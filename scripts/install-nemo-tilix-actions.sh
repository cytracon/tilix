#!/usr/bin/env bash
# Install hardened Tilix context-menu actions for Nemo (not Nautilus).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin/tilix-open-location"
ACT="${XDG_DATA_HOME:-$HOME/.local/share}/nemo/actions"

install -Dm 755 "$ROOT/scripts/tilix-open-location" "$BIN"
mkdir -p "$ACT"

cat > "$ACT/open-tilix-here.nemo_action" << EOF
[Nemo Action]
Active=true
Name=Open Tilix Here
Name[de]=Tilix hier öffnen
Comment=Open Cytracon Tilix in this folder
Comment[de]=Cytracon Tilix in diesem Ordner öffnen
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
Comment=Open selected folder in Cytracon Tilix
Comment[de]=Ausgewählten Ordner in Cytracon Tilix öffnen
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
Comment=Open Tilix via SSH for sftp/ftp (hardened helper)
Comment[de]=Tilix per SSH für sftp/ftp (gehärteter Helper)
Exec=$BIN %U
Selection=s
Extensions=dir;
Icon-Name=com.gexperts.Tilix
EscapeSpaces=true
Quote=double
EOF

echo "Installed:"
echo "  $BIN"
echo "  $ACT/open-tilix-*.nemo_action"
echo "Restart Nemo: nemo -q && nemo &"
