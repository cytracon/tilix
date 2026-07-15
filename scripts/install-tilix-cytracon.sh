#!/usr/bin/env bash
# =============================================================================
# install-tilix-cytracon.sh
#
# EIN Script für ALLE Cytracon-PCs (Desktop, Laptop, Multimedia).
# Installiert / aktualisiert Cytracon-Tilix nach ~/.local — ohne Root, ohne LDC.
#
# Erstinstallation (ohne Clone):
#   curl -fsSL https://raw.githubusercontent.com/cytracon/tilix/master/scripts/install-tilix-cytracon.sh | bash
#
# Danach / lokal:
#   bash install-tilix-cytracon.sh
#   tilix-update                 # gleicher Befehl nach Install
#   tilix-update --check
#   tilix-update --force
#   tilix-update --timer         # täglicher Auto-Update (systemd --user)
#   tilix-update --tag v1.9.8-cytracon.9
#
# Env (optional):
#   TILIX_PREFIX=$HOME/.local
#   TILIX_REPO=cytracon/tilix
#   TILIX_TARBALL=/pfad/zu/paket.tar.gz   # offline / manuelles Package
#   GITHUB_TOKEN=…                        # nur gegen API-Rate-Limits
# =============================================================================
set -euo pipefail

REPO="${TILIX_REPO:-cytracon/tilix}"
PREFIX="${TILIX_PREFIX:-$HOME/.local}"
GIT_URL="${TILIX_GIT_URL:-https://github.com/${REPO}.git}"
WEB="https://github.com/${REPO}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/master"

CHECK_ONLY=0
FORCE=0
WANT_TAG=""
DO_TIMER=0
SELF_URL="${RAW_BASE}/scripts/install-tilix-cytracon.sh"

for arg in "${@:-}"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    --timer|--install-timer) DO_TIMER=1 ;;
    --tag=*) WANT_TAG="${arg#--tag=}" ;;
    --tag)   NEED_TAG=1 ;;
    -h|--help)
      sed -n '2,28p' "$0" 2>/dev/null | sed 's/^# \?//' || true
      exit 0
      ;;
    *)
      if [[ "${NEED_TAG:-0}" == 1 ]]; then
        WANT_TAG="$arg"
        NEED_TAG=0
      fi
      ;;
  esac
done

log()  { printf '\033[36m[tilix]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[tilix]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[tilix]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Befehl fehlt: $1 (bitte installieren)"
}

need_cmd curl
need_cmd tar
need_cmd file
need_cmd git
need_cmd install

normalize_ver() { echo "${1#v}"; }

installed_version() {
  local bin=""
  if [[ -x "$PREFIX/libexec/tilix" ]] && file "$PREFIX/libexec/tilix" 2>/dev/null | grep -qi ELF; then
    bin="$PREFIX/libexec/tilix"
  elif [[ -x "$PREFIX/bin/tilix" ]] && file "$PREFIX/bin/tilix" 2>/dev/null | grep -qi ELF; then
    bin="$PREFIX/bin/tilix"
  fi
  [[ -z "$bin" ]] && { echo ""; return; }
  "$bin" --version 2>/dev/null \
    | sed -n 's/.*Tilix version:[[:space:]]*//p' \
    | head -1 | tr -d '[:space:]' || true
}

