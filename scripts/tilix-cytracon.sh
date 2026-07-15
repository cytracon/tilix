#!/usr/bin/env bash
# =============================================================================
# tilix-cytracon.sh  —  ALLES in EINEM Script
#
#   install / update / package / publish / timer / help
#
# Auf JEDEM PC (kein LDC, kein Root):
#   bash tilix-cytracon.sh              # install/update (GitHub oder lokal)
#   tilix-update                        # gleicher Befehl nach Install
#   tilix-cytracon --timer              # täglicher Auto-Update
#   tilix-cytracon --check
#   tilix-cytracon --force
#
# Ohne Clone:
#   curl -fsSL https://raw.githubusercontent.com/cytracon/tilix/master/scripts/tilix-cytracon.sh | bash
#
# Offline (Package in Downloads/Drive/tmp):
#   bash tilix-cytracon.sh              # findet tilix-cytracon-*.tar.gz automatisch
#   TILIX_TARBALL=/pfad/x.tar.gz bash tilix-cytracon.sh
#
# Build-PC (Binary schon gebaut):
#   tilix-cytracon package              # → /tmp/tilix-cytracon-…tar.gz
#   tilix-cytracon publish              # package + git push + GitHub Release
#   GITHUB_TOKEN=ghp_… tilix-cytracon publish
#
# Env: TILIX_PREFIX TILIX_REPO TILIX_BIN TILIX_TARBALL PKG_DIR GITHUB_TOKEN
# =============================================================================
set -euo pipefail

REPO="${TILIX_REPO:-cytracon/tilix}"
PREFIX="${TILIX_PREFIX:-$HOME/.local}"
PKG_DIR="${PKG_DIR:-/tmp}"
STAGE_NAME="tilix-cytracon-deploy"
GIT_URL="${TILIX_GIT_URL:-https://github.com/${REPO}.git}"
WEB="https://github.com/${REPO}"
RAW_SELF="https://raw.githubusercontent.com/${REPO}/master/scripts/tilix-cytracon.sh"
API="https://api.github.com/repos/${REPO}"

CMD="update"
CHECK_ONLY=0
FORCE=0
DO_TIMER=0
WANT_TAG=""
SKIP_PUSH=0
DRY=0

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \?//'
}

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    install|update|package|publish|timer|help|-h|--help)
      CMD="$1"; [[ "$1" == help || "$1" == -h || "$1" == --help ]] && CMD=help
      shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --timer|--install-timer) DO_TIMER=1; shift ;;
    --tag) WANT_TAG="${2:-}"; shift 2 ;;
    --tag=*) WANT_TAG="${1#--tag=}"; shift ;;
    --skip-push) SKIP_PUSH=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) CMD=help; shift ;;
    *)
      # bare script name aliases
      if [[ "$1" == *-update || "$1" == install-tilix-cytracon* ]]; then shift; continue; fi
      err_unknown="$1"; shift
      echo "Unbekanntes Argument: $err_unknown" >&2
      usage; exit 2
      ;;
  esac
done
# default command if invoked as tilix-update
base="$(basename "${0:-tilix-cytracon}" 2>/dev/null || echo tilix-cytracon)"
if [[ "$CMD" == "update" && "$base" == "tilix-update" ]]; then CMD=update; fi
if [[ "$CMD" == "timer" ]]; then DO_TIMER=1; CMD=update; fi

log()  { printf '\033[36m[tilix]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[tilix]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[tilix]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 2; }

need() { command -v "$1" >/dev/null 2>&1 || die "Befehl fehlt: $1"; }

normalize_ver() { echo "${1#v}"; }

self_path() {
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}"
  elif [[ -n "${0:-}" && -f "$0" ]]; then
    readlink -f "$0" 2>/dev/null || echo "$0"
  else
    echo ""
  fi
}

repo_root() {
  local d s
  s="$(self_path)"
  if [[ -n "$s" && -d "$(dirname "$s")/../source/gx/tilix" ]]; then
    cd "$(dirname "$s")/.." && pwd; return
  fi
  if [[ -d "${HOME}/src/tilix/source/gx/tilix" ]]; then
    echo "${HOME}/src/tilix"; return
  fi
  echo ""
}

