#!/usr/bin/env bash
# =============================================================================
# tilix-update.sh — keep Cytracon Tilix current from GitHub Releases
#
# Public repo: https://github.com/cytracon/tilix
# No token required. Uses git tags + direct release asset URLs (no API rate limit).
#
# Usage:
#   tilix-update                 # install latest if newer
#   tilix-update --check         # status only (0=ok, 1=update, 2=error)
#   tilix-update --force         # reinstall latest
#   tilix-update --tag v1.9.8-cytracon.9
#   tilix-update --install-timer # daily systemd --user timer
# =============================================================================
set -euo pipefail

REPO="${TILIX_REPO:-cytracon/tilix}"
PREFIX="${TILIX_PREFIX:-$HOME/.local}"
GIT_URL="${TILIX_GIT_URL:-https://github.com/${REPO}.git}"
WEB="https://github.com/${REPO}"
CHECK_ONLY=0
FORCE=0
WANT_TAG=""
INSTALL_TIMER=0

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    --tag=*) WANT_TAG="${arg#--tag=}" ;;
    --tag)   NEXT_TAG=1 ;;
    --install-timer) INSTALL_TIMER=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      if [[ "${NEXT_TAG:-0}" == 1 ]]; then
        WANT_TAG="$arg"
        NEXT_TAG=0
      fi
      ;;
  esac
done

log()  { printf '[tilix-update] %s\n' "$*"; }
err()  { printf '[tilix-update] ERROR: %s\n' "$*" >&2; }
die()  { err "$*"; exit 2; }

resolve_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then echo "$GITHUB_TOKEN"; return; fi
  if [[ -n "${GH_TOKEN:-}" ]]; then echo "$GH_TOKEN"; return; fi
  local f
  for f in \
    "${HOME}/.config/tilix/github-token" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/tilix/github-token" \
    /root/.github-token
  do
    if [[ -f "$f" && -r "$f" ]]; then tr -d '[:space:]' < "$f"; return; fi
  done
  local hosts="${HOME}/.config/gh/hosts.yml"
  if [[ -f "$hosts" ]]; then
    local t
    t="$(sed -n 's/.*oauth_token:[[:space:]]*//p' "$hosts" | head -1 | tr -d '[:space:]')"
    [[ -n "$t" ]] && { echo "$t"; return; }
  fi
  return 1
}

normalize_ver() {
  local v="${1#v}"
  echo "$v"
}

installed_version() {
  local bin=""
  for b in "$PREFIX/libexec/tilix" "$PREFIX/bin/tilix" "$(command -v tilix 2>/dev/null || true)"; do
    if [[ -n "$b" && -x "$b" ]]; then
      if file "$b" 2>/dev/null | grep -qi 'ELF'; then
        bin="$b"; break
      elif [[ -x "$PREFIX/libexec/tilix" ]]; then
        bin="$PREFIX/libexec/tilix"; break
      fi
    fi
  done
  [[ -z "$bin" ]] && { echo ""; return; }
  "$bin" --version 2>/dev/null \
    | sed -n 's/.*Tilix version:[[:space:]]*//p' \
    | head -1 | tr -d '[:space:]' || true
}

# Sort cytracon tags: prefer higher .N after cytracon.
# Input: list of tags like v1.9.8-cytracon.9
latest_cytracon_tag() {
  # version-sort works well for v1.9.8-cytracon.N
  sort -V | tail -1
}

# Discover latest cytracon tag via git (no GitHub API)
fetch_latest_tag() {
  local tags
  tags="$(git ls-remote --tags --refs "$GIT_URL" 'refs/tags/v*-cytracon.*' 2>/dev/null \
    | awk '{print $2}' | sed 's|refs/tags/||' || true)"
  if [[ -z "$tags" ]]; then
    # broader pattern (some tags without leading v)
    tags="$(git ls-remote --tags --refs "$GIT_URL" 2>/dev/null \
      | awk '{print $2}' | sed 's|refs/tags/||' | grep -E 'cytracon\.[0-9]+$' || true)"
  fi
  [[ -n "$tags" ]] || return 1
  echo "$tags" | latest_cytracon_tag
}