install_self() {
  # Install this script as tilix-update + install-tilix-cytracon
  local src="${1:-}"
  mkdir -p "$PREFIX/bin"
  if [[ -z "$src" || ! -f "$src" || ! -r "$src" ]]; then
    # try BASH_SOURCE / $0
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
      src="${BASH_SOURCE[0]}"
    elif [[ -n "${0:-}" && -f "$0" && "$0" != "bash" && "$0" != "-bash" ]]; then
      src="$0"
    fi
  fi
  if [[ -n "$src" && -f "$src" && -r "$src" ]]; then
    local dest1="$PREFIX/bin/install-tilix-cytracon"
    local dest2="$PREFIX/bin/tilix-update"
    # Avoid "same file" when already running from dest
    if [[ "$(readlink -f "$src" 2>/dev/null || realpath "$src" 2>/dev/null || echo "$src")" != \
          "$(readlink -f "$dest1" 2>/dev/null || echo "$dest1")" ]]; then
      cp -f "$src" "$dest1"
    fi
    if [[ "$(readlink -f "$src" 2>/dev/null || realpath "$src" 2>/dev/null || echo "$src")" != \
          "$(readlink -f "$dest2" 2>/dev/null || echo "$dest2")" ]]; then
      cp -f "$src" "$dest2"
    fi
    # If only one dest was source, still ensure both exist and match
    if [[ ! -f "$dest1" ]]; then cp -f "$src" "$dest1"; fi
    if [[ ! -f "$dest2" ]]; then cp -f "$src" "$dest2"; fi
    if [[ -f "$dest1" && ! -f "$dest2" ]]; then cp -f "$dest1" "$dest2"; fi
    if [[ -f "$dest2" && ! -f "$dest1" ]]; then cp -f "$dest2" "$dest1"; fi
    chmod 755 "$dest1" "$dest2" 2>/dev/null || true
  else
    # running via curl|bash — re-fetch self from GitHub (needs push of this file)
    local tmp
    tmp="$(mktemp)"
    if curl -fsSL "$SELF_URL" -o "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      chmod 755 "$tmp"
      cp -f "$tmp" "$PREFIX/bin/install-tilix-cytracon"
      cp -f "$tmp" "$PREFIX/bin/tilix-update"
      chmod 755 "$PREFIX/bin/install-tilix-cytracon" "$PREFIX/bin/tilix-update"
    else
      err "Warnung: Updater konnte nicht nach $PREFIX/bin kopiert werden (Script-Quelle unklar)."
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
  fi
  ok "Updater: $PREFIX/bin/tilix-update"
}

install_timer() {
  local unit_dir="${HOME}/.config/systemd/user"
  local exe="$PREFIX/bin/tilix-update"
  [[ -x "$exe" ]] || die "tilix-update fehlt — erst Installation laufen lassen."
  mkdir -p "$unit_dir"

  cat > "$unit_dir/tilix-update.service" << EOF
[Unit]
Description=Cytracon Tilix aktualisieren (GitHub Release)
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
    ok "Timer aktiv (täglich). Status:"
    systemctl --user status tilix-update.timer --no-pager 2>/dev/null | head -10 || true
  else
    err "systemctl nicht verfügbar — Timer-Dateien liegen in $unit_dir"
  fi
}

# Ensure ~/.local/bin early on PATH for this shell + profile hint
ensure_path() {
  case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) export PATH="$PREFIX/bin:$PATH" ;;
  esac
  if [[ -f "$HOME/.profile" ]] && ! grep -q '\.local/bin' "$HOME/.profile" 2>/dev/null; then
    {
      echo ''
      echo '# Cytracon user binaries (Tilix)'
      echo 'if [ -d "$HOME/.local/bin" ] ; then PATH="$HOME/.local/bin:$PATH"; fi'
    } >> "$HOME/.profile"
    log "PATH-Hinweis in ~/.profile ergänzt (nächster Login)."
  fi
}

list_cytracon_tags() {
  git ls-remote --tags --refs "$GIT_URL" 'refs/tags/v*-cytracon.*' 2>/dev/null \
    | awk '{print $2}' | sed 's|refs/tags/||' | sort -V -r
}

asset_name_for() {
  local ver
  ver="$(normalize_ver "$1")"
  echo "tilix-cytracon-${ver}-linux-x86_64.tar.gz"
}

probe_download() {
  # args: tag → prints "name|url" if HTTP 200
  local tag="$1" name url code
  name="$(asset_name_for "$tag")"
  url="${WEB}/releases/download/${tag}/${name}"
  code="$(curl -sI -o /dev/null -w '%{http_code}' -L --max-time 15 "$url" 2>/dev/null || echo 000)"
  if [[ "$code" == "200" ]]; then
    echo "${name}|${url}"
    return 0
  fi
  return 1
}