# =============================================================================
# Token
# =============================================================================
resolve_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then echo "$GITHUB_TOKEN"; return; fi
  if [[ -n "${GH_TOKEN:-}" ]]; then echo "$GH_TOKEN"; return; fi
  local f
  for f in \
    "${HOME}/.config/tilix/github-token" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/tilix/github-token" \
    /root/.github-token
  do
    if [[ -r "$f" ]]; then tr -d '[:space:]' < "$f"; return; fi
  done
  if sudo -n test -r /root/.github-token 2>/dev/null; then
    sudo -n cat /root/.github-token | tr -d '[:space:]'; return
  fi
  local hosts="${HOME}/.config/gh/hosts.yml"
  if [[ -f "$hosts" ]]; then
    local t
    t="$(sed -n 's/.*oauth_token:[[:space:]]*//p' "$hosts" | head -1 | tr -d '[:space:]')"
    [[ -n "$t" ]] && { echo "$t"; return; }
  fi
  return 1
}

# =============================================================================
# Version / binary
# =============================================================================
installed_version() {
  local bin=""
  if [[ -x "$PREFIX/libexec/tilix" ]] && file "$PREFIX/libexec/tilix" 2>/dev/null | grep -qi ELF; then
    bin="$PREFIX/libexec/tilix"
  fi
  [[ -z "$bin" ]] && { echo ""; return; }
  "$bin" --version 2>/dev/null \
    | sed -n 's/.*Tilix version:[[:space:]]*//p' \
    | head -1 | tr -d '[:space:]' || true
}

resolve_binary() {
  if [[ -n "${TILIX_BIN:-}" && -x "$TILIX_BIN" ]]; then echo "$TILIX_BIN"; return; fi
  local r b
  r="$(repo_root)"
  for b in \
    ${r:+"$r/tilix"} \
    "$HOME/.local/libexec/tilix" \
    "$HOME/.local/bin/tilix-cytracon"
  do
    [[ -n "$b" && -x "$b" ]] || continue
    file "$b" 2>/dev/null | grep -qi ELF && { echo "$b"; return; }
  done
  return 1
}

ensure_path() {
  case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) export PATH="$PREFIX/bin:$PATH" ;; esac
  if [[ -f "$HOME/.profile" ]] && ! grep -q '\.local/bin' "$HOME/.profile" 2>/dev/null; then
    {
      echo ''
      echo '# Cytracon user binaries (Tilix)'
      echo 'if [ -d "$HOME/.local/bin" ] ; then PATH="$HOME/.local/bin:$PATH"; fi'
    } >> "$HOME/.profile"
  fi
}

# =============================================================================
# Install this script as tilix-update + tilix-cytracon + install-tilix-cytracon
# =============================================================================
install_self() {
  local src="${1:-}"
  mkdir -p "$PREFIX/bin"
  if [[ -z "$src" || ! -f "$src" ]]; then src="$(self_path)"; fi
  if [[ -z "$src" || ! -f "$src" ]]; then
    local tmp; tmp="$(mktemp)"
    if curl -fsSL "$RAW_SELF" -o "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      src="$tmp"
    else
      rm -f "$tmp"; return 0
    fi
  fi
  local d
  for d in tilix-cytracon tilix-update install-tilix-cytracon; do
    local dest="$PREFIX/bin/$d"
    if [[ "$(readlink -f "$src" 2>/dev/null || echo "$src")" == \
          "$(readlink -f "$dest" 2>/dev/null || echo "$dest")" ]]; then
      continue
    fi
    cp -f "$src" "$dest"
    chmod 755 "$dest"
  done
  # ensure all three exist
  for d in tilix-cytracon tilix-update install-tilix-cytracon; do
    [[ -x "$PREFIX/bin/$d" ]] || { cp -f "$src" "$PREFIX/bin/$d"; chmod 755 "$PREFIX/bin/$d"; }
  done
  ok "Befehle: tilix-update · tilix-cytracon  ($PREFIX/bin)"
}

