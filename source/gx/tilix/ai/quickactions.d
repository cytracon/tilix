/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.ai.quickactions;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;
import std.file;
import std.path;
import std.process : environment;
import std.string;

import gio.Settings : GSettings = Settings;

import glib.Util;

import gx.tilix.preferences;

/**
 * Quick action: name|command|section
 */
struct QuickAction {
    string name;
    string command;
    string section;

    string toSetting() const {
        return name ~ "|" ~ command ~ "|" ~ section;
    }

    static QuickAction fromSetting(string raw) {
        QuickAction q;
        auto parts = raw.split("|");
        if (parts.length >= 1) q.name = parts[0].strip();
        if (parts.length >= 2) q.command = parts[1].strip();
        if (parts.length >= 3) q.section = parts[2 .. $].join("|").strip();
        if (q.section.length == 0) q.section = "General";
        return q;
    }
}

struct ShopEntry {
    string name;
    string command;

    string toSetting() const {
        return name ~ "|" ~ command;
    }

    static ShopEntry fromSetting(string raw) {
        ShopEntry s;
        auto parts = raw.split("|");
        if (parts.length >= 1) s.name = parts[0].strip();
        if (parts.length >= 2) s.command = parts[1 .. $].join("|").strip();
        return s;
    }
}

private string homeDir() {
    string h = Util.getHomeDir();
    if (h.length == 0) h = environment.get("HOME");
    return h;
}

private string sshVps() {
    string key = buildPath(homeDir(), ".ssh", "id_cytracon2");
    return "ssh -o BatchMode=yes -i " ~ key ~ " root@157.90.81.172";
}

string[] defaultQuickActionsClean() {
    string s = sshVps();
    return [
        "VPS Shell|" ~ s ~ "|Server",
        "Fail2ban Status|" ~ s ~ " 'fail2ban-client status'|Server",
        "Load & Memory|" ~ s ~ " 'uptime; echo; free -h; echo; nproc'|Server",
        "Disk Usage|" ~ s ~ " 'df -h / /var /home 2>/dev/null; df -h'|Server",
        "Magento Cache Flush (cwd)|php bin/magento cache:flush|Cache",
        "Redis FLUSHDB (danger)|redis-cli FLUSHDB|Cache",
        "Varnish Ban All|" ~ s ~ " 'varnishadm \"ban req.url ~ .\"'|Cache",
        "PHP-FPM Restart 8.4|" ~ s ~ " 'systemctl restart php8.4-fpm'|Reload",
        "nginx Reload|" ~ s ~ " 'nginx -t && systemctl reload nginx'|Reload",
        "MariaDB Slow Log Tail|" ~ s ~ " 'tail -50 /var/log/mysql/mariadb-slow.log 2>/dev/null || journalctl -u mariadb -n 30 --no-pager'|Status"
    ];
}

string[] defaultShops() {
    string s = sshVps();
    return [
        "Platinum Hyvä (web436)|" ~ s ~ " 'cd /var/www/clients/client4/web436/web && sudo -u web436 bash'",
        "Platinum Staging (web384)|" ~ s ~ " 'cd /var/www/clients/client4/web384/web && sudo -u web384 bash'",
        "Platinum Prod (web55)|" ~ s ~ " 'cd /var/www/clients/client4/web55/web && sudo -u web55 bash'",
        "Schweizerwerk (web429)|" ~ s ~ " 'cd /var/www/clients/client138/web429/web && sudo -u web429 bash'",
        "Packshop (web53)|" ~ s ~ " 'cd /var/www/clients/client14/web53/web && sudo -u web53 bash'",
        "Cytracon (web12)|" ~ s ~ " 'cd /var/www/clients/client1/web12/web && sudo -u web12 bash'"
    ];
}

