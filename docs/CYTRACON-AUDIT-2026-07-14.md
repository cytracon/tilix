# Cytracon Tilix Audit — 2026-07-14

**Fork:** https://github.com/cytracon/tilix  
**Upstream:** https://github.com/gnunn1/tilix  
**Local clone:** (local path omitted — not published)  
**Installed system version:** Tilix 1.9.6 / VTE 0.84 / GTK 3.24.52  
**Upstream tag/version in tree:** 1.9.7 (MPL-2.0, D language, GTK3 + VTE via GtkD 3.11.0)

---

## 1. Executive Summary

| Area | Rating | Notes |
|------|--------|-------|
| Maintenance | 🔴 Critical | Upstream seeks maintainers (#1700); only l10n/CI/deps in 2025–2026 |
| Security | 🟠 High | Confirmed crash vectors; weak unsafe-paste; trigger RCE-by-design; password UX gaps |
| Stability | 🟠 High | GNOME 47 crashes, Wayland issues, LDC runtime breakage, OSC-7 segfault |
| Architecture | 🟡 Medium | Monolithic `terminal.d` (~4.7k LOC), GTK3 lock-in, experimental VTE patches |
| Feature fit (Cytracon) | 🟢 Strong base | Splits, quake, sync input, bookmarks, profiles — good ops terminal |

**Bottom line:** Keep Tilix as daily driver; treat this fork as the place for crash/security fixes and Cytracon-specific features. Do **not** expect upstream feature velocity. Medium-term strategic options: (A) maintain this D/GTK3 fork, (B) track PR #2282 (GtkD→GID) toward GTK4, (C) evaluate Ghostty/WezTerm/Kitty if maintenance cost exceeds value.

---

## 2. Upstream Reality Check

- **Not fully dead**, but effectively unmaintained for features/bugs.
- README banner: *"Maintainers Wanted — no new features, PRs reviewed very slowly"*.
- **443 open issues**, ~10 open PRs (including important #2282 GID migration).
- Recent non-l10n work: GtkD pin, paste encoding fix (2024-12), prgname for Wayland icon (2025-12), Dependabot.
- Last real product work is sparse; community PRs pile up.

### High-impact open upstream issues

| Issue | Topic | Priority for us |
|-------|-------|-----------------|
| #1700 | Looking for maintainer | Strategic |
| #2244 | Crash on invalid OSC 7 URL | P0 fix in fork |
| #2239 / #2245 | GNOME 47 core dump / conda segfault | P0/P1 (env-dependent) |
| #2264 | LDC shared lib soname breakage | Packaging |
| #2198 | OSC 52 clipboard over SSH | High feature value |
| #2282 | GtkD → GID bindings (GTK4 path) | Strategic PR to evaluate/merge |
| #2293 | Invisible drag-icon blocks clicks | UX bugfix PR |

---

## 3. Security Findings

### S1 — CRITICAL: Uncaught exception → segfault on OSC 7 (directory URI)

**Where:** `source/gx/tilix/terminal/terminal.d`

```d
// addOnCurrentDirectoryUriChanged → getHostnameAndDirectory()
directory = URI.filenameFromUri(cwd, hostname);  // NO try/catch
```

**Contrast:** `openURI()` *does* wrap `filenameFromUri` in try/catch (lines ~2014–2021).

**Repro (upstream #2244):**
```bash
printf '\e]7;file://525198bb6eda/bin\e\\'; sleep 1000
```

**Impact:** Any remote host, malicious prompt, or broken OSC 7 sequence can crash the entire Tilix process (all panes/tabs).

**Fix:** Wrap `getHostnameAndDirectory` (and DnD path ~3413) in try/catch; log + ignore invalid URIs. Same class of bug as Terminator/xfce4-terminal.

**Severity:** Critical (availability / DoS against the terminal host process)

---

### S2 — HIGH: Triggers + custom hyperlinks = intentional RCE surface

**Where:** `processTrigger()` / custom link handler in `terminal.d`

| Action | Behavior |
|--------|----------|
| `EXECUTE_COMMAND` | `spawnShell(replaceMatchTokens(...))` |
| `RUN_PROCESS` | `executeShell(...)` then `feedChild` output |
| Custom hyperlink click | `spawnShell(command with $0,$1… groups)` |
| `SEND_TEXT` | Injects match-derived text into terminal |

**Threat model:**
1. User configures a trigger/hyperlink with `$1` etc. in the command.
2. Untrusted terminal output (SSH, `curl`, `cat` log) matches the regex.
3. Attacker-controlled capture groups flow into shell execution.

This is *by design* for power users, but there is **no sandbox, confirmation, or allowlist**.

**Recommendations:**
- Default: disable EXECUTE_COMMAND / RUN_PROCESS unless explicitly enabled with a scary confirmation.
- Require confirmation on first fire per session for shell-spawning actions.
- Document as "equivalent to auto-running shell on untrusted I/O".
- Prefer `spawn` with argv array over shell string where possible.

**Severity:** High (conditional on user configuration; default empty = lower risk)

---

### S3 — MEDIUM: Unsafe-paste detection is trivial to bypass

**Where:** `isPasteUnsafe()` in `terminal.d`

```d
return (text.indexOf("sudo") > -1) && (text.indexOf("\n") > -1);
```

**Misses:** `doas`, `pkexec`, `su -`, `curl|bash`, `wget|sh`, `rm -rf /`, base64-decoded payloads, `sudo` without newline (single-line), Unicode homoglyphs, etc.

**Recommendations:** Expand heuristics (configurable denylist), always warn on multi-line paste containing shell metacharacters when advanced paste is off, optional "require confirm for all multi-line pastes".

**Severity:** Medium (defense-in-depth failure; user can still click through)

---

### S4 — MEDIUM: Password manager inserts secrets as terminal keystrokes

**Where:** `password.d` + `feedChild(password)` in terminal actions.

- Secrets stored via libsecret (good).
- Insertion uses `vte.feedChild` → visible to shell, `script`, `tee`, remote host, and possibly logged.
- Edit dialog opens with empty password field (cannot verify without re-entry).
- TreeView ID column binds `COLUMN_NAME` instead of `COLUMN_ID` (UI bug, line ~140).

**Recommendations:** Optional bracketed paste; warn when inserting into remote sessions; fix column binding; never log password values (audit `trace` paths).

**Severity:** Medium

---

### S5 — LOW/FIXED: Nautilus open-tilix shell injection

**Where:** `data/nautilus/open-tilix.py`  
**Status:** Fixed pattern present (`Popen([...])` without `shell=True`, `shlex.quote` for remote path). Upstream PR #2155 closed.

**Residual:** Remote `ssh -t user@host` builds username/hostname without quoting. Low practical risk if Nautilus URI parse is strict; still worth hardening with `shlex.quote` on all interpolated fields and using argv form for `ssh` if possible.

**Severity:** Low residual

---

### S6 — LOW: Token replacement order bug in `replaceMatchTokens`

**Where:** `source/gx/tilix/terminal/regex.d`

```d
foreach(i, match; matches) {
    result = result.replace("$" ~ to!string(i - 1), match);
}
```

- Replaces from low→high → classic `$1` vs `$10` corruption.
- Index `i - 1` yields `$-1` for first element (noise).

Affects triggers and custom hyperlinks (security-relevant if mis-expanded commands run).

**Severity:** Low–Medium (correctness; can become security if commands mis-expand)

---

### S7 — INFO: D-Bus / GApplication remote control

- Service: `com.gexperts.Tilix` (`data/dbus/com.gexperts.Tilix.service`)
- Remote CLI can run actions, open sessions, quake-toggle, etc. on the primary instance.
- Scoped to the user session (normal GApplication model). Same-user local code execution already has shell access — acceptable, but document that `tilix -a …` is a control plane.

### S8 — INFO: Flatpak host spawn / env handling

- Complex Flatpak path builds env via `env.split("=")` — values containing `=` are dropped (bug).
- Host command path is necessary for Flatpak; audit periodically for path injection.

---

## 4. Bugs & Reliability

### Confirmed / high confidence

| ID | Finding | Location | Fix effort |
|----|---------|----------|------------|
| B1 | OSC 7 invalid URI segfault | `getHostnameAndDirectory` | Small |
| B2 | DnD `filenameFromUri` without try/catch | `onVTEDragDataReceived` | Small |
| B3 | Password TreeView column wrong index | `password.d:140` | Trivial |
| B4 | `replaceMatchTokens` order / `$-1` | `regex.d` | Small |
| B5 | Env var values with `=` dropped in Flatpak spawn | `buildHostCommandVariant` | Small |
| B6 | Unsafe paste only detects `sudo` | `isPasteUnsafe` | Small |
| B7 | GNOME 47 / gobject crashes | Upstream #2239/#2245 | Unknown / deps |
| B8 | LDC soname packaging breakage | Upstream #2264 | Packaging |
| B9 | Session profile missing → no fallback | `session.d` TODO | Medium |
| B10 | Invisible drag window blocks clicks | Upstream #2293 (open PR) | Medium (merge PR) |

### Structural debt

- `terminal.d` ~4672 lines — hard to review/test; extract trigger/URI/spawn modules.
- GTK3 + GtkD 3.11 — long-term dead end without #2282/GTK4 path.
- Experimental features need patched VTE (triggers/badges/notifications) — distro packages often lack patches → silent feature absence.
- 23 TODO/FIXME markers; little automated functional test coverage beyond regex unittests and CI build.

### Local install note

Desktop runs **1.9.6** (Ubuntu package) while upstream tree is **1.9.7**. Rebuild/install from this fork before verifying fixes.

---

## 5. Feature Recommendations (Cytracon Workstyle)

Prioritized for AI-assisted sysadmin, multi-SSH Magento/VPS work, Tilix quake + splits.

### P0 — Stability & Security (do first)

1. **Hardening patch set**
   - OSC 7 / DnD URI try/catch
   - Safer `replaceMatchTokens` (high→low indices)
   - Expand unsafe-paste heuristics
   - Password column bugfix
2. **OSC 52 clipboard** (upstream #2198) — copy from remote nvim/tmux to local clipboard over SSH (with allowlist + prompt).
3. **Crash telemetry opt-in** — write last exception + VTE/GTK versions to `~/.local/share/tilix/crash.log` for our audits.

### P1 — Ops productivity

4. **SSH profile packs** — bookmarks + profile auto-switch by hostname already exist; add importable “Cytracon hosts” JSON (shops, VPS, staging) and jump-host aware titles.
5. **Process-aware guardrails** — prevent close/suspend when long jobs run (upstream #2269 idea); show active process name in tab (partially present).
6. **Session layouts as code** — versionable layout files in `~/backups/` or git; CLI `tilix --session cytracon-ops.json`.
7. **Quake improvements** — multi-monitor focus, Wayland-safe geometry, restore last CWD reliably.
8. **Bell / notification routing** — desktop notify + optional Tilix bell → already partial; add filter by title regex (e.g. only Magento deploy shells).

### P2 — AI / modern terminal

9. **Semantic shell integration** (iTerm2/Kitty-style markers) — mark command start/end for “copy last command output”.
10. **Split groups for sync input** (upstream #279) — sync only selected panes (prod vs staging).
11. **Scrollback export** — one-click export pane output to `/tmp` or session-log path for incident notes.
12. **OSC 8 hyperlink + open in browser policy** — confirm external opens; block `file://` remote hosts (partially present).

### P3 — Strategic platform

13. **Evaluate merge of #2282 (GID bindings)** — prerequisite for GTK4 / future GNOME.
14. **CI on Ubuntu 24.04 + LDC** matching our workstation; publish `.deb` from `cytracon/tilix`.
15. **Optional: sidecar in Rust/Zig** only if D maintainer bandwidth fails — full rewrite is high cost; not recommended first.

### Explicit non-goals (for now)

- Full GTK4 rewrite from scratch
- Competing with Ghostty GPU renderer in year one
- Flatpak-only distribution (we need host tooling, SSH, docker sockets)

---

## 6. Recommended Fix Roadmap

### Sprint 0 (1–2 days) — Hardening PR on this fork

- [ ] Catch exceptions in `getHostnameAndDirectory` + DnD URI parse  
- [ ] Fix `replaceMatchTokens`  
- [ ] Expand `isPasteUnsafe`  
- [ ] Fix password TreeView column  
- [ ] Add `docs/` + CI status badge for cytracon fork  
- [ ] Manual test: OSC 7 crash repro must no longer kill process  

### Sprint 1 — Packaging

- [ ] Build with LDC on Ubuntu 24.04  
- [ ] Install over distro package or `/usr/local`  
- [ ] Verify quake, splits, libsecret passwords, Nautilus extension  

### Sprint 2 — High-value features

- [ ] OSC 52 (with security prompt)  
- [ ] Layout/session CLI polish  
- [ ] Cytracon bookmark pack  

### Sprint 3 — Platform

- [ ] Review/merge or re-base #2282  
- [ ] Decision gate: continue D fork vs migrate terminal  

---

## 7. Quick Wins (code pointers)

| Change | File | Notes |
|--------|------|-------|
| try/catch OSC 7 | `terminal.d` ~2649–2658 | Mirror `openURI` pattern |
| try/catch DnD | `terminal.d` ~3412–3414 | Same |
| Token replace | `regex.d` ~158–164 | Reverse index order; skip empty |
| Unsafe paste | `terminal.d` ~1433–1435 | Heuristic list |
| Password column | `password.d` ~140 | Use `COLUMN_ID` |
| Env split | `terminal.d` ~2909 | `findSplit("=")` once |

---

## 8. Competitive Context (if fork cost rises)

| Terminal | Pros | Cons vs Tilix |
|----------|------|----------------|
| **Ghostty** | Fast, modern, active | Less tiling layout DNA; newer ecosystem |
| **WezTerm** | Lua config, mux, SSH | Heavier config model |
| **Kitty** | GPU, kitten tools | Different UX |
| **GNOME Console** | Maintained with GNOME | Minimal features |
| **Tilix fork** | Already our muscle memory | GTK3/D maint burden |

Recommendation: **stay on Tilix fork for 6–12 months** with hardening; re-evaluate after GNOME deprecates more GTK3 paths.

---

## 9. Verification Notes

- Static audit of D sources + nautilus plugin + dbus service + upstream issue graph.
- Did **not** rebuild Tilix in this session (no full compile cycle).
- Did **not** reproduce OSC 7 crash live against installed 1.9.6 (recommended next step after patch).
- GitHub fork created as `cytracon/tilix` from `gnunn1/tilix` (full history).

---

## 10. References

- Upstream README maintainers notice  
- Issues: #1700, #2155, #2198, #2239, #2244, #2245, #2264, #2282, #2293  
- License: MPL-2.0 (modifications must stay MPL-compatible when published)