install_timer() {
  local unit_dir="${HOME}/.config/systemd/user"
  local exe="$PREFIX/bin/tilix-update"
  [[ -x "$exe" ]] || { install_self; exe="$PREFIX/bin/tilix-update"; }
  mkdir -p "$unit_dir"
  cat > "$unit_dir/tilix-update.service" << EOF
[Unit]
Description=Cytracon Tilix aktualisieren
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=${exe}
Nice=10
EOF
  cat > "$unit_dir/tilix-update.timer" << 'EOF'
[Unit]
Description=Tägliches Cytracon-Tilix-Update
[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=45m
[Install]
WantedBy=timers.target
EOF
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable --now tilix-update.timer
    ok "Timer aktiv (täglich)."
    systemctl --user status tilix-update.timer --no-pager 2>/dev/null | head -8 || true
  else
    err "systemctl fehlt — Timer-Dateien in $unit_dir"
  fi
}

# =============================================================================
# Package (embeds THIS script as updater + inline installer)
# =============================================================================
cmd_package() {
  need file; need tar
  local bin version ver_file tar stage
  bin="$(resolve_binary)" || die "Kein Tilix-Binary. Bauen: dub build --compiler=ldc2 --build=release"
  version="$("$bin" --version 2>/dev/null | sed -n 's/.*Tilix version:[[:space:]]*//p' | head -1 | tr -d '[:space:]')"
  version="${version:-unknown}"
  ver_file="$(echo "$version" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_\+$//')"
  tar="${PKG_DIR}/tilix-cytracon-${ver_file}-linux-x86_64.tar.gz"
  stage="${PKG_DIR}/${STAGE_NAME}"

  log "Binary:  $bin"
  log "Version: $version"
  log "Package: $tar"

  rm -rf "$stage"
  mkdir -p "$stage"/{bin,libexec,share/glib-2.0/schemas,share/applications,share/nemo/actions}

  install -Dm755 "$bin" "$stage/libexec/tilix"

  # Wrapper
  cat > "$stage/bin/tilix" << 'WRAP'
#!/usr/bin/env bash
set -euo pipefail
PREFIX="${HOME}/.local"
export GSETTINGS_SCHEMA_DIR="${PREFIX}/share/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:${GSETTINGS_SCHEMA_DIR}}"
export XDG_DATA_DIRS="${PREFIX}/share${XDG_DATA_DIRS:+:${XDG_DATA_DIRS}}"
case ":${XDG_DATA_DIRS}:" in
  *:/usr/share:*) ;;
  *) export XDG_DATA_DIRS="${XDG_DATA_DIRS}:/usr/local/share:/usr/share" ;;
esac
exec "${PREFIX}/libexec/tilix" "$@"
WRAP
  chmod 755 "$stage/bin/tilix"

  # Embed this all-in-one script
  local me; me="$(self_path)"
  if [[ -n "$me" && -f "$me" ]]; then
    install -Dm755 "$me" "$stage/bin/tilix-update"
    install -Dm755 "$me" "$stage/bin/tilix-cytracon"
  fi

  local r; r="$(repo_root)"
  if [[ -n "$r" && -f "$r/scripts/tilix-open-location" ]]; then
    install -Dm755 "$r/scripts/tilix-open-location" "$stage/bin/tilix-open-location"
  fi

  local schema=""
  for s in \
    ${r:+"$r/data/gsettings/com.gexperts.Tilix.gschema.xml"} \
    "$HOME/.local/share/glib-2.0/schemas/com.gexperts.Tilix.gschema.xml"
  do
    [[ -n "$s" && -f "$s" ]] && { schema="$s"; break; }
  done
  [[ -n "$schema" ]] || die "GSettings schema nicht gefunden."
  install -Dm644 "$schema" "$stage/share/glib-2.0/schemas/"
  glib-compile-schemas "$stage/share/glib-2.0/schemas/" 2>/dev/null || true

  cat > "$stage/share/applications/com.gexperts.Tilix.desktop" << EOF
[Desktop Entry]
Version=1.1
Type=Application
Name=Tilix (Cytracon)
Name[de]=Tilix (Cytracon)
GenericName=Terminal
Comment=Cytracon Tilix ${version}
Comment[de]=Cytracon Tilix ${version}
Keywords=shell;prompt;command;commandline;cmd;terminal;tilix;cytracon;
Exec=__HOME__/.local/bin/tilix %F
TryExec=__HOME__/.local/bin/tilix
Icon=com.gexperts.Tilix
Terminal=false
Categories=System;TerminalEmulator;X-GNOME-Utilities;
StartupNotify=true
StartupWMClass=com.gexperts.Tilix
DBusActivatable=false
Actions=new-window;new-session;preferences;

[Desktop Action new-window]
Name=New Window
Name[de]=Neues Fenster
Exec=__HOME__/.local/bin/tilix --action=app-new-window

