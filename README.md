# Tilix (Cytracon Fork)

[![Upstream](https://img.shields.io/badge/upstream-gnunn1%2Ftilix-blue)](https://github.com/gnunn1/tilix)
[![License](https://img.shields.io/badge/license-MPL--2.0-green)](LICENSE)

**Repository:** https://github.com/cytracon/tilix  
**Upstream:** https://github.com/gnunn1/tilix (minimal maintenance; [maintainers wanted](https://github.com/gnunn1/tilix/issues/1700))  
**Current version:** **1.9.8-cytracon.9**  
**Install script:** [`scripts/tilix-cytracon.sh`](scripts/tilix-cytracon.sh) (install · update · package · publish · dock)

Tiling terminal emulator for Linux (GTK 3 + VTE), forked for **Cytracon ops / Magento / AI workflows**. Upstream Tilix features remain; this fork adds security fixes, header-bar productivity tools, and file-manager integration for **Nemo** (and Nautilus).

Original project site: [tilix-web](https://gnunn1.github.io/tilix-web).

> **Release rule:** Bei jeder neuen Version immer mit anpassen:  
> `source/gx/tilix/constants.d` · `docs/CYTRACON-CHANGELOG.md` · **`README.md` (diese Datei)** · Tag `v1.9.8-cytracon.N` · `tilix-cytracon package` / `publish`.

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

Empty shops/quick-actions lists load Cytracon defaults (VPS, Fail2ban, Magento shops, cache flush, etc.).

### Security & reliability

| Item | Notes |
|------|--------|
| OSC 7 crash fix | Invalid directory URIs no longer segfault the process |
| Safer paste heuristics | Beyond `sudo`+newline |
| Trigger / custom-link shell confirm | Default **on** |
| Password insert | Never synced to other panes; optional remote warning |
| AI resume by `kind` | Grok sessions never open under Codex |
| Bookmark / menu buttons | Correct per-row command (D loop-capture fix) |
| Ubuntu Dock | Install script writes Cytracon `.desktop` + wrapper (same app-id pin) |
| Bookmarks install safety | Pack scripts **never** overwrite `bookmarks.json` (symlink-safe) |

### File manager integration

| Manager | Status |
|---------|--------|
| **Nemo** (primary for this fork) | Hardened **`.nemo_action`** entries + `tilix-open-location` helper |
| **Nautilus** | Hardened Python extension `data/nautilus/open-tilix.py` |

Nemo does **not** load Nautilus Python extensions. Use the Nemo installer below.

### Other

- Copy scrollback to clipboard: `Ctrl+Shift+O`
- Copy scrollback to session-log directory (Ops menu)
- Example packs: `data/cytracon/` (bookmarks example, ops session layout)
- Docs: [Audit](docs/CYTRACON-AUDIT-2026-07-14.md) · [Changelog](docs/CYTRACON-CHANGELOG.md) · [Auto-Update](docs/AUTO-UPDATE.md)

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
tilix-cytracon dock           # Desktop/Dock-Eintrag erneuern (ohne Kill)
# tilix-cytracon dock --kill  # optional: laufende Tilix-Fenster beenden
```

#### Google Drive / Multimedia (oft `noexec`)

```bash
# FALSCH:
#   sudo ./tilix-cytracon.sh          → Permission denied + falscher Owner
#   ./tilix-cytracon.sh               → oft noexec auf Drive

# RICHTIG:
bash "/home/bbachmann/Google Drive/BBachmann/Downloads/tilix-cytracon.sh"

# oder:
cp "/home/bbachmann/Google Drive/BBachmann/Downloads/tilix-cytracon.sh" /tmp/
cp "/home/bbachmann/Google Drive/BBachmann/Downloads"/tilix-cytracon-*-linux-x86_64.tar.gz /tmp/ 2>/dev/null || true
bash /tmp/tilix-cytracon.sh
```

Das Script findet Packages automatisch in `~/Downloads`, Google Drive Downloads und `/tmp`.

#### Ohne lokale Datei (nach Push des Scripts auf GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/cytracon/tilix/master/scripts/tilix-cytracon.sh | bash
```

#### Build-PC (neue Version veröffentlichen)

```bash
cd ~/src/tilix
# 1) Version bumpen: constants.d + CHANGELOG + README (diese Datei!)
dub build --compiler=ldc2 --build=release
install -Dm755 tilix ~/.local/libexec/tilix

tilix-cytracon package              # tar.gz → /tmp + Downloads + Drive
GITHUB_TOKEN=ghp_… tilix-cytracon publish   # Tag + GitHub Release
# oder Tag pushen → Actions (.github/workflows/release.yml)
```

### Was das Install-Script macht

| Schritt | Ziel |
|---------|------|
| Binary | `~/.local/libexec/tilix` |
| Wrapper | `~/.local/bin/tilix` (PATH + GSettings schemas) |
| Updater | `~/.local/bin/tilix-update` (= `tilix-cytracon`) |
| **Ubuntu Dock** | `~/.local/share/applications/com.gexperts.Tilix.desktop` (**Tilix (Cytracon)**), gleiche App-ID → Pin bleibt |
| Schemas | `~/.local/share/glib-2.0/schemas/` + `glib-compile-schemas` |
| Kill offener Fenster | **nein** (nur `dock --kill` explizit) |

`~/.local/bin` muss vor `/usr/bin` in `PATH` stehen (Distro-Tilix 1.9.6 sonst gewinnt).

Nach Upgrade: Tilix-Fenster **selbst** schließen und neu starten (oder Dock-Icon).  
Optional LAN: `./scripts/deploy-tilix-cytracon-home.sh`

---

## Quick extras (from source / packs)

```bash
./scripts/install-nemo-tilix-actions.sh
./scripts/install-cytracon-packs.sh --sessions   # überschreibt bookmarks.json NICHT
```

---

## Building

Written in [D](https://dlang.org/) + GTK 3 (gtkd). Compilers: **LDC** or **DMD** (not GDC).

```bash
export PATH="$HOME/.local/opt/ldc2/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DFLAGS="-L-L$HOME/.local/lib"

dub build --compiler=ldc2 --build=release
install -Dm755 tilix ~/.local/libexec/tilix
tilix-cytracon package    # empfohlen statt install.sh für Cytracon-Layout
```

Dependencies (see `dub.json`): **gtkd** / **vte** ≥ 3.11.0.

Meson is also supported: [Building with Meson](https://github.com/gnunn1/tilix/wiki/Building-with-Meson).

### Runtime libraries

* GTK 3.18+
* VTE 0.46+ (OSC 52 clipboard when VTE ≥ 0.76)
* dconf / GSettings

---

## Upstream Tilix features (unchanged)

* Horizontal / vertical splits, drag & drop rearrange and detach
* Tabs or session sidebar
* Synchronized input across terminals
* Save / load session layouts
* Custom titles, color schemes, transparency, background images
* [Quake mode](https://github.com/gnunn1/tilix/wiki/Quake-Mode)
* Custom hyperlinks, profile triggers (some need patched VTE)

---

## Scripts reference

| Script | Purpose |
|--------|---------|
| **`scripts/tilix-cytracon.sh`** | **All-in-one:** install · update · package · publish · dock |
| `scripts/tilix-update.sh` | Alias of `tilix-cytracon.sh` |
| `scripts/install-tilix-cytracon.sh` | Alias of `tilix-cytracon.sh` |
| `scripts/tilix-open-location` | Hardened open path/URI for file managers |
| `scripts/install-nemo-tilix-actions.sh` | Install Nemo context-menu actions |
| `scripts/install-cytracon-packs.sh` | Example sessions (never overwrites bookmarks.json) |
| `scripts/deploy-tilix-cytracon-home.sh` | LAN deploy to laptop / multimedia |
| `install.sh` | Full resource install (schemas, icons, …) |

---

## Tags

| Tag | Highlights |
|-----|------------|
| `v1.9.8-cytracon.9` | Bookmark/AI capture fix, Grok/Codex accordion + kind resume, all-in-one updater, Ubuntu dock desktop entry |
| `v1.9.8-cytracon.8` | Resume kind fix (no Grok→Codex) |
| `v1.9.8-cytracon.7` | Bookmark accordion by theme |
| `v1.9.8-cytracon.4` | Full Cytracon workflow UI + prefs |
| `v1.9.8-cytracon.1` | Security hardening baseline |

---

## Support & license

* Issues: https://github.com/cytracon/tilix/issues  
* Upstream issues / translations: https://github.com/gnunn1/tilix  
* License: [MPL-2.0](LICENSE)

---

## Migrating from Terminix (upstream note)

```bash
dconf dump /com/gexperts/Terminix/ > terminix.dconf
dconf load /com/gexperts/Tilix/ < terminix.dconf
# optional cleanup:
# dconf reset -f /com/gexperts/Terminix/
# mv ~/.config/terminix ~/.config/tilix
```