# Probe whether a release asset exists (public download URL)
asset_candidates() {
  local tag="$1"
  local ver
  ver="$(normalize_ver "$tag")"
  # naming from package-tilix.sh
  echo "tilix-cytracon-${ver}-linux-x86_64.tar.gz"
  # alternate: dots → underscores (older sanitize)
  echo "tilix-cytracon-$(echo "$ver" | tr '.' '_')-linux-x86_64.tar.gz"
}

probe_asset() {
  local tag="$1"
  local name url code
  for name in $(asset_candidates "$tag"); do
    url="${WEB}/releases/download/${tag}/${name}"
    code="$(curl -sI -o /dev/null -w '%{http_code}' -L "$url" 2>/dev/null || echo 000)"
    if [[ "$code" == "200" ]]; then
      echo "$name|$url"
      return 0
    fi
  done
  return 1
}

# Walk tags newest-first until one has a release asset
find_latest_release() {
  local all tag hit
  all="$(git ls-remote --tags --refs "$GIT_URL" 'refs/tags/v*-cytracon.*' 2>/dev/null \
    | awk '{print $2}' | sed 's|refs/tags/||' | sort -V -r || true)"
  if [[ -z "$all" ]]; then
    all="$(git ls-remote --tags --refs "$GIT_URL" 2>/dev/null \
      | awk '{print $2}' | sed 's|refs/tags/||' | grep -E 'cytracon\.[0-9]+$' | sort -V -r || true)"
  fi
  [[ -n "$all" ]] || return 1
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if hit="$(probe_asset "$tag")"; then
      echo "${tag}|${hit}"
      return 0
    fi
  done <<< "$all"
  return 1
}

install_timer() {
  local unit_dir="${HOME}/.config/systemd/user"
  mkdir -p "$unit_dir"
  local self
  self="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  if [[ -x "$PREFIX/bin/tilix-update" ]]; then
    self="$PREFIX/bin/tilix-update"
  else
    install -Dm755 "$self" "$PREFIX/bin/tilix-update"
    self="$PREFIX/bin/tilix-update"
  fi

  cat > "$unit_dir/tilix-update.service" << EOF
[Unit]
Description=Update Cytracon Tilix from GitHub Releases
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${self}
Nice=10
EOF

  cat > "$unit_dir/tilix-update.timer" << 'EOF'
[Unit]
Description=Daily Cytracon Tilix update check

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=45m

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now tilix-update.timer
  log "Timer enabled (systemd --user)."
  systemctl --user status tilix-update.timer --no-pager 2>/dev/null | head -12 || true
}

if [[ "$INSTALL_TIMER" == 1 ]]; then
  install_timer
  exit 0
fi

TOKEN=""
TOKEN="$(resolve_token 2>/dev/null || true)"

CUR="$(normalize_ver "$(installed_version)")"
log "Installed: ${CUR:-<none>}"
log "Repo:      ${WEB} (public)"

REL_TAG=""
ASSET_NAME=""
ASSET_URL=""

if [[ -n "$WANT_TAG" ]]; then
  REL_TAG="$WANT_TAG"
  [[ "$REL_TAG" == v* ]] || REL_TAG="v${REL_TAG}"
  log "Requested tag: ${REL_TAG}"
  if hit="$(probe_asset "$REL_TAG")"; then
    ASSET_NAME="${hit%%|*}"
    ASSET_URL="${hit#*|}"
  else
    die "No release asset for ${REL_TAG}.
Publish first:  cd ~/src/tilix && ./scripts/publish-github-release.sh
Or open: ${WEB}/releases"
  fi
