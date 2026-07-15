#!/usr/bin/env bash
# =============================================================================
# publish-github-release.sh
#
# From the build machine: package local binary + push git tag + create
# GitHub Release with the tarball asset (no GitHub Actions required).
#
# Prerequisites:
#   - Built binary (~/.local/libexec/tilix or ./tilix)
#   - Git remote origin → cytracon/tilix
#   - Token with contents:write (GITHUB_TOKEN / ~/.config/tilix/github-token / /root/.github-token)
#
# Usage:
#   ./scripts/publish-github-release.sh              # version from binary
#   ./scripts/publish-github-release.sh --dry-run
#   ./scripts/publish-github-release.sh --skip-push   # tag/release only, no git push
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "${SCRIPT_DIR}/../source/gx/tilix" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -d "${HOME}/src/tilix/source/gx/tilix" ]]; then
  REPO_ROOT="$(cd "${HOME}/src/tilix" && pwd)"
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

REPO="${TILIX_REPO:-cytracon/tilix}"
PKG_DIR="${PKG_DIR:-/tmp}"
DRY=0
SKIP_PUSH=0

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --skip-push) SKIP_PUSH=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \?//'; exit 0 ;;
  esac
done

log() { printf '[publish] %s\n' "$*"; }
die() { printf '[publish] ERROR: %s\n' "$*" >&2; exit 1; }

resolve_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then echo "$GITHUB_TOKEN"; return; fi
  if [[ -n "${GH_TOKEN:-}" ]]; then echo "$GH_TOKEN"; return; fi
  for f in \
    "${HOME}/.config/tilix/github-token" \
    /root/.github-token
  do
    if [[ -f "$f" && -r "$f" ]]; then tr -d '[:space:]' < "$f"; return; fi
  done
  # try sudo root token (desktop)
  if [[ -r /root/.github-token ]]; then
    tr -d '[:space:]' < /root/.github-token
    return
  fi
  if sudo -n test -r /root/.github-token 2>/dev/null; then
    sudo -n cat /root/.github-token | tr -d '[:space:]'
    return
  fi
  return 1
}

export PKG_DIR
cd "$REPO_ROOT"
[[ -x scripts/package-tilix.sh ]] || die "package-tilix.sh missing"
log "Building package…"
TAR="$(bash scripts/package-tilix.sh | tail -1)"
[[ -n "$TAR" && -f "$TAR" ]] || die "Package not created."

BIN=""
for b in "$HOME/.local/libexec/tilix" "$REPO_ROOT/tilix"; do
  [[ -x "$b" ]] && file "$b" | grep -qi ELF && BIN="$b" && break
done
[[ -n "$BIN" ]] || die "No binary for version detection."
VERSION="$("$BIN" --version 2>/dev/null | sed -n 's/.*Tilix version:[[:space:]]*//p' | head -1 | tr -d '[:space:]')"
VERSION="${VERSION:-unknown}"
TAG="v${VERSION}"
# already has v?
[[ "$VERSION" == v* ]] && TAG="$VERSION"
TAG="${TAG#vv}"  # guard
[[ "$TAG" == v* ]] || TAG="v${TAG}"

log "Version: $VERSION"
log "Tag:     $TAG"
log "Package: $TAR ($(du -h "$TAR" | awk '{print $1}'))"

TOKEN=""
TOKEN="$(resolve_token)" || die "No GitHub token (need contents:write)."

if [[ "$DRY" == 1 ]]; then
  log "DRY-RUN: would tag $TAG, push, create release with $(basename "$TAR")"
  exit 0
fi

# Ensure install-from-package is inside tarball for tilix-update
# (deploy script uses install-remote.sh — fine)

# Git tag if missing
if git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
  log "Tag $TAG already exists locally."
else
  git -C "$REPO_ROOT" tag -a "$TAG" -m "Cytracon Tilix $VERSION"
  log "Created tag $TAG"
fi

if [[ "$SKIP_PUSH" != 1 ]]; then
  log "Pushing commits + tags to origin…"
  git -C "$REPO_ROOT" push origin HEAD
  git -C "$REPO_ROOT" push origin "$TAG" || git -C "$REPO_ROOT" push origin --tags
fi

# Create release via API (idempotent-ish)
API="https://api.github.com/repos/${REPO}"
AUTH=( -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" )

REL_JSON="$(curl -fsSL "${AUTH[@]}" "${API}/releases/tags/${TAG}" 2>/dev/null || true)"
REL_ID=""
if [[ -n "$REL_JSON" ]] && echo "$REL_JSON" | grep -q '"id"'; then
  REL_ID="$(echo "$REL_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
  log "Release exists (id=$REL_ID) — will upload/replace asset."
else
  log "Creating release $TAG…"
  BODY="Cytracon Tilix **${VERSION}**

### Update on any PC
\`\`\`bash
# Token once: ~/.config/tilix/github-token (contents:read)
tilix-update
# or:
curl -fsSL -H \"Authorization: Bearer \$(cat ~/.config/tilix/github-token)\" \\
  -H \"Accept: application/vnd.github.raw\" \\
  https://api.github.com/repos/cytracon/tilix/contents/scripts/tilix-update.sh?ref=master \\
  -o /tmp/tilix-update.sh && bash /tmp/tilix-update.sh
\`\`\`
"
  REL_JSON="$(curl -fsSL "${AUTH[@]}" -X POST "${API}/releases" \
    -d "$(python3 - <<PY
import json
print(json.dumps({
  "tag_name": "${TAG}",
  "name": "Tilix ${VERSION}",
  "body": """${BODY}""",
  "draft": False,
  "prerelease": False,
}))
PY
)")"
  REL_ID="$(echo "$REL_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  log "Created release id=$REL_ID"
fi

[[ -n "$REL_ID" ]] || die "Could not resolve release id."

ASSET_NAME="$(basename "$TAR")"
# Delete existing asset with same name
EXISTING="$(curl -fsSL "${AUTH[@]}" "${API}/releases/${REL_ID}/assets" \
  | python3 -c "import json,sys; 
assets=json.load(sys.stdin)
for a in assets:
  if a.get('name')=='''${ASSET_NAME}''':
    print(a['id']); break" 2>/dev/null || true)"
if [[ -n "$EXISTING" ]]; then
  log "Deleting old asset id=$EXISTING…"
  curl -fsSL "${AUTH[@]}" -X DELETE "${API}/releases/assets/${EXISTING}" >/dev/null
fi

log "Uploading ${ASSET_NAME}…"
UPLOAD_URL="https://uploads.github.com/repos/${REPO}/releases/${REL_ID}/assets?name=${ASSET_NAME}"
curl -fsSL "${AUTH[@]}" \
  -H "Content-Type: application/gzip" \
  --data-binary @"${TAR}" \
  "$UPLOAD_URL" | python3 -c 'import json,sys; j=json.load(sys.stdin); print("asset:", j.get("name"), j.get("browser_download_url","")[:80])'

log "Done. Latest: https://github.com/${REPO}/releases/tag/${TAG}"
log "On other PCs: tilix-update"
