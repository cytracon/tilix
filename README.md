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

---

## Cytracon features

### Header bar (navigation)

| Control | What it does | Shortcut |
|---------|----------------|----------|
| **Bookmarks** | Searchable popover, **accordion by theme** | `Ctrl+Shift+B` |
| **AI** | Tools + **Grok / Codex** recent sessions (accordion) | `Ctrl+Shift+A` |
| **Ops** | Shops, server/cache/status, ops layout, session log | `Ctrl+Shift+Q` |

### Preferences (fully configurable)

- **Preferences → AI Tools** — define CLIs (`name\|start\|resume {id}\|list`)
- **Preferences → Cytracon**
  - Command launch mode: *current terminal* / *split right* / *split down* / *new session*
  - Confirm destructive bookmark/quick commands
  - Show/hide header buttons
  - Unified recent AI count
  - Session log directory (default `~/.claude/session-logs`)
  - Ops session JSON path
  - **Shops** list (`name\|command`)
  - **Quick actions** (`name\|command\|section`)

Shops and quick actions are **empty by default** — configure in Preferences (no host/SSH infrastructure is baked into the app).

### Security & reliability

| Item | Notes |
|------|--------|
| OSC 7 crash fix | Invalid directory URIs no longer segfault the process |
| Safer paste heuristics | Beyond `sudo`+newline |
| Trigger / custom-link shell confirm | Default **on** |
| Password insert | Never synced to other panes; optional remote warning |
| AI resume by `kind` | Grok sessions never open under Codex |
| Bookmark / menu buttons | Correct per-row command (D loop-capture fix) |
| Omarchy / Hyprland | Wayland wrapper, xdg-terminal-exec, tiled window rules, theme-set hook |
| Bookmarks install safety | Pack scripts **never** overwrite `bookmarks.json` (symlink-safe) |

### File manager integration

| Manager | Status |
|---------|--------|
| **Nautilus** (Omarchy default) | Hardened Python extension `data/nautilus/open-tilix.py` |
| **Nemo** | Hardened **`.nemo_action`** entries + `tilix-open-location` helper |

Nemo does **not** load Nautilus Python extensions. Use the Nemo installer below.

### Other

- Copy scrollback to clipboard: `Ctrl+Shift+O`
- Copy scrollback to session-log directory (Ops menu)
- Example packs: `data/cytracon/` (bookmarks example, ops session layout)
- Docs: [Omarchy](docs/OMARCHY.md) · [Audit](docs/CYTRACON-AUDIT-2026-07-14.md) · [Changelog](docs/CYTRACON-CHANGELOG.md) · [Auto-Update](docs/AUTO-UPDATE.md)

---

## Install & auto-update (all machines)

| | |
|--|--|
| Repo | **public** — https://github.com/cytracon/tilix |
| Root / sudo | **nie** — installiert nach `~/.local` |
| Compiler auf Laptops | nicht nötig (vorgefertigtes `linux-x86_64` Package) |
| Token | nicht nötig für Install/Update (public) |

### One script: `scripts/tilix-cytracon.sh`

Nach Install auch als: `tilix-update` · `tilix-cytracon` · `install-tilix-cytracon` (`~/.local/bin`).

```bash
# --- Jeder PC: install / update ---
# Bevorzugt: bash (nicht ./ und NIE sudo)
bash tilix-cytracon.sh

# danach:
tilix-update
tilix-update --check
tilix-update --force
tilix-update --timer          # optional: täglich (systemd --user)
tilix-cytracon desktop        # Desktop / Hyprland / xdg-terminal-exec (ohne Kill)
# tilix-cytracon desktop --kill  # optional: laufende Tilix-Fenster beenden
```

#### Ohne lokale Datei

```bash
curl -fsSL https://raw.githubusercontent.com/cytracon/tilix/master/scripts/tilix-cytracon.sh | bash
```

#### Build-PC (Omarchy)

```bash
cd ~/src/tilix
./scripts/build-omarchy.sh
tilix-cytracon package
GITHUB_TOKEN=ghp_… tilix-cytracon publish
```

### Was das Install-Script macht

| Schritt | Ziel |
|---------|------|
| Binary | `~/.local/libexec/tilix` |
| Wrapper | `~/.local/bin/tilix` (Wayland + xdg-terminal-exec) |
| Updater | `~/.local/bin/tilix-update` |
| **Desktop** | `X-TerminalArg*` for Omarchy Super+Return |
| Schemas / icons / gresource | `~/.local/share/` |
| Kill offener Fenster | **nein** (nur `desktop --kill` explizit) |

`~/.local/bin` muss vor `/usr/bin` in `PATH` stehen.

---

## Building

```bash
./scripts/build-omarchy.sh
tilix-cytracon package
tilix-cytracon desktop
```

Dependencies: **gtkd** / **vte** ≥ 3.11.0. Runtime: GTK 3.18+, VTE 0.46+, dconf.

---

## Scripts reference

| Script | Purpose |
|--------|---------|
| **`scripts/tilix-cytracon.sh`** | install · update · package · publish · desktop |
| `scripts/build-omarchy.sh` | Native LDC release build |
| `scripts/tilix-update.sh` | Alias of `tilix-cytracon.sh` |
| `scripts/install-tilix-cytracon.sh` | Alias of `tilix-cytracon.sh` |
| `scripts/tilix-open-location` | Hardened open path/URI for file managers |
| `scripts/install-nemo-tilix-actions.sh` | Nemo context-menu actions |
| `scripts/install-cytracon-packs.sh` | Example sessions |
| `install.sh` | Full resource install |

---

## Tags

| Tag | Highlights |
|-----|------------|
| `v1.9.8-cytracon.11` | Omarchy/Hyprland primary: Wayland wrapper, xdg-terminal-exec, tiled rules, theme hook, full resources |
| `v1.9.8-cytracon.10` | No infra hardcodes; shops/ops/remote AI only via Settings |
| `v1.9.8-cytracon.9` | Bookmark/AI capture fix, Grok/Codex accordion + kind resume |
| `v1.9.8-cytracon.8` | Resume kind fix (no Grok→Codex) |
| `v1.9.8-cytracon.7` | Bookmark accordion by theme |
| `v1.9.8-cytracon.4` | Full Cytracon workflow UI + prefs |
| `v1.9.8-cytracon.1` | Security hardening baseline |

---

## Support & license

* Issues: https://github.com/cytracon/tilix/issues  
* Upstream issues / translations: https://github.com/gnunn1/tilix  
* License: [MPL-2.0](LICENSE)
