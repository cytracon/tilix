# Cytracon Tilix Changelog

## 1.9.8-cytracon.10 — 2026-07-15

### Privacy / public repo
- **No server/infrastructure hardcodes** in the published tree
- Shops, quick actions, remote AI tools: **GSettings only** (empty defaults)
- Example bookmarks/session layouts use generic placeholders
- Deploy script reads targets from env / `~/.config/tilix/deploy.env` (not in git)
- Nemo actions use `tilix-open-location` on PATH (no absolute home paths)

## 1.9.8-cytracon.9 — 2026-07-14

### Fixes
- **Bookmarks always ran the last entry's command** — D loop-variable capture in GTK button delegates. Fixed with `makeCmdButton` / per-call `.dup` captures. Same fix for AI sessions, tools, shops, and quick actions.

## 1.9.8-cytracon.8 — 2026-07-14

### Fixes
- **Grok sessions no longer resume with Codex** — resume uses explicit `kind` (`grok`|`codex`), not fragile `status.canFind("codex")`

### UI
- AI menu: **accordion split** — separate expanders for recent **Grok** and **Codex** sessions (like bookmark themes)

## 1.9.8-cytracon.1 — 2026-07-14

### Security
- Catch invalid OSC 7 / directory URIs (`filenameFromUri`) — prevents process-wide segfault (upstream #2244)
- Catch invalid dropped URIs in drag-and-drop
- Expand unsafe-paste heuristics (`doas`, `pkexec`, pipe-to-shell, `rm -rf /`, etc.)
- Confirm shell execution from triggers and custom hyperlinks (default **on**)
- Do **not** sync inserted passwords to synchronized-input peers
- Optional warning before inserting passwords into remote sessions (default **on**)
- Fix `replaceMatchTokens` `$1`/`$10` order bug
- Harden Nautilus `open-tilix.py` remote SSH command construction (quote + host/user validation)
- Flatpak host env: preserve values containing `=`

### Bug fixes
- Password manager TreeView ID column bound wrong field (`COLUMN_ID`)

### Features
- **Copy Output to Clipboard** (`Ctrl+Shift+O`) — full scrollback for incident notes
- Preferences: Security section (trigger confirm, remote password warn, OSC 52 policy flag)
- Cytracon bookmark pack + ops session layout (`data/cytracon/`, `scripts/install-cytracon-packs.sh`)
- Document OSC 52: provided by VTE ≥ 0.76 (this workstation: VTE 0.84)

### Packaging / identity
- Version: `1.9.8-cytracon.1`
- Fork: https://github.com/cytracon/tilix

## 1.9.8-cytracon.4 — 2026-07-14

### Features
- Searchable bookmark popover in header bar
- AI menu: unified recent Grok/Codex, resume, launch modes
- Ops menu: shops, server/cache/status actions, ops layout, session log export
- Preferences → Cytracon (+ AI Tools) for full configuration
- Destructive command confirmation
- Nemo hardened open-in-Tilix actions (`scripts/install-nemo-tilix-actions.sh`)

### Fixes
- AI resume listing when started from GNOME/Ubuntu Dock (PATH + FS fallback)
- Bookmark pack install never overwrites real `bookmarks.json`

## 1.9.8-cytracon.3 — 2026-07-14
- AI resume list PATH fix + Grok/Codex filesystem fallback

