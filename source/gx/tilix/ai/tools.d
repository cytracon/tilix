/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.ai.tools;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.experimental.logger;
import std.file;
import std.json;
import std.path;
import std.process;
import std.regex;
import std.string;
import std.typecons : Tuple, tuple;

import gio.Settings : GSettings = Settings;

import glib.Util;

import gx.tilix.preferences;

/**
 * One AI tool definition (editable in Preferences).
 *
 * Stored in GSettings as pipe-separated fields:
 *   name|command|resume_command|list_command
 *
 * resume_command may contain {id} placeholder.
 * list_command optional — output lines should contain a UUID.
 */
struct AITool {
    string name;
    string command;        // start new interactive session
    string resumeCommand;  // template with {id}
    string listCommand;    // optional shell command to list sessions

    string toSetting() const {
        return name ~ "|" ~ command ~ "|" ~ resumeCommand ~ "|" ~ listCommand;
    }

    static AITool fromSetting(string raw) {
        AITool t;
        auto parts = raw.split("|");
        if (parts.length >= 1) t.name = parts[0].strip();
        if (parts.length >= 2) t.command = parts[1].strip();
        if (parts.length >= 3) t.resumeCommand = parts[2].strip();
        if (parts.length >= 4) t.listCommand = parts[3 .. $].join("|").strip();
        return t;
    }

    string buildResume(string id) const {
        if (resumeCommand.length == 0) return "";
        return resumeCommand.replace("{id}", id);
    }

    bool supportsResume() const {
        return resumeCommand.length > 0;
    }

    bool isGrokLike() const {
        auto n = name.toLower();
        auto c = command.toLower();
        return n.canFind("grok") || c.canFind("grok");
    }

    bool isCodexLike() const {
        auto n = name.toLower();
        auto c = command.toLower();
        return n.canFind("codex") || c.canFind("codex");
    }

    bool isRemote() const {
        return command.canFind("ssh") || listCommand.canFind("ssh");
    }
}

struct AISessionEntry {
    string id;
    string summary;
    string updated;
    string status;
}

/** Last diagnostic from listSessionsForTool (for UI). */
__gshared string lastListDiagnostic;

private string homeDir() {
    string h = Util.getHomeDir();
    if (h.length == 0) {
        h = environment.get("HOME");
    }
    return h;
}

/** PATH as used by interactive shells (GNOME apps often miss ~/.local/bin). */
string userPathPrefix() {
    string h = homeDir();
    return buildPath(h, ".local", "bin") ~ ":" ~
           buildPath(h, ".grok", "bin") ~ ":" ~
           buildPath(h, ".npm-global", "bin") ~ ":" ~
           buildPath(h, "bin") ~ ":" ~
           "/usr/local/bin:/usr/bin:/bin";
}

/**
 * Run a shell command with a sane PATH and stderr merged into stdout.
 * GNOME-launched Tilix often has PATH without ~/.local/bin.
 */
Tuple!(int, string) runUserShell(string command) {
    string wrapped = "export PATH=\"" ~ userPathPrefix() ~ ":$PATH\"; " ~ command ~ " 2>&1";
    try {
        auto p = executeShell(wrapped);
        return tuple(p.status, p.output);
    } catch (Exception e) {
        return tuple(1, e.msg);
    }
}

string resolveGrokBinary() {
    string h = homeDir();
    string[] candidates = [
        buildPath(h, ".local", "bin", "grok"),
        buildPath(h, ".grok", "bin", "grok"),
        "/usr/local/bin/grok",
        "/usr/bin/grok"
    ];
    foreach (c; candidates) {
        if (exists(c)) return c;
    }
    return "grok";
}

string resolveCodexBinary() {
    string h = homeDir();
    string[] candidates = [
        buildPath(h, ".local", "bin", "codex"),
        "/usr/local/bin/codex",
        "/usr/bin/codex"
    ];
    foreach (c; candidates) {
        if (exists(c)) return c;
    }
    // npm global often only has codex.js via symlink in /usr/local
    return "codex";
}

/** Default Cytracon AI tools (absolute-ish paths where possible). */
string[] defaultAIToolSettings() {
    string grok = resolveGrokBinary();
    string codex = resolveCodexBinary();
    string key = buildPath(homeDir(), ".ssh", "id_cytracon2");
    string sshBase = "ssh -o BatchMode=yes -i " ~ key ~ " root@157.90.81.172";
    return [
        "Grok|" ~ grok ~ "|" ~ grok ~ " --resume {id}|" ~ grok ~ " sessions list -n 40",
        "Codex|" ~ codex ~ "|" ~ codex ~ " resume {id}|",
        "Grok AI (Server)|" ~ sshBase ~ " -t grokai|" ~ sshBase ~ " -t 'cd /AI && /AI/.grok/bin/grok --resume {id}'|" ~ sshBase ~ " 'cd /AI && /AI/.grok/bin/grok sessions list -n 25'",
        "Codex AI (Server)|" ~ sshBase ~ " -t codexai|" ~ sshBase ~ " -t 'cd /AI && codex resume {id}'|"
    ];
}

