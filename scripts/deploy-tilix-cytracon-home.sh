#!/usr/bin/env bash
# =============================================================================
# deploy-tilix-cytracon-home.sh
#
# Baut das Cytracon-Tilix-Paket vom Desktop und installiert es auf:
#   - bbachmann-laptop   (default 192.168.178.162)
#   - multimedia-laptop  (default 192.168.178.164)
#
# Usage:
#   ./scripts/deploy-tilix-cytracon-home.sh              # package + deploy both
#   ./scripts/deploy-tilix-cytracon-home.sh --package-only
#   ./scripts/deploy-tilix-cytracon-home.sh --deploy-only
#   ./scripts/deploy-tilix-cytracon-home.sh laptop        # only laptop
#   ./scripts/deploy-tilix-cytracon-home.sh multimedia    # only multimedia
#
# Env overrides:
#   LAPTOP_HOST / LAPTOP_IP
#   MULTIMEDIA_HOST / MULTIMEDIA_IP
#   REMOTE_USER   (default: bbachmann)
#   SSH_KEY       (default: ~/.ssh/id_ed25519, fallback id_cytracon2)
#   TILIX_BIN     (default: ~/.local/libexec/tilix or repo ./tilix)
#   PKG_DIR       (default: /tmp)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer real repo layout; if this script lives outside the repo (e.g. Google Drive),
# fall back to ~/src/tilix or TILIX_REPO.
if [[ -d "${SCRIPT_DIR}/../source/gx/tilix" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -n "${TILIX_REPO:-}" && -d "${TILIX_REPO}" ]]; then
  REPO_ROOT="$(cd "${TILIX_REPO}" && pwd)"
elif [[ -d "${HOME}/src/tilix/source/gx/tilix" ]]; then
  REPO_ROOT="$(cd "${HOME}/src/tilix" && pwd)"
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

REMOTE_USER="${REMOTE_USER:-bbachmann}"
LAPTOP_HOST="${LAPTOP_HOST:-bbachmann-laptop}"
LAPTOP_IP="${LAPTOP_IP:-192.168.178.162}"
MULTIMEDIA_HOST="${MULTIMEDIA_HOST:-multimedia-laptop}"
MULTIMEDIA_IP="${MULTIMEDIA_IP:-192.168.178.164}"
PKG_DIR="${PKG_DIR:-/tmp}"
STAGE_NAME="tilix-cytracon-deploy"