find_release() {
  local tag hit
  if [[ -n "$WANT_TAG" ]]; then
    tag="$WANT_TAG"
    [[ "$tag" == v* ]] || tag="v${tag}"
    if hit="$(probe_download "$tag")"; then
      echo "${tag}|${hit}"
      return 0
    fi
    return 1
  fi
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if hit="$(probe_download "$tag")"; then
      echo "${tag}|${hit}"
      return 0
    fi
  done < <(list_cytracon_tags)
  return 1
}

install_from_tarball() {
  local tarfile="$1"
  local tmp stage installer
  [[ -f "$tarfile" ]] || die "Tarball fehlt: $tarfile"
  file "$tarfile" | grep -qiE 'gzip|tar' || die "Keine tar.gz: $(file -b "$tarfile")"

  tmp="$(mktemp -d /tmp/tilix-install.XXXXXX)"
  tar -xzf "$tarfile" -C "$tmp"
  stage="$(find "$tmp" -maxdepth 2 -type f \( -name install-from-package.sh -o -name install-remote.sh \) -printf '%h\n' | head -1)"
  if [[ -z "$stage" ]]; then
    rm -rf "$tmp"
    die "Ungültiges Package (kein install-*.sh)."
  fi

  if [[ -x "$stage/install-from-package.sh" ]]; then
    installer="$stage/install-from-package.sh"
  else
    installer="$stage/install-remote.sh"
  fi

  log "Installiere nach ${PREFIX}…"
  PREFIX="$PREFIX" bash "$installer"
  rm -rf "$tmp"
}

# Newest local package in common places (Drive sync / Downloads /tmp)
find_local_package() {
  local -a roots=()
  local f best="" best_mtime=0 mt
  roots+=(
    "${HOME}/Downloads"
    "${HOME}/download"
    "${HOME}/Google Drive/BBachmann/Downloads"
    "${HOME}/Google Drive/Meine Ablage/BBachmann/Downloads"
    "/tmp"
    "${HOME}/src/tilix"
  )
  # script directory
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    roots+=("$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)")
  fi
  # XDG
  [[ -n "${XDG_DOWNLOAD_DIR:-}" ]] && roots+=("$XDG_DOWNLOAD_DIR")

  for dir in "${roots[@]}"; do
    [[ -d "$dir" ]] || continue
    # shellcheck disable=SC2044
    while IFS= read -r -d '' f; do
      mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      if (( mt >= best_mtime )); then
        best_mtime=$mt
        best="$f"
      fi
    done < <(find "$dir" -maxdepth 2 -type f -name 'tilix-cytracon-*-linux-x86_64.tar.gz' -print0 2>/dev/null)
  done
  [[ -n "$best" ]] || return 1
  echo "$best"
}