AITool[] loadAITools(GSettings gs = null) {
    if (gs is null) {
        gs = new GSettings(SETTINGS_ID);
    }
    string[] raw;
    try {
        raw = gs.getStrv(SETTINGS_AI_TOOLS_KEY);
    } catch (Exception e) {
        warningf("Could not load AI tools: %s", e.msg);
        raw = null;
    }
    if (raw is null || raw.length == 0) {
        raw = defaultAIToolSettings();
    }
    AITool[] tools;
    foreach (line; raw) {
        if (line.strip().length == 0) continue;
        auto t = AITool.fromSetting(line);
        if (t.name.length > 0 && t.command.length > 0) {
            tools ~= t;
        }
    }
    return tools;
}

void saveAITools(AITool[] tools, GSettings gs = null) {
    if (gs is null) {
        gs = new GSettings(SETTINGS_ID);
    }
    string[] raw;
    foreach (t; tools) {
        if (t.name.length > 0 && t.command.length > 0) {
            raw ~= t.toSetting();
        }
    }
    gs.setStrv(SETTINGS_AI_TOOLS_KEY, raw);
}

private auto uuidRe = ctRegex!(`([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})`);

/**
 * Parse session list output (grok sessions list style or any line with a UUID).
 */
AISessionEntry[] parseSessionListOutput(string output) {
    AISessionEntry[] result;
    bool[string] seen;
    foreach (line; output.splitLines()) {
        line = line.strip();
        if (line.length == 0) continue;
        if (line.startsWith("SESSION ID") || line.startsWith("---") || line.startsWith("(no")) continue;
        // skip pure error noise without UUID
        auto m = matchFirst(line, uuidRe);
        if (!m) continue;
        if (m.hit in seen) continue;
        seen[m.hit] = true;

        AISessionEntry e;
        e.id = m.hit;
        auto rest = line[m.pre.length + m.hit.length .. $].strip();
        e.summary = rest;

        auto dateRe = ctRegex!(`(\d{4}-\d{2}-\d{2})`);
        auto dates = matchAll(rest, dateRe);
        string[] foundDates;
        foreach (d; dates) foundDates ~= d.hit;
        if (foundDates.length >= 2) e.updated = foundDates[1];
        else if (foundDates.length == 1) e.updated = foundDates[0];

        auto statusRe = ctRegex!(`\b(local|remote|both|archived)\b`, "i");
        auto sm = matchFirst(rest, statusRe);
        if (sm) e.status = sm.hit;

        auto parts = rest.split();
        if (parts.length > 0) {
            size_t start = 0;
            foreach (i, p; parts) {
                if (p == "local" || p == "remote" || p == "both" || p == "archived") {
                    start = i + 1;
                    break;
                }
                if (matchFirst(p, dateRe)) start = i + 1;
            }
            if (start < parts.length) {
                e.summary = parts[start .. $].join(" ");
            }
        }
        if (e.summary.length == 0) e.summary = e.id[0 .. min(8, e.id.length)];
        result ~= e;
    }
    return result;
}

/**
 * List sessions for a tool via list_command, with PATH fix + FS fallbacks.
 */
AISessionEntry[] listSessionsForTool(AITool tool, int limit = 40) {
    lastListDiagnostic = "";
    AISessionEntry[] entries;
    string[] diagnostics;

    if (tool.listCommand.length > 0) {
        auto p = runUserShell(tool.listCommand);
        diagnostics ~= format("list_cmd status=%s out_len=%s", p[0], p[1].length);
        if (p[1].length > 0) {
            entries = parseSessionListOutput(p[1]);
            diagnostics ~= format("parsed=%s", entries.length);
            if (entries.length == 0 && p[1].length < 400) {
                diagnostics ~= "raw: " ~ p[1].replace("\n", " | ");
            }
        } else if (p[0] != 0) {
            diagnostics ~= "list_cmd produced no output (is PATH missing tools?)";
        }
    }

    // Filesystem fallbacks (local tools)
    if (entries.length == 0 && !tool.isRemote()) {
        if (tool.isGrokLike()) {
            auto fs = listGrokSessionsFromFS(limit);
            diagnostics ~= format("grok_fs=%s", fs.length);
            entries = fs;
        }
        if (entries.length == 0 && tool.isCodexLike()) {
            auto fs = listCodexSessionsFromFS(limit);
            diagnostics ~= format("codex_fs=%s", fs.length);
            entries = fs;
        }
    }

    // Remote grok without working list: still try local FS as weak fallback? skip.

    if (entries.length > limit) {
        entries = entries[0 .. limit];
    }
    lastListDiagnostic = diagnostics.join("; ");
    if (entries.length == 0) {
        warningf("AI session list empty for %s: %s", tool.name, lastListDiagnostic);
    }
    return entries;
}