[Desktop Action new-session]
Name=New Session
Name[de]=Neue Sitzung
Exec=__HOME__/.local/bin/tilix --action=app-new-session

[Desktop Action preferences]
Name=Preferences
Name[de]=Einstellungen
Exec=__HOME__/.local/bin/tilix --preferences
EOF

  # Inline package installer (no external script dependency)
  cat > "$stage/install-remote.sh" << 'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
echo ">>> Installing Cytracon Tilix on $(hostname) as $(whoami)"
echo ">>> Target: $PREFIX"
mkdir -p "$PREFIX"/{bin,libexec,share/glib-2.0/schemas,share/applications,share/nemo/actions}
install -Dm755 "$HERE/libexec/tilix" "$PREFIX/libexec/tilix"
install -Dm755 "$HERE/bin/tilix" "$PREFIX/bin/tilix"
for f in tilix-update tilix-cytracon install-tilix-cytracon tilix-open-location; do
  [[ -f "$HERE/bin/$f" ]] && install -Dm755 "$HERE/bin/$f" "$PREFIX/bin/$f"
done
# aliases
[[ -x "$PREFIX/bin/tilix-update" ]] || true
if [[ -x "$PREFIX/bin/tilix-update" ]]; then
  cp -f "$PREFIX/bin/tilix-update" "$PREFIX/bin/tilix-cytracon" 2>/dev/null || true
  cp -f "$PREFIX/bin/tilix-update" "$PREFIX/bin/install-tilix-cytracon" 2>/dev/null || true
  chmod 755 "$PREFIX/bin/tilix-cytracon" "$PREFIX/bin/install-tilix-cytracon" 2>/dev/null || true
fi
install -Dm644 "$HERE/share/glib-2.0/schemas/com.gexperts.Tilix.gschema.xml" "$PREFIX/share/glib-2.0/schemas/"
[[ -f "$HERE/share/glib-2.0/schemas/gschemas.compiled" ]] && \
  install -Dm644 "$HERE/share/glib-2.0/schemas/gschemas.compiled" "$PREFIX/share/glib-2.0/schemas/" || true
glib-compile-schemas "$PREFIX/share/glib-2.0/schemas/" 2>/dev/null || true
if [[ -f "$HERE/share/applications/com.gexperts.Tilix.desktop" ]]; then
  sed "s|__HOME__|${HOME}|g" "$HERE/share/applications/com.gexperts.Tilix.desktop" \
    > "$PREFIX/share/applications/com.gexperts.Tilix.desktop"
  update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
fi
if [[ -x "$PREFIX/bin/tilix-open-location" ]]; then
  BIN="$PREFIX/bin/tilix-open-location"; ACT="$PREFIX/share/nemo/actions"
  cat > "$ACT/open-tilix-here.nemo_action" << EOF
[Nemo Action]
Active=true
Name=Open Tilix Here
Name[de]=Tilix hier öffnen
Exec=$BIN %P
Selection=none
Extensions=any;
Icon-Name=com.gexperts.Tilix
EscapeSpaces=true
Quote=double
EOF
  cat > "$ACT/open-tilix-dir.nemo_action" << EOF
[Nemo Action]
Active=true
Name=Open in Tilix
Name[de]=In Tilix öffnen
Exec=$BIN %F
Selection=s
Extensions=dir;
Icon-Name=com.gexperts.Tilix
EscapeSpaces=true
Quote=double
EOF
  cat > "$ACT/open-tilix-uri.nemo_action" << EOF
[Nemo Action]
Active=true
Name=Open Remote Tilix
Name[de]=Remote Tilix öffnen
Exec=$BIN %U
Selection=s
Extensions=dir;
Icon-Name=com.gexperts.Tilix
EscapeSpaces=true
Quote=double
EOF
fi
if [[ -f "$HOME/.profile" ]] && ! grep -q '\.local/bin' "$HOME/.profile" 2>/dev/null; then
  echo '' >> "$HOME/.profile"
  echo 'if [ -d "$HOME/.local/bin" ] ; then PATH="$HOME/.local/bin:$PATH"; fi' >> "$HOME/.profile"