QuickAction[] loadQuickActions(GSettings gs = null) {
    if (gs is null) gs = new GSettings(SETTINGS_ID);
    string[] raw;
    try { raw = gs.getStrv(SETTINGS_QUICK_ACTIONS_KEY); } catch (Exception) { raw = null; }
    if (raw is null || raw.length == 0) raw = defaultQuickActionsClean();
    QuickAction[] outp;
    foreach (line; raw) {
        if (line.strip().length == 0) continue;
        auto q = QuickAction.fromSetting(line);
        if (q.name.length && q.command.length) outp ~= q;
    }
    return outp;
}

void saveQuickActions(QuickAction[] actions, GSettings gs = null) {
    if (gs is null) gs = new GSettings(SETTINGS_ID);
    string[] raw;
    foreach (a; actions) {
        if (a.name.length && a.command.length) raw ~= a.toSetting();
    }
    gs.setStrv(SETTINGS_QUICK_ACTIONS_KEY, raw);
}

ShopEntry[] loadShops(GSettings gs = null) {
    if (gs is null) gs = new GSettings(SETTINGS_ID);
    string[] raw;
    try { raw = gs.getStrv(SETTINGS_SHOPS_KEY); } catch (Exception) { raw = null; }
    if (raw is null || raw.length == 0) raw = defaultShops();
    ShopEntry[] outp;
    foreach (line; raw) {
        if (line.strip().length == 0) continue;
        auto s = ShopEntry.fromSetting(line);
        if (s.name.length && s.command.length) outp ~= s;
    }
    return outp;
}

void saveShops(ShopEntry[] shops, GSettings gs = null) {
    if (gs is null) gs = new GSettings(SETTINGS_ID);
    string[] raw;
    foreach (s; shops) {
        if (s.name.length && s.command.length) raw ~= s.toSetting();
    }
    gs.setStrv(SETTINGS_SHOPS_KEY, raw);
}

/**
 * Heuristic: command looks destructive / high-impact.
 */
bool isDestructiveCommand(string cmd) {
    if (cmd.length == 0) return false;
    string lower = cmd.toLower();
    static immutable string[] patterns = [
        "rm -rf", "rm -r ", "dist-upgrade", "full-upgrade",
        "drop database", "drop table", "mkfs", "dd if=",
        "flushall", "flushdb", "truncate ",
        "systemctl stop", "systemctl restart", "service .* restart",
        "nginx -s stop", "reboot", "shutdown", "init 0", "init 6",
        "varnishadm ban", "mysql -e \"delete", "mysqldump",
        "> /dev/sd", "chmod -r 777 /", "chown -r "
    ];
    foreach (p; patterns) {
        if (lower.indexOf(p) >= 0) return true;
    }
    // reload often disruptive on prod
    if (lower.indexOf("reload") >= 0 && (lower.indexOf("nginx") >= 0 || lower.indexOf("php") >= 0 || lower.indexOf("varnish") >= 0))
        return true;
    return false;
}

string defaultSessionLogPath() {
    return buildPath(homeDir(), ".claude", "session-logs");
}

string defaultOpsSessionPath() {
    string p1 = buildPath(homeDir(), ".config", "tilix", "sessions", "ops-triple.json");
    if (exists(p1)) return p1;
    string p2 = buildPath(homeDir(), "src", "tilix", "data", "cytracon", "sessions", "ops-triple.json");
    if (exists(p2)) return p2;
    return p1;
}

string resolveSessionLogPath(GSettings gs) {
    string p;
    try { p = gs.getString(SETTINGS_SESSION_LOG_PATH_KEY); } catch (Exception) {}
    if (p.strip().length == 0) p = defaultSessionLogPath();
    // expand ~
    if (p.startsWith("~/")) p = buildPath(homeDir(), p[2 .. $]);
    return p;
}

string resolveOpsSessionPath(GSettings gs) {
    string p;
    try { p = gs.getString(SETTINGS_OPS_SESSION_PATH_KEY); } catch (Exception) {}
    if (p.strip().length == 0) p = defaultOpsSessionPath();
    if (p.startsWith("~/")) p = buildPath(homeDir(), p[2 .. $]);
    return p;
}