/** Scan ~/.grok/sessions for session dirs (+ summary.json when present). */
AISessionEntry[] listGrokSessionsFromFS(int limit = 40) {
    AISessionEntry[] entries;
    string root = buildPath(homeDir(), ".grok", "sessions");
    if (!exists(root)) {
        lastListDiagnostic ~= " grok_sessions_dir_missing=" ~ root;
        return entries;
    }
    Tuple!(SysTime, string, string)[] found; // mtime, id, summary
    try {
        foreach (string dir; dirEntries(root, SpanMode.depth)) {
            if (!dir.isDir) continue;
            string base = baseName(dir);
            auto m = matchFirst(base, uuidRe);
            if (!m) continue;
            // only leaf session dirs (contain chat_history or summary)
            string summaryPath = buildPath(dir, "summary.json");
            string chatPath = buildPath(dir, "chat_history.jsonl");
            if (!exists(summaryPath) && !exists(chatPath)) continue;

            SysTime mt;
            try { mt = timeLastModified(dir); } catch (Exception) { continue; }

            string summary = "grok " ~ m.hit[0 .. min(8, m.hit.length)];
            if (exists(summaryPath)) {
                try {
                    auto j = parseJSON(readText(summaryPath));
                    foreach (key; ["generated_title", "session_summary", "summary", "title", "preview"]) {
                        if (key in j && j[key].type == JSONType.string && j[key].str.length > 0) {
                            summary = j[key].str;
                            break;
                        }
                    }
                    if ("info" in j && j["info"].type == JSONType.object) {
                        auto info = j["info"];
                        if ("cwd" in info && info["cwd"].type == JSONType.string) {
                            // keep title, cwd is optional context
                        }
                    }
                    if (exists(summaryPath)) {
                        try { mt = timeLastModified(summaryPath); } catch (Exception) {}
                    }
                } catch (Exception) {}
            }
            if (summary.length > 100) summary = summary[0 .. 100] ~ "…";
            found ~= tuple(mt, m.hit, summary);
        }
    } catch (Exception e) {
        warningf("Grok FS scan failed: %s", e.msg);
        return entries;
    }
    sort!((a, b) => a[0] > b[0])(found);
    bool[string] seen;
    foreach (item; found) {
        if (item[1] in seen) continue;
        seen[item[1]] = true;
        if (entries.length >= limit) break;
        AISessionEntry e;
        e.id = item[1];
        auto iso = item[0].toISOExtString();
        e.updated = iso.length >= 10 ? iso[0 .. 10] : iso;
        e.summary = item[2];
        e.status = "local";
        entries ~= e;
    }
    return entries;
}

/**
 * Unified recent sessions from local Grok + Codex (for header menu).
 */
AISessionEntry[] listUnifiedRecentSessions(int limit = 15) {
    AISessionEntry[] all;
    auto g = listGrokSessionsFromFS(limit * 2);
    foreach (ref e; g) {
        if (e.status.length == 0) e.status = "grok";
        else e.status = "grok/" ~ e.status;
        e.summary = "[Grok] " ~ e.summary;
    }
    auto c = listCodexSessionsFromFS(limit * 2);
    foreach (ref e; c) {
        e.status = "codex";
        e.summary = "[Codex] " ~ e.summary;
    }
    all ~= g;
    all ~= c;
    // sort by updated string roughly (ISO date) — also keep original order from FS (already mtime sorted)
    // Interleave by re-sorting if updated looks like ISO date
    // Simple: take from each list already sorted, merge by updated desc
    sort!((a, b) => a.updated > b.updated)(all);
    if (all.length > limit) all = all[0 .. limit];
    return all;
}

/** Scan ~/.codex/sessions for recent rollouts. */
AISessionEntry[] listCodexSessionsFromFS(int limit = 40) {
    AISessionEntry[] entries;
    string root = buildPath(homeDir(), ".codex", "sessions");
    if (!exists(root)) {
        lastListDiagnostic ~= " codex_sessions_dir_missing=" ~ root;
        return entries;
    }
    Tuple!(SysTime, string)[] found;
    try {
        foreach (string file; dirEntries(root, SpanMode.depth)) {
            if (!file.endsWith(".jsonl")) continue;
            auto base = baseName(file);
            if (!base.startsWith("rollout-")) continue;
            auto m = matchFirst(base, uuidRe);
            if (!m) continue;
            SysTime mt;
            try { mt = timeLastModified(file); } catch (Exception) { continue; }
            found ~= tuple(mt, m.hit);
        }
    } catch (Exception e) {
        warningf("Codex FS scan failed: %s", e.msg);
        return entries;
    }
    sort!((a, b) => a[0] > b[0])(found);
    foreach (i, item; found) {
        if (i >= limit) break;
        AISessionEntry e;
        e.id = item[1];
        auto iso = item[0].toISOExtString();
        e.updated = iso.length >= 10 ? iso[0 .. 10] : iso;
        e.summary = "codex " ~ e.id[0 .. min(8, e.id.length)];
        e.status = "local";
        // Try first line of jsonl for a prompt snippet
        try {
            string path = "";
            // re-find path is expensive; skip
        } catch (Exception) {}
        entries ~= e;
    }
    return entries;
}