finish_local() {
  if [[ -f "${BASH_SOURCE[0]:-}" ]]; then install_self "${BASH_SOURCE[0]}"; else install_self ""; fi
  ok "Fertig. Version: $(installed_version)"
  [[ "$DO_TIMER" == 1 ]] && install_timer
  log "Tilix komplett beenden und neu starten:  pkill -x tilix"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
ensure_path
CUR="$(normalize_ver "$(installed_version)")"
log "Rechner:   $(hostname) · $(whoami)"
log "Ziel:      $PREFIX"
log "Installiert: ${CUR:-<noch keins>}"

# Only timer?
if [[ "$DO_TIMER" == 1 && "$CHECK_ONLY" == 0 && -z "${TILIX_TARBALL:-}" && "$FORCE" == 0 ]]; then
  # If binary missing, install first then timer
  if [[ -z "$CUR" ]]; then
    log "Noch kein Tilix — installiere zuerst, dann Timer."
  else
    # ensure self is installed
    if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
      install_self "${BASH_SOURCE[0]}"
    else
      install_self ""
    fi
    install_timer
    exit 0
  fi
fi

# Offline / explicit tarball
if [[ -n "${TILIX_TARBALL:-}" ]]; then
  log "Nutze lokales Package: $TILIX_TARBALL"
  install_from_tarball "$TILIX_TARBALL"
  finish_local
  exit 0
fi

log "Suche GitHub Release auf ${WEB} …"
FOUND=""
if ! FOUND="$(find_release)"; then
  log "Kein GitHub-Release — suche lokales Package (Downloads / Drive /tmp)…"
  LOCAL_PKG=""
  if LOCAL_PKG="$(find_local_package)"; then
    log "Gefunden: $LOCAL_PKG"
    if [[ "$CHECK_ONLY" == 1 ]]; then
      log "Lokales Package vorhanden (GitHub-Release fehlt noch)."
      exit 1
    fi
    # If already on cytracon.9 and package is same version-ish, skip unless --force
    if [[ "$FORCE" != 1 && -n "$CUR" ]]; then
      base="$(basename "$LOCAL_PKG")"
      if [[ "$base" == *"${CUR}"* ]]; then
        ok "Bereits auf $CUR (lokales Package $base). --force erzwingt Neuinstallation."
        finish_local
        exit 0
      fi
    fi
    install_from_tarball "$LOCAL_PKG"
    finish_local
    exit 0
  fi
  err "Kein Release-Package und kein lokales Tarball gefunden."
  err ""
  err "Option A — Package aus Drive nutzen:"
  err "  # Dateien nach ~/Downloads legen:"
  err "  #   install-tilix-cytracon.sh"
  err "  #   tilix-cytracon-*-linux-x86_64.tar.gz"
  err "  bash ~/Downloads/install-tilix-cytracon.sh"
  err ""
  err "Option B — GitHub Release (Build-PC, einmalig):"
  err "  cd ~/src/tilix && git push origin master --tags"
  err "  GITHUB_TOKEN=… ./scripts/publish-github-release.sh"
  err ""
  err "Releases: ${WEB}/releases"
  exit 2
fi

REL_TAG="${FOUND%%|*}"
rest="${FOUND#*|}"
ASSET_NAME="${rest%%|*}"
ASSET_URL="${rest#*|}"
NEW="$(normalize_ver "$REL_TAG")"

log "Release:   $REL_TAG"
log "Package:   $ASSET_NAME"

if [[ "$CHECK_ONLY" == 1 ]]; then
  if [[ -n "$CUR" && "$CUR" == "$NEW" ]]; then
    ok "Bereits aktuell ($CUR)."
    exit 0
  fi
  log "Update verfügbar: ${CUR:-keins} → $NEW"
  exit 1
fi

if [[ "$FORCE" != 1 && -n "$CUR" && "$CUR" == "$NEW" ]]; then
  ok "Bereits auf $CUR — nichts zu tun (--force erzwingt Neuinstallation)."
  if [[ -f "${BASH_SOURCE[0]:-}" ]]; then install_self "${BASH_SOURCE[0]}"; else install_self ""; fi
  [[ "$DO_TIMER" == 1 ]] && install_timer
  exit 0
fi

TMP="$(mktemp -d /tmp/tilix-dl.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
TAR="$TMP/$ASSET_NAME"

log "Download…"
curl -fsSL -L --retry 3 -o "$TAR" "$ASSET_URL" || die "Download fehlgeschlagen: $ASSET_URL"

install_from_tarball "$TAR"

# Prefer the script we just ran (newest logic) over possibly older copy in package
if [[ -f "${BASH_SOURCE[0]:-}" && -r "${BASH_SOURCE[0]}" ]]; then
  install_self "${BASH_SOURCE[0]}"
else
  install_self ""
fi

# If package shipped updater but older, keep ours — already done

NOW="$(normalize_ver "$(installed_version)")"
ok "Installiert: ${NOW:-?}"
if [[ -n "$NOW" && "$NOW" != "$NEW" ]]; then
  err "Versions-Mismatch (erwartet $NEW, ist $NOW)."
  exit 2
fi

[[ "$DO_TIMER" == 1 ]] && install_timer

echo
ok "Fertig."
log "Tilix neu starten:"
log "  pkill -x tilix"
log "  tilix &"
log "Später updaten:  tilix-update"
log "Auto-Update:     tilix-update --timer"