# --- colours (if tty) ---
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'; C_RST=$'\033[0m'
else
  C_OK=; C_ERR=; C_INFO=; C_RST=
fi

log()  { printf '%s[*]%s %s\n' "$C_INFO" "$C_RST" "$*"; }
ok()   { printf '%s[OK]%s %s\n' "$C_OK" "$C_RST" "$*"; }
err()  { printf '%s[ERR]%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

resolve_key() {
  if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
    echo "$SSH_KEY"
    return
  fi
  for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_cytracon2" "$HOME/.ssh/id_cytracon"; do
    if [[ -f "$k" ]]; then
      echo "$k"
      return
    fi
  done
  die "Kein SSH-Key gefunden (id_ed25519 / id_cytracon2)."
}

resolve_binary() {
  if [[ -n "${TILIX_BIN:-}" && -x "$TILIX_BIN" ]]; then
    echo "$TILIX_BIN"
    return
  fi
  for b in "$HOME/.local/libexec/tilix" "$REPO_ROOT/tilix" "$HOME/.local/bin/tilix-cytracon"; do
    if [[ -x "$b" ]] && file "$b" 2>/dev/null | grep -qi 'ELF'; then
      echo "$b"
      return
    fi
  done
  # wrapper is a shell script — reject
  if [[ -x "$HOME/.local/bin/tilix" ]] && head -1 "$HOME/.local/bin/tilix" | grep -q bash; then
    if [[ -x "$HOME/.local/libexec/tilix" ]]; then
      echo "$HOME/.local/libexec/tilix"
      return
    fi
  fi
  die "Kein Tilix-Binary gefunden. Baue zuerst: cd $REPO_ROOT && dub build --compiler=ldc2 --build=release"
}

ssh_opts() {
  local key="$1"
  echo -o BatchMode=yes \
       -o ConnectTimeout=8 \
       -o ConnectionAttempts=1 \
       -o IdentitiesOnly=yes \
       -o StrictHostKeyChecking=accept-new \
       -i "$key"
}

host_online() {
  local ip="$1"
  ping -c 1 -W 2 "$ip" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
build_package() {
  local bin version stage tar
  bin="$(resolve_binary)"
  version="$("$bin" --version 2>/dev/null | sed -n 's/.*Tilix version:[[:space:]]*//p' | head -1 | tr -d '[:space:]')"
  version="${version:-unknown}"
  # sanitize for filename (no trailing underscores)
  local ver_file
  ver_file="$(echo "$version" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_\+$//')"
  tar="${PKG_DIR}/tilix-cytracon-${ver_file}-linux-x86_64.tar.gz"
  stage="${PKG_DIR}/${STAGE_NAME}"

  log "Binary:  $bin"
  log "Version: $version"
  log "Package: $tar"

  rm -rf "$stage"
  mkdir -p "$stage"/{bin,libexec,share/glib-2.0/schemas,share/applications,share/nemo/actions}

  install -Dm 755 "$bin" "$stage/libexec/tilix"

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

  if [[ -f "$REPO_ROOT/scripts/tilix-open-location" ]]; then
    install -Dm 755 "$REPO_ROOT/scripts/tilix-open-location" "$stage/bin/tilix-open-location"
  fi

  local schema_src=""
  for s in \
    "$REPO_ROOT/data/gsettings/com.gexperts.Tilix.gschema.xml" \
    "$HOME/.local/share/glib-2.0/schemas/com.gexperts.Tilix.gschema.xml"; do
    if [[ -f "$s" ]]; then schema_src="$s"; break; fi
  done
  [[ -n "$schema_src" ]] || die "GSettings schema nicht gefunden."
  install -Dm 644 "$schema_src" "$stage/share/glib-2.0/schemas/"
  glib-compile-schemas "$stage/share/glib-2.0/schemas/" 2>/dev/null || true

  # Desktop entry (HOME replaced on target)
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

  # Remote installer (runs ON the laptop)
  cat > "$stage/install-remote.sh" << 'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${HOME}/.local"
echo ">>> Installing Cytracon Tilix on $(hostname) as $(whoami)"
echo ">>> Target: $PREFIX"

mkdir -p "$PREFIX"/{bin,libexec,share/glib-2.0/schemas,share/applications,share/nemo/actions}

install -Dm 755 "$HERE/libexec/tilix" "$PREFIX/libexec/tilix"
install -Dm 755 "$HERE/bin/tilix" "$PREFIX/bin/tilix"
if [[ -f "$HERE/bin/tilix-open-location" ]]; then
  install -Dm 755 "$HERE/bin/tilix-open-location" "$PREFIX/bin/tilix-open-location"
fi

install -Dm 644 "$HERE/share/glib-2.0/schemas/com.gexperts.Tilix.gschema.xml" \
  "$PREFIX/share/glib-2.0/schemas/"
if [[ -f "$HERE/share/glib-2.0/schemas/gschemas.compiled" ]]; then
  install -Dm 644 "$HERE/share/glib-2.0/schemas/gschemas.compiled" \
    "$PREFIX/share/glib-2.0/schemas/" || true
fi
glib-compile-schemas "$PREFIX/share/glib-2.0/schemas/" 2>/dev/null || true

sed "s|__HOME__|${HOME}|g" \
  "$HERE/share/applications/com.gexperts.Tilix.desktop" \
  > "$PREFIX/share/applications/com.gexperts.Tilix.desktop"
update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true

# Nemo actions (primary FM on Cytracon desktops)
if [[ -x "$PREFIX/bin/tilix-open-location" ]]; then
  BIN="$PREFIX/bin/tilix-open-location"
  ACT="$PREFIX/share/nemo/actions"
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

# Ensure ~/.local/bin is on PATH for login shells
if [[ -f "$HOME/.profile" ]] && ! grep -q '\.local/bin' "$HOME/.profile" 2>/dev/null; then
  {
    echo ''
    echo '# Cytracon Tilix / user binaries'
    echo 'if [ -d "$HOME/.local/bin" ] ; then PATH="$HOME/.local/bin:$PATH"; fi'
  } >> "$HOME/.profile"
fi

echo ">>> Verify"
export PATH="$PREFIX/bin:$PATH"
export GSETTINGS_SCHEMA_DIR="$PREFIX/share/glib-2.0/schemas"
command -v tilix
tilix --version 2>&1 | head -8
echo ">>> Done on $(hostname)"
REMOTE
  chmod 755 "$stage/install-remote.sh"

  tar -C "$PKG_DIR" -czf "$tar" "$STAGE_NAME"
  ok "Package built: $tar ($(du -h "$tar" | awk '{print $1}'))"
  # remember for deploy
  PACKAGE_TAR="$tar"
  export PACKAGE_TAR
  echo "$tar" > "${PKG_DIR}/tilix-cytracon-latest.pkgpath"
}

# ---------------------------------------------------------------------------
# Deploy one host
# ---------------------------------------------------------------------------
deploy_host() {
  local name="$1" ip="$2"
  local key tar base
  key="$(resolve_key)"
  tar="${PACKAGE_TAR:-}"
  if [[ -z "$tar" || ! -f "$tar" ]]; then
    if [[ -f "${PKG_DIR}/tilix-cytracon-latest.pkgpath" ]]; then
      tar="$(cat "${PKG_DIR}/tilix-cytracon-latest.pkgpath")"
    fi
  fi
  [[ -n "${tar:-}" && -f "$tar" ]] || die "Kein Package. Zuerst --package-only oder ohne Flags laufen lassen."
  base="$(basename "$tar")"

  log "Deploy → $name ($ip) as ${REMOTE_USER}"
  if ! host_online "$ip"; then
    err "$name offline (ping $ip failed)"
    return 2
  fi

  # shellcheck disable=SC2046
  if ! ssh $(ssh_opts "$key") "${REMOTE_USER}@${ip}" "echo connected-\$(hostname)" >/dev/null 2>&1; then
    err "$name: SSH fehlgeschlagen (Key? User? sshd?)"
    return 3
  fi

  # shellcheck disable=SC2046
  scp $(ssh_opts "$key") "$tar" "${REMOTE_USER}@${ip}:/tmp/${base}"

  # shellcheck disable=SC2046
  ssh $(ssh_opts "$key") "${REMOTE_USER}@${ip}" bash -s << REMOTE
set -euo pipefail
cd /tmp
rm -rf ${STAGE_NAME}
tar -xzf ${base}
cd ${STAGE_NAME}
./install-remote.sh
REMOTE

  ok "$name installiert"
  return 0
}

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local mode="all"  # all | package | deploy
  local only=""     # "" | laptop | multimedia

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --package-only) mode="package"; shift ;;
      --deploy-only)  mode="deploy"; shift ;;
      laptop|bbachmann-laptop) only="laptop"; shift ;;
      multimedia|multimedia-laptop) only="multimedia"; shift ;;
      *)
        err "Unbekanntes Argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  PACKAGE_TAR=""
  if [[ "$mode" == "all" || "$mode" == "package" ]]; then
    build_package
  fi
  if [[ "$mode" == "package" ]]; then
    ok "Nur Package erstellt. Deploy mit: $0 --deploy-only"
    exit 0
  fi

  # deploy-only: find latest package
  if [[ -z "${PACKAGE_TAR:-}" ]]; then
    if [[ -f "${PKG_DIR}/tilix-cytracon-latest.pkgpath" ]]; then
      PACKAGE_TAR="$(cat "${PKG_DIR}/tilix-cytracon-latest.pkgpath")"
    else
      PACKAGE_TAR="$(ls -1t "${PKG_DIR}"/tilix-cytracon-*-linux-x86_64.tar.gz 2>/dev/null | head -1 || true)"
    fi
  fi
  [[ -n "${PACKAGE_TAR:-}" && -f "$PACKAGE_TAR" ]] || die "Kein Package gefunden. Zuerst ohne --deploy-only ausführen."

  local fail=0
  if [[ -z "$only" || "$only" == "laptop" ]]; then
    deploy_host "$LAPTOP_HOST" "$LAPTOP_IP" || fail=$((fail + 1))
  fi
  if [[ -z "$only" || "$only" == "multimedia" ]]; then
    deploy_host "$MULTIMEDIA_HOST" "$MULTIMEDIA_IP" || fail=$((fail + 1))
  fi

  if [[ "$fail" -gt 0 ]]; then
    err "Fertig mit $fail Fehler(n). Hosts online? IPs korrekt?"
    err "Laptop:    $LAPTOP_HOST → $LAPTOP_IP"
    err "Multimedia: $MULTIMEDIA_HOST → $MULTIMEDIA_IP"
    exit 1
  fi
  ok "Alle Zielsysteme aktualisiert."
}

main "$@"
