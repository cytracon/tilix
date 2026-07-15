#!/usr/bin/env bash
# =============================================================================
# package-tilix.sh — build a portable Cytracon Tilix tarball for ~/.local install
#
# Usage:
#   ./scripts/package-tilix.sh                 # auto-find binary
#   TILIX_BIN=./tilix ./scripts/package-tilix.sh
#   PKG_DIR=/tmp ./scripts/package-tilix.sh
#
# Outputs:
#   $PKG_DIR/tilix-cytracon-<ver>-linux-x86_64.tar.gz
#   $PKG_DIR/tilix-cytracon-latest.pkgpath   (path to tarball)
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

PKG_DIR="${PKG_DIR:-/tmp}"
STAGE_NAME="tilix-cytracon-deploy"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[package] $*"; }

resolve_binary() {
  if [[ -n "${TILIX_BIN:-}" && -x "$TILIX_BIN" ]]; then
    echo "$TILIX_BIN"
    return
  fi
  for b in \
    "$REPO_ROOT/tilix" \
    "$HOME/.local/libexec/tilix" \
    "$HOME/.local/bin/tilix-cytracon"
  do
    if [[ -x "$b" ]] && file "$b" 2>/dev/null | grep -qi 'ELF'; then
      echo "$b"
      return
    fi
  done
  die "No Tilix binary. Build first or set TILIX_BIN=..."
}

BIN="$(resolve_binary)"
VERSION="$("$BIN" --version 2>/dev/null | sed -n 's/.*Tilix version:[[:space:]]*//p' | head -1 | tr -d '[:space:]')"
VERSION="${VERSION:-unknown}"
VER_FILE="$(echo "$VERSION" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_\+$//')"
TAR="${PKG_DIR}/tilix-cytracon-${VER_FILE}-linux-x86_64.tar.gz"
STAGE="${PKG_DIR}/${STAGE_NAME}"

log "Binary:  $BIN"
log "Version: $VERSION"
log "Package: $TAR"

rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,libexec,share/glib-2.0/schemas,share/applications,share/nemo/actions}

install -Dm 755 "$BIN" "$STAGE/libexec/tilix"

cat > "$STAGE/bin/tilix" << 'WRAP'
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
chmod 755 "$STAGE/bin/tilix"

if [[ -f "$REPO_ROOT/scripts/tilix-open-location" ]]; then
  install -Dm 755 "$REPO_ROOT/scripts/tilix-open-location" "$STAGE/bin/tilix-open-location"
fi
if [[ -f "$REPO_ROOT/scripts/tilix-update.sh" ]]; then
  install -Dm 755 "$REPO_ROOT/scripts/tilix-update.sh" "$STAGE/bin/tilix-update"
fi

SCHEMA_SRC=""
for s in \
  "$REPO_ROOT/data/gsettings/com.gexperts.Tilix.gschema.xml" \
  "$HOME/.local/share/glib-2.0/schemas/com.gexperts.Tilix.gschema.xml"
do
  if [[ -f "$s" ]]; then SCHEMA_SRC="$s"; break; fi
done
[[ -n "$SCHEMA_SRC" ]] || die "GSettings schema not found."
install -Dm 644 "$SCHEMA_SRC" "$STAGE/share/glib-2.0/schemas/"
glib-compile-schemas "$STAGE/share/glib-2.0/schemas/" 2>/dev/null || true

cat > "$STAGE/share/applications/com.gexperts.Tilix.desktop" << EOF
[Desktop Entry]
Version=1.1
Type=Application
Name=Tilix (Cytracon)
Name[de]=Tilix (Cytracon)
GenericName=Terminal
Comment=Cytracon Tilix ${VERSION}
Comment[de]=Cytracon Tilix ${VERSION}
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

install -Dm 755 "$REPO_ROOT/scripts/install-from-package.sh" "$STAGE/install-remote.sh"
install -Dm 755 "$REPO_ROOT/scripts/install-from-package.sh" "$STAGE/install-from-package.sh"

tar -C "$PKG_DIR" -czf "$TAR" "$STAGE_NAME"
echo "$TAR" > "${PKG_DIR}/tilix-cytracon-latest.pkgpath"
log "OK: $TAR ($(du -h "$TAR" | awk '{print $1}'))"
echo "$TAR"
