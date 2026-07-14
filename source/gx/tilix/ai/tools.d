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
 * list_command optional — output lines should start with a UUID.
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
        if (parts.length >= 4) t.listCommand = parts[3 .. $].join("|").strip(); // allow | in list cmd? rare
        // re-parse carefully: only first 3 pipes split name/cmd/resume, rest is list
        if (parts.length > 4) {
            t.listCommand = parts[3 .. $].join("|").strip();
        }
        return t;
    }

    string buildResume(string id) const {
        if (resumeCommand.length == 0) return "";
        return resumeCommand.replace("{id}", id);
    }

    bool supportsResume() const {
        return resumeCommand.length > 0;
    }
}

struct AISessionEntry {
    string id;
    string summary;
    string updated; // free-form date string
    string status;
}

/** Default Cytracon AI tools (desktop + server wrappers). */
string[] defaultAIToolSettings() {
    return [
        "Grok|grok|grok --resume {id}|grok sessions list -n 30",
        "Codex|codex|codex resume {id}|",
        "Grok AI (Server)|ssh -t -i ~/.ssh/id_cytracon2 root@157.90.81.172 grokai|ssh -t -i ~/.ssh/id_cytracon2 root@157.90.81.172 'cd /AI && /AI/.grok/bin/grok --resume {id}'|ssh -i ~/.ssh/id_cytracon2 root@157.90.81.172 'cd /AI && /AI/.grok/bin/grok sessions list -n 20'",
        "Codex AI (Server)|ssh -t -i ~/.ssh/id_cytracon2 root@157.90.81.172 codexai|ssh -t -i ~/.ssh/id_cytracon2 root@157.90.81.172 'cd /AI && codex resume {id}'|"
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
    foreach (line; output.splitLines()) {
        line = line.strip();
        if (line.length == 0) continue;
        if (line.startsWith("SESSION ID") || line.startsWith("---") || line.startsWith("(no")) continue;
        auto m = matchFirst(line, uuidRe);
        if (!m) continue;
        AISessionEntry e;
        e.id = m.hit;
        // remaining text after UUID as summary-ish
        auto rest = line[m.pre.length + m.hit.length .. $].strip();
        // Drop date/status columns roughly: keep last long token chunk as summary
        e.summary = rest;
        // Try to extract dates (YYYY-MM-DD)
        auto dateRe = ctRegex!(`(\d{4}-\d{2}-\d{2})`);
        auto dates = matchAll(rest, dateRe);
        string[] foundDates;
        foreach (d; dates) foundDates ~= d.hit;
        if (foundDates.length >= 2) e.updated = foundDates[1];
        else if (foundDates.length == 1) e.updated = foundDates[0];
        // Status word after dates
        auto statusRe = ctRegex!(`\b(local|remote|both|archived)\b`, "i");
        auto sm = matchFirst(rest, statusRe);
        if (sm) e.status = sm.hit;
        // Clean summary: text after last status or after dates
        auto parts = rest.split();
        if (parts.length > 3) {
            // find status index
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
 * List sessions for a tool via list_command, or filesystem fallback for Codex.
 */
AISessionEntry[] listSessionsForTool(AITool tool, int limit = 30) {
    AISessionEntry[] entries;
    if (tool.listCommand.length > 0) {
        try {
            auto p = executeShell(tool.listCommand);
            if (p.status == 0 || p.output.length > 0) {
                entries = parseSessionListOutput(p.output);
            } else {
                warningf("list_command failed (%s): %s", p.status, p.output);
            }
        } catch (Exception e) {
            warningf("list_command error: %s", e.msg);
        }
    }
    if (entries.length == 0 && tool.name.toLower().canFind("codex") && !tool.command.canFind("ssh")) {
        entries = listCodexSessionsFromFS(limit);
    }
    if (entries.length > limit) {
        entries = entries[0 .. limit];
    }
    return entries;
}

/** Scan ~/.codex/sessions for recent rollouts. */
AISessionEntry[] listCodexSessionsFromFS(int limit = 30) {
    AISessionEntry[] entries;
    string root = buildPath(Util.getHomeDir(), ".codex", "sessions");
    if (!exists(root)) return entries;
    Tuple!(SysTime, string)[] found; // mtime, id
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
        entries ~= e;
    }
    return entries;
}
