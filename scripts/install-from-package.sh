#!/usr/bin/env bash
# Install a staged Cytracon Tilix package into ~/.local (no root).
# Expected layout (this script lives in package root):
#   libexec/tilix
#   bin/tilix
#   share/glib-2.0/schemas/...
#   share/applications/com.gexperts.Tilix.desktop
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"

echo ">>> Installing Cytracon Tilix on $(hostname) as $(whoami)"
echo ">>> Target: $PREFIX"

mkdir -p "$PREFIX"/{bin,libexec,share/glib-2.0/schemas,share/applications,share/nemo/actions}

install -Dm 755 "$HERE/libexec/tilix" "$PREFIX/libexec/tilix"
install -Dm 755 "$HERE/bin/tilix" "$PREFIX/bin/tilix"
if [[ -f "$HERE/bin/tilix-open-location" ]]; then
  install -Dm 755 "$HERE/bin/tilix-open-location" "$PREFIX/bin/tilix-open-location"
fi
if [[ -f "$HERE/bin/tilix-update" ]]; then
  install -Dm 755 "$HERE/bin/tilix-update" "$PREFIX/bin/tilix-update"
elif [[ -f "$HERE/bin/tilix-update.sh" ]]; then
  install -Dm 755 "$HERE/bin/tilix-update.sh" "$PREFIX/bin/tilix-update"
fi

install -Dm 644 "$HERE/share/glib-2.0/schemas/com.gexperts.Tilix.gschema.xml" \
  "$PREFIX/share/glib-2.0/schemas/"
if [[ -f "$HERE/share/glib-2.0/schemas/gschemas.compiled" ]]; then
  install -Dm 644 "$HERE/share/glib-2.0/schemas/gschemas.compiled" \
    "$PREFIX/share/glib-2.0/schemas/" || true
fi
glib-compile-schemas "$PREFIX/share/glib-2.0/schemas/" 2>/dev/null || true

if [[ -f "$HERE/share/applications/com.gexperts.Tilix.desktop" ]]; then
  sed "s|__HOME__|${HOME}|g" \
    "$HERE/share/applications/com.gexperts.Tilix.desktop" \
    > "$PREFIX/share/applications/com.gexperts.Tilix.desktop"
  update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
fi

# Nemo actions
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
command -v tilix || true
"$PREFIX/libexec/tilix" --version 2>&1 | head -8
echo ">>> Done on $(hostname)"