else
  log "Looking for latest release with linux package…"
  if found="$(find_latest_release)"; then
    # tag|name|url
    REL_TAG="${found%%|*}"
    rest="${found#*|}"
    ASSET_NAME="${rest%%|*}"
    ASSET_URL="${rest#*|}"
  else
    # Helpful diagnostics
    latest_tag="$(fetch_latest_tag || true)"
    die "Kein GitHub Release mit Package gefunden.
Tags existieren${latest_tag:+ (latest tag: $latest_tag)}, aber noch kein Release-Asset.
Auf dem Build-PC:
  cd ~/src/tilix
  git push origin master --tags
  ./scripts/publish-github-release.sh
Danach hier erneut: tilix-update
Seite: ${WEB}/releases"
  fi
fi

NEW="$(normalize_ver "$REL_TAG")"
log "Latest:    ${NEW}  (${ASSET_NAME})"

if [[ "$CHECK_ONLY" == 1 ]]; then
  if [[ -n "$CUR" && "$CUR" == "$NEW" ]]; then
    log "Up to date."
    exit 0
  fi
  log "Update available: ${CUR:-none} → ${NEW}"
  exit 1
fi

if [[ "$FORCE" != 1 && -n "$CUR" && "$CUR" == "$NEW" ]]; then
  log "Already on ${CUR} — nothing to do (use --force to reinstall)."
  exit 0
fi

TMP="$(mktemp -d /tmp/tilix-update.XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

TAR="${TMP}/${ASSET_NAME}"
log "Downloading ${ASSET_URL}…"
# Public browser download — no API, no rate limit
if ! curl -fsSL -L -o "$TAR" "$ASSET_URL"; then
  # optional API fallback with token
  if [[ -n "$TOKEN" ]]; then
    log "Direct download failed; trying API with token…"
    api="https://api.github.com/repos/${REPO}/releases/tags/${REL_TAG}"
    json="$(curl -fsSL \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "$api")" || die "API fallback failed."
    api_url="$(echo "$json" | python3 -c "
import json,sys
j=json.load(sys.stdin)
for a in j.get('assets') or []:
  if (a.get('name') or '').endswith('linux-x86_64.tar.gz'):
    print(a['url']); break
")"
    [[ -n "$api_url" ]] || die "No asset in API response."
    curl -fsSL -L \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/octet-stream" \
      -o "$TAR" "$api_url" || die "Download failed."
  else
    die "Download failed (is the release published?). ${WEB}/releases"
  fi
fi

[[ -s "$TAR" ]] || die "Download empty."
file "$TAR" | grep -qi 'gzip\|tar' || die "Not a tar.gz: $(file -b "$TAR")"

log "Extracting…"
tar -xzf "$TAR" -C "$TMP"
STAGE="$(find "$TMP" -maxdepth 2 -type f \( -name 'install-remote.sh' -o -name 'install-from-package.sh' \) -printf '%h\n' | head -1)"
[[ -n "$STAGE" && -d "$STAGE" ]] || die "Unexpected package layout."

if [[ -x "$STAGE/install-from-package.sh" ]]; then
  INSTALLER="$STAGE/install-from-package.sh"
else
  INSTALLER="$STAGE/install-remote.sh"
fi

install -Dm755 "$0" "$PREFIX/bin/tilix-update" 2>/dev/null || true

log "Installing into ${PREFIX}…"
PREFIX="$PREFIX" bash "$INSTALLER"

if [[ -x "$STAGE/bin/tilix-update" ]]; then
  install -Dm755 "$STAGE/bin/tilix-update" "$PREFIX/bin/tilix-update"
fi
# Always keep this (newest) updater
install -Dm755 "$0" "$PREFIX/bin/tilix-update" 2>/dev/null || true

NEW_INST="$(normalize_ver "$(installed_version)")"
log "Now running: ${NEW_INST:-?}"
if [[ -n "$NEW_INST" && "$NEW_INST" != "$NEW" ]]; then
  err "Version mismatch after install (expected $NEW, got $NEW_INST)."
  exit 2
fi

log "OK. Fully quit Tilix (pkill -x tilix) and start again to load the new binary."