fi
export PATH="$PREFIX/bin:$PATH"
export GSETTINGS_SCHEMA_DIR="$PREFIX/share/glib-2.0/schemas"
echo ">>> Verify"
"$PREFIX/libexec/tilix" --version 2>&1 | head -8
echo ">>> Done on $(hostname)"
REMOTE
  chmod 755 "$stage/install-remote.sh"
  cp -f "$stage/install-remote.sh" "$stage/install-from-package.sh"

  tar -C "$PKG_DIR" -czf "$tar" "$STAGE_NAME"
  echo "$tar" > "${PKG_DIR}/tilix-cytracon-latest.pkgpath"
  PACKAGE_TAR="$tar"
  ok "Package: $tar ($(du -h "$tar" | awk '{print $1}'))"

  # also drop into Downloads / Drive for other PCs
  for d in \
    "$HOME/Downloads" \
    "$HOME/Google Drive/BBachmann/Downloads"
  do
    if [[ -d "$d" ]]; then
      cp -f "$tar" "$d/"
      me="$(self_path)"; [[ -n "$me" && -f "$me" ]] && cp -f "$me" "$d/tilix-cytracon.sh"
      log "Kopie → $d/"
    fi
  done
}

# =============================================================================
# Publish to GitHub Releases
# =============================================================================
cmd_publish() {
  need curl; need python3; need git
  local token tar version tag rel_id asset_name
  token="$(resolve_token)" || die "GITHUB_TOKEN fehlt (Write).
  export GITHUB_TOKEN=ghp_…
  oder:  echo ghp_… > ~/.config/tilix/github-token && chmod 600 ~/.config/tilix/github-token"

  log "Baue Package…"
  PACKAGE_TAR=""
  cmd_package
  tar="${PACKAGE_TAR:-}"
  [[ -n "$tar" && -f "$tar" ]] || die "Package fehlgeschlagen."

  local bin; bin="$(resolve_binary)"
  version="$("$bin" --version 2>/dev/null | sed -n 's/.*Tilix version:[[:space:]]*//p' | head -1 | tr -d '[:space:]')"
  version="${version:-unknown}"
  tag="v${version#v}"
  asset_name="$(basename "$tar")"

  log "Tag: $tag  Asset: $asset_name"
  if [[ "$DRY" == 1 ]]; then
    log "DRY-RUN — kein Push/Release."
    exit 0
  fi

  local r; r="$(repo_root)"
  if [[ -n "$r" && -d "$r/.git" ]]; then
    if ! git -C "$r" rev-parse "$tag" >/dev/null 2>&1; then
      git -C "$r" tag -a "$tag" -m "Cytracon Tilix $version" || true
    fi
    if [[ "$SKIP_PUSH" != 1 ]]; then
      log "git push…"
      # use token for HTTPS push if needed
      local origin
      origin="$(git -C "$r" remote get-url origin 2>/dev/null || true)"
      if [[ "$origin" == https://github.com/* ]]; then
        git -C "$r" -c "http.extraHeader=Authorization: Bearer ${token}" push origin HEAD || \
          git -C "$r" push origin HEAD || err "git push HEAD fehlgeschlagen — manuell pushen"
        git -C "$r" -c "http.extraHeader=Authorization: Bearer ${token}" push origin "$tag" || \
          git -C "$r" push origin "$tag" || err "git push tag fehlgeschlagen"
      else
        git -C "$r" push origin HEAD || true
        git -C "$r" push origin "$tag" || true
      fi
    fi
  fi

  local auth=( -H "Authorization: Bearer ${token}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" )
  local rel_json
  rel_json="$(curl -fsSL "${auth[@]}" "${API}/releases/tags/${tag}" 2>/dev/null || true)"
  if echo "${rel_json:-}" | grep -q '"id"'; then
    rel_id="$(echo "$rel_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
    log "Release existiert (id=$rel_id)"
  else
    log "Erzeuge Release $tag…"
    rel_json="$(curl -fsSL "${auth[@]}" -X POST "${API}/releases" \
      -d "$(python3 -c "
import json
print(json.dumps({
  'tag_name': '''${tag}''',
  'name': '''Tilix ${version}''',
  'body': '''Cytracon Tilix ${version}

### Install / Update (jeder PC)
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/cytracon/tilix/master/scripts/tilix-cytracon.sh | bash
# danach: tilix-update
\`\`\`
''',
  'draft': False,
  'prerelease': False,
}))
")")"
    rel_id="$(echo "$rel_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  fi
  [[ -n "$rel_id" ]] || die "Release-ID unbekannt."

  # delete existing asset with same name
  local old
  old="$(curl -fsSL "${auth[@]}" "${API}/releases/${rel_id}/assets" \
    | python3 -c "import json,sys
for a in json.load(sys.stdin):
  if a.get('name')=='''${asset_name}''':
    print(a['id']); break" 2>/dev/null || true)"
  if [[ -n "$old" ]]; then
    curl -fsSL "${auth[@]}" -X DELETE "${API}/releases/assets/${old}" >/dev/null
  fi

  log "Upload $asset_name…"
  curl -fsSL "${auth[@]}" \
    -H "Content-Type: application/gzip" \
    --data-binary @"${tar}" \
    "https://uploads.github.com/repos/${REPO}/releases/${rel_id}/assets?name=${asset_name}" \
    | python3 -c 'import json,sys; j=json.load(sys.stdin); print("OK", j.get("name"), j.get("browser_download_url","")[:90])'

  ok "Release: ${WEB}/releases/tag/${tag}"
  ok "Auf anderen PCs:  tilix-update"
}

# =============================================================================
# Find release / local package
# =============================================================================
list_cytracon_tags() {
  git ls-remote --tags --refs "$GIT_URL" 'refs/tags/v*-cytracon.*' 2>/dev/null \
    | awk '{print $2}' | sed 's|refs/tags/||' | sort -V -r || true
}

asset_name_for() {
  local ver; ver="$(normalize_ver "$1")"
  echo "tilix-cytracon-${ver}-linux-x86_64.tar.gz"
}

probe_download() {
  local tag="$1" name url code
  name="$(asset_name_for "$tag")"
  url="${WEB}/releases/download/${tag}/${name}"
  code="$(curl -sI -o /dev/null -w '%{http_code}' -L --max-time 12 "$url" 2>/dev/null || echo 000)"
  [[ "$code" == "200" ]] && { echo "${name}|${url}"; return 0; }
  return 1
}

find_github_release() {
  local tag hit
  if [[ -n "$WANT_TAG" ]]; then
    tag="$WANT_TAG"; [[ "$tag" == v* ]] || tag="v$tag"
    hit="$(probe_download "$tag")" && { echo "${tag}|${hit}"; return 0; }
    return 1
  fi
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    hit="$(probe_download "$tag")" && { echo "${tag}|${hit}"; return 0; }
  done < <(list_cytracon_tags)
  return 1
}

find_local_package() {
  local -a roots=()
  local f best="" best_mtime=0 mt
  roots+=(
    "${HOME}/Downloads" "${HOME}/download" "/tmp"
    "${HOME}/Google Drive/BBachmann/Downloads"
    "${HOME}/Google Drive/Meine Ablage/BBachmann/Downloads"
    "${HOME}/src/tilix"
  )
  local s; s="$(self_path)"; [[ -n "$s" ]] && roots+=("$(dirname "$s")")
  [[ -n "${XDG_DOWNLOAD_DIR:-}" ]] && roots+=("$XDG_DOWNLOAD_DIR")
  for dir in "${roots[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' f; do
      mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      if (( mt >= best_mtime )); then best_mtime=$mt; best="$f"; fi
    done < <(find "$dir" -maxdepth 2 -type f -name 'tilix-cytracon-*-linux-x86_64.tar.gz' -print0 2>/dev/null)
  done
  [[ -n "$best" ]] || return 1
  echo "$best"
}

install_from_tarball() {
  local tarfile="$1" tmp stage
  [[ -f "$tarfile" ]] || die "Tarball fehlt: $tarfile"
  file "$tarfile" | grep -qiE 'gzip|tar' || die "Keine tar.gz: $(file -b "$tarfile")"
  tmp="$(mktemp -d /tmp/tilix-install.XXXXXX)"
  tar -xzf "$tarfile" -C "$tmp"
  stage="$(find "$tmp" -maxdepth 2 -type f -name 'install-remote.sh' -printf '%h\n' | head -1)"
  [[ -n "$stage" ]] || { rm -rf "$tmp"; die "Ungültiges Package."; }
  log "Installiere nach ${PREFIX}…"
  PREFIX="$PREFIX" bash "$stage/install-remote.sh"
  rm -rf "$tmp"
  # always put newest self as updater
  install_self "$(self_path)"
}

# =============================================================================
# Update / install (default)
# =============================================================================
cmd_update() {
  need curl; need tar; need file; need git
  ensure_path
  local CUR NEW FOUND LOCAL_PKG REL_TAG ASSET_NAME ASSET_URL
  CUR="$(normalize_ver "$(installed_version)")"
  log "Rechner:     $(hostname) · $(whoami)"
  log "Ziel:        $PREFIX"
  log "Installiert: ${CUR:-<noch keins>}"

  if [[ "$DO_TIMER" == 1 && "$CHECK_ONLY" == 0 && -z "${TILIX_TARBALL:-}" && "$FORCE" == 0 && -n "$CUR" ]]; then
    install_self "$(self_path)"
    install_timer
    return 0
  fi

  # explicit local
  if [[ -n "${TILIX_TARBALL:-}" ]]; then
    log "Lokales Package: $TILIX_TARBALL"
    [[ "$CHECK_ONLY" == 1 ]] && { log "würde installieren: $TILIX_TARBALL"; exit 1; }
    install_from_tarball "$TILIX_TARBALL"
    [[ "$DO_TIMER" == 1 ]] && install_timer
    ok "Fertig. Version: $(installed_version)"
    log "Tilix neu starten:  pkill -x tilix"
    return 0
  fi

  log "Suche GitHub Release…"
  if FOUND="$(find_github_release)"; then
    REL_TAG="${FOUND%%|*}"; rest="${FOUND#*|}"
    ASSET_NAME="${rest%%|*}"; ASSET_URL="${rest#*|}"
    NEW="$(normalize_ver "$REL_TAG")"
    log "Release: $REL_TAG ($ASSET_NAME)"

    if [[ "$CHECK_ONLY" == 1 ]]; then
      if [[ -n "$CUR" && "$CUR" == "$NEW" ]]; then ok "Aktuell ($CUR)."; exit 0; fi
      log "Update: ${CUR:-keins} → $NEW"; exit 1
    fi
    if [[ "$FORCE" != 1 && -n "$CUR" && "$CUR" == "$NEW" ]]; then
      ok "Bereits auf $CUR."
      install_self "$(self_path)"
      [[ "$DO_TIMER" == 1 ]] && install_timer
      return 0
    fi
    local tmp tarf
    tmp="$(mktemp -d /tmp/tilix-dl.XXXXXX)"
    tarf="$tmp/$ASSET_NAME"
    log "Download…"
    curl -fsSL -L --retry 3 -o "$tarf" "$ASSET_URL" || die "Download fehlgeschlagen"
    install_from_tarball "$tarf"
    rm -rf "$tmp"
    [[ "$DO_TIMER" == 1 ]] && install_timer
    ok "Fertig. Version: $(installed_version)"
    log "Tilix neu starten:  pkill -x tilix"
    return 0
  fi

  # local fallback
  log "Kein GitHub-Release — suche lokal (Downloads/Drive/tmp)…"
  if LOCAL_PKG="$(find_local_package)"; then
    log "Gefunden: $LOCAL_PKG"
    if [[ "$CHECK_ONLY" == 1 ]]; then log "Lokales Package: $LOCAL_PKG"; exit 1; fi
    if [[ "$FORCE" != 1 && -n "$CUR" ]]; then
      if [[ "$(basename "$LOCAL_PKG")" == *"$CUR"* ]]; then
        ok "Bereits auf $CUR."
        install_self "$(self_path)"
        [[ "$DO_TIMER" == 1 ]] && install_timer
        return 0
      fi
    fi
    install_from_tarball "$LOCAL_PKG"
    [[ "$DO_TIMER" == 1 ]] && install_timer
    ok "Fertig. Version: $(installed_version)"
    log "Tilix neu starten:  pkill -x tilix"
    return 0
  fi

  err "Nichts gefunden (weder GitHub-Release noch lokales tar.gz)."
  err ""
  err "Build-PC (einmal):"
  err "  tilix-cytracon package     # legt Package in Downloads/Drive"
  err "  GITHUB_TOKEN=… tilix-cytracon publish"
  err ""
  err "Oder Package manuell nach ~/Downloads legen und erneut:"
  err "  tilix-update"
  exit 2
}

# =============================================================================
# main
# =============================================================================
case "$CMD" in
  help) usage; exit 0 ;;
  package) cmd_package; exit 0 ;;
  publish) cmd_publish ;;
  update|install) cmd_update ;;
  *) die "Unbekannter Befehl: $CMD" ;;
esac
