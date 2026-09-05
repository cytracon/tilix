# Tilix (Cytracon Fork)

[![Upstream](https://img.shields.io/badge/upstream-gnunn1%2Ftilix-blue)](https://github.com/gnunn1/tilix)
[![License](https://img.shields.io/badge/license-MPL--2.0-green)](LICENSE)

**Repository:** https://github.com/cytracon/tilix  
**Upstream:** https://github.com/gnunn1/tilix (minimal maintenance; [maintainers wanted](https://github.com/gnunn1/tilix/issues/1700))  
**Current version:** **1.9.8-cytracon.11**  
**Install script:** [`scripts/tilix-cytracon.sh`](scripts/tilix-cytracon.sh) (install · update · package · publish · desktop)  
**Primary desktop:** [Omarchy](docs/OMARCHY.md) (Arch + Hyprland). Ubuntu/GNOME still works.

Tiling terminal emulator for Linux (GTK 3 + VTE), forked for **Cytracon ops / Magento / AI workflows**. Upstream Tilix features remain; this fork adds security fixes, header-bar productivity tools, Omarchy/Hyprland integration, and file-manager integration for **Nautilus** and **Nemo**.

Original project site: [tilix-web](https://gnunn1.github.io/tilix-web).

> **Release rule:** Bei jeder neuen Version immer mit anpassen:  
> `source/gx/tilix/constants.d` · `docs/CYTRACON-CHANGELOG.md` · **`README.md` (diese Datei)** · Tag `v1.9.8-cytracon.N` · `./scripts/build-omarchy.sh` · `tilix-cytracon package` / `publish`.  
> Never commit hostnames, IPs, SSH keys, or shop paths — those belong in Preferences / local env only.

See **[docs/OMARCHY.md](docs/OMARCHY.md)** for the Hyprland/xdg-terminal-exec port. Install with:

```bash
curl -fsSL https://raw.githubusercontent.com/cytracon/tilix/master/scripts/tilix-cytracon.sh | bash
```
