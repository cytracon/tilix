# Cytracon Tilix on Omarchy

Primary desktop for this fork as of **1.9.8-cytracon.11**. Ubuntu/GNOME remains supported.

Omarchy is Arch Linux + Hyprland. The Ubuntu-era package had several mismatches here:

| Ubuntu assumption | Omarchy reality | Fix |
|---|---|---|
| GNOME Dock pin / `favorite-apps` | Hyprland + xdg-terminal-exec | Desktop file with `X-TerminalArg*` |
| Floating “terminal” dialog | Foot/kitty/ghostty **tile** | Drop `+floating-window` |
| X11 / XWayland | Wayland session | `GDK_BACKEND=wayland` in wrapper |
| Nemo-only “open here” | Default FM is Nautilus | Install `open-tilix.py` |
| Binary-only tarball | Missing gresource/icons/schemes | Full `~/.local/share/tilix` payload |
| Hyprbars + GTK CSD | Double title bar | Keep GTK header bar (Bookmarks/AI/Ops); do not tag Tilix as a dialog |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/cytracon/tilix/master/scripts/tilix-cytracon.sh | bash
# or from a clone:
bash scripts/tilix-cytracon.sh
```

Installs into `~/.local` (no sudo). Then:

- Super+Return uses Tilix (`~/.config/xdg-terminals.list`)
- `~/.config/hypr/tilix.lua` is required from `hyprland.lua`
- Theme changes run `theme-set-tilix`

## Build on Omarchy

No root. LDC can live in `~/.local/opt/ldc2` (official tarball) or as `extra/ldc`.

```bash
./scripts/build-omarchy.sh
tilix-cytracon package
tilix-cytracon desktop
```

## Files the installer writes

| Path | Role |
|------|------|
| `~/.local/libexec/tilix` | Binary |
| `~/.local/bin/tilix` | Wayland + xdg-terminal-exec wrapper |
| `~/.local/share/applications/com.gexperts.Tilix.desktop` | Launcher + terminal-exec keys |
| `~/.local/share/tilix/resources/tilix.gresource` | CSS / symbolic icons |
| `~/.config/hypr/tilix.lua` | Window rules |
| `~/.config/xdg-terminals.list` | Default terminal |
| `~/.config/omarchy/hooks/theme-set.d/theme-set-tilix` | Theme colors |

Do **not** tag Tilix as `floating-window`. That Omarchy tag is for 875×600 dialogs.
