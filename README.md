# Tilix (Cytracon Fork)

[![Upstream](https://img.shields.io/badge/upstream-gnunn1%2Ftilix-blue)](https://github.com/gnunn1/tilix)
[![License](https://img.shields.io/badge/license-MPL--2.0-green)](LICENSE)

**Repository:** https://github.com/cytracon/tilix  
**Upstream:** https://github.com/gnunn1/tilix (minimal maintenance; [maintainers wanted](https://github.com/gnunn1/tilix/issues/1700))  
**Current version:** **1.9.8-cytracon.9**

Tiling terminal emulator for Linux (GTK 3 + VTE), forked for **Cytracon ops / Magento / AI workflows**. Upstream Tilix features remain; this fork adds security fixes, header-bar productivity tools, and file-manager integration for **Nemo** (and Nautilus).

Original project site: [tilix-web](https://gnunn1.github.io/tilix-web).

---

## Cytracon features

### Header bar (navigation)

| Control | What it does | Shortcut |
|---------|----------------|----------|
| **Bookmarks** | Searchable popover over all bookmarks | `Ctrl+Shift+B` |
| **AI** | Tools, resume, **unified recent** Grok/Codex sessions | `Ctrl+Shift+A` |
| **Ops** | Shops, server/cache/status quick actions, ops layout, session log | `Ctrl+Shift+Q` |

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
| AI resume listing | Works when launched from Ubuntu Dock (PATH + FS fallback) |
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
- Docs: [Audit](docs/CYTRACON-AUDIT-2026-07-14.md) · [Changelog](docs/CYTRACON-CHANGELOG.md)

---

## Install & auto-update (all machines)

Repo is **private**. Updates use **GitHub Releases** (prebuilt `linux-x86_64` tarball) — no LDC on laptops.

### 1) One-time token (every PC)

Fine-grained PAT with **Contents: Read** on `cytracon/tilix` (or classic `repo`):

```bash
mkdir -p ~/.config/tilix && chmod 700 ~/.config/tilix
echo 'github_pat_…' > ~/.config/tilix/github-token
chmod 600 ~/.config/tilix/github-token
```

### 2) Update / first install

```bash
./scripts/tilix-update.sh          # or: tilix-update
tilix-update --check               # exit 1 = update available
tilix-update --force               # reinstall latest
tilix-update --install-timer       # daily systemd --user timer
```

Install path: `~/.local/libexec/tilix` + wrapper `~/.local/bin/tilix`.  
After upgrade: fully quit (`pkill -x tilix`) and start again.

### 3) Publish a new version (build machine)

```bash
./scripts/publish-github-release.sh
# packages tarball, git push, creates GitHub Release asset
```

Or push a tag `v1.9.8-cytracon.N` — GitHub Actions builds and releases automatically.

### 4) LAN deploy (optional)

```bash
./scripts/deploy-tilix-cytracon-home.sh   # package + scp to laptop/multimedia
```

Details: [docs/AUTO-UPDATE.md](docs/AUTO-UPDATE.md)

Ensure `~/.local/bin` is first on `PATH` so Cytracon wins over distro `/usr/bin/tilix`.

Desktop entry: `~/.local/share/applications/com.gexperts.Tilix.desktop`  
(Name: **Tilix (Cytracon)**; same app-id so Ubuntu Dock pin keeps working.)

---

## Quick install (from source)

```bash
install -Dm 644 data/gsettings/com.gexperts.Tilix.gschema.xml \
  ~/.local/share/glib-2.0/schemas/
glib-compile-schemas ~/.local/share/glib-2.0/schemas/
./scripts/install-nemo-tilix-actions.sh
./scripts/install-cytracon-packs.sh --sessions
```

---

## Building

Written in [D](https://dlang.org/) + GTK 3 (gtkd). Compilers: **LDC** or **DMD** (not GDC).

```bash
# with LDC
dub build --compiler=ldc2 --build=release

# user install (no root)
./install.sh "$HOME/.local"
# then add ~/.local/share to XDG_DATA_DIRS and use the GSettings steps above
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
| `scripts/tilix-open-location` | Hardened open path/URI for file managers |
| `scripts/install-nemo-tilix-actions.sh` | Install Nemo context-menu actions |
| `scripts/install-cytracon-packs.sh` | Example sessions (and example bookmarks file only) |
| `install.sh` | Full resource install (schemas, icons, …) |

---

## Tags

| Tag | Highlights |
|-----|------------|
| `v1.9.8-cytracon.4` | Full Cytracon workflow UI + prefs |
| `v1.9.8-cytracon.3` | AI resume PATH/FS fix |
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
