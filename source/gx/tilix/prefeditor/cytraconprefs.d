/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.prefeditor.cytraconprefs;

import std.algorithm;
import std.conv;
import std.experimental.logger;
import std.format;
import std.string;

import gio.Settings : GSettings = Settings;

import gtk.Box;
import gtk.Button;
import gtk.CheckButton;
import gtk.ComboBox;
import gtk.Dialog;
import gtk.Entry;
import gtk.Grid;
import gtk.Label;
import gtk.ListStore;
import gtk.ScrolledWindow;
import gtk.SpinButton;
import gtk.TreeIter;
import gtk.TreePath;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.CellRendererText;
import gtk.Widget;
import gtk.Window;

import gtkc.gtktypes : GtkAlign;

import gx.gtk.settings;
import gx.gtk.util;
import gx.i18n.l10n;

import gx.tilix.ai.quickactions;
import gx.tilix.preferences;

/**
 * Preferences: Cytracon workflow (launch mode, header buttons, shops, quick actions, paths).
 */
class CytraconPreferences : Box {
private:
    GSettings gsSettings;
    BindingHelper bh;

    ListStore lsQuick;
    ListStore lsShops;
    TreeView tvQuick;
    TreeView tvShops;
    QuickAction[] quickActions;
    ShopEntry[] shops;

    enum Q_NAME = 0, Q_CMD = 1, Q_SEC = 2;
    enum S_NAME = 0, S_CMD = 1;

    void createUI() {
        setMarginLeft(18);
        setMarginRight(18);
        setMarginTop(18);
        setMarginBottom(18);
        setSpacing(8);

        addSection(_("Command launch"));
        auto bLaunch = new Box(Orientation.HORIZONTAL, 12);
        bLaunch.add(new Label(_("Run commands in")));
        // current / split-right / split-down / new-session
        auto cb = createNameValueCombo(
            [_("Current terminal"), _("New split right"), _("New split down"), _("New session")],
            SETTINGS_CMD_LAUNCH_MODE_VALUES);
        bh.bind(SETTINGS_CMD_LAUNCH_MODE_KEY, cb, "active-id", GSettingsBindFlags.DEFAULT);
        bLaunch.add(cb);
        add(bLaunch);

        auto cbNl = new CheckButton(_("Append Enter when injecting commands"));
        bh.bind(SETTINGS_AI_FEED_NEWLINE_KEY, cbNl, "active", GSettingsBindFlags.DEFAULT);
        add(cbNl);

        auto cbDest = new CheckButton(_("Confirm destructive bookmark / quick commands"));
        bh.bind(SETTINGS_BOOKMARK_CONFIRM_DESTRUCTIVE_KEY, cbDest, "active", GSettingsBindFlags.DEFAULT);
        add(cbDest);

        addSection(_("Header bar"));
        auto cbBm = new CheckButton(_("Show bookmarks button"));
        bh.bind(SETTINGS_HEADER_SHOW_BOOKMARKS_KEY, cbBm, "active", GSettingsBindFlags.DEFAULT);
        add(cbBm);
        auto cbAi = new CheckButton(_("Show AI menu"));
        bh.bind(SETTINGS_HEADER_SHOW_AI_KEY, cbAi, "active", GSettingsBindFlags.DEFAULT);
        add(cbAi);
        auto cbQ = new CheckButton(_("Show Ops / Quick menu"));
        bh.bind(SETTINGS_HEADER_SHOW_QUICK_KEY, cbQ, "active", GSettingsBindFlags.DEFAULT);
        add(cbQ);
        auto cbSearch = new CheckButton(_("Searchable bookmark popover (vs classic dialog)"));
        bh.bind(SETTINGS_BOOKMARK_HEADER_SEARCH_KEY, cbSearch, "active", GSettingsBindFlags.DEFAULT);
        add(cbSearch);

        auto bRecent = new Box(Orientation.HORIZONTAL, 12);
        bRecent.add(new Label(_("Unified recent AI sessions")));
        auto sp = new SpinButton(1, 50, 1);
        bh.bind(SETTINGS_AI_UNIFIED_RECENT_KEY, sp, "value", GSettingsBindFlags.DEFAULT);
        bRecent.add(sp);
        add(bRecent);

        addSection(_("Paths"));
        addPathRow(_("Session log directory"), SETTINGS_SESSION_LOG_PATH_KEY, _("Empty = ~/.claude/session-logs"));
        addPathRow(_("Ops session layout JSON"), SETTINGS_OPS_SESSION_PATH_KEY, _("Empty = auto-detect ops-triple.json"));

        addSection(_("Shops"));
        lsShops = new ListStore([GType.STRING, GType.STRING]);
        tvShops = new TreeView(lsShops);
        tvShops.appendColumn(new TreeViewColumn(_("Name"), new CellRendererText(), "text", S_NAME));
        tvShops.appendColumn(new TreeViewColumn(_("Command"), new CellRendererText(), "text", S_CMD));
        auto swS = new ScrolledWindow(tvShops);
        swS.setSizeRequest(-1, 120);
        swS.setShadowType(ShadowType.ETCHED_IN);
        add(swS);
        add(editButtons(
            () { editShop(-1); },
            () { auto i = selectedIndex(tvShops, lsShops); if (i >= 0) editShop(i); },
            () { auto i = selectedIndex(tvShops, lsShops); if (i >= 0 && i < shops.length) { shops = shops[0..i] ~ shops[i+1..$]; persistShops(); reloadShops(); } },
            () { shops = loadShopsFromDefaults(); persistShops(); reloadShops(); }
        ));

        addSection(_("Quick actions (Ops menu)"));
        lsQuick = new ListStore([GType.STRING, GType.STRING, GType.STRING]);
        tvQuick = new TreeView(lsQuick);
        tvQuick.appendColumn(new TreeViewColumn(_("Name"), new CellRendererText(), "text", Q_NAME));
        tvQuick.appendColumn(new TreeViewColumn(_("Section"), new CellRendererText(), "text", Q_SEC));
        tvQuick.appendColumn(new TreeViewColumn(_("Command"), new CellRendererText(), "text", Q_CMD));
        auto swQ = new ScrolledWindow(tvQuick);
        swQ.setSizeRequest(-1, 160);
        swQ.setShadowType(ShadowType.ETCHED_IN);
        add(swQ);
        add(editButtons(
            () { editQuick(-1); },
            () { auto i = selectedIndex(tvQuick, lsQuick); if (i >= 0) editQuick(i); },
            () { auto i = selectedIndex(tvQuick, lsQuick); if (i >= 0 && i < quickActions.length) { quickActions = quickActions[0..i] ~ quickActions[i+1..$]; persistQuick(); reloadQuick(); } },
            () { quickActions = loadQuickFromDefaults(); persistQuick(); reloadQuick(); }
        ));
    }

    void addSection(string title) {
        auto lbl = new Label(format("<b>%s</b>", title));
        lbl.setUseMarkup(true);
        lbl.setHalign(GtkAlign.START);
        lbl.setMarginTop(10);
        add(lbl);
    }

    void addPathRow(string label, string key, string placeholder) {
        auto b = new Box(Orientation.HORIZONTAL, 8);
        b.add(new Label(label));
        auto e = new Entry();
        e.setHexpand(true);
        e.setPlaceholderText(placeholder);
        bh.bind(key, e, "text", GSettingsBindFlags.DEFAULT);
        b.add(e);
        add(b);
    }

    Box editButtons(void delegate() onAdd, void delegate() onEdit, void delegate() onRemove, void delegate() onDefaults) {
        auto b = new Box(Orientation.HORIZONTAL, 6);
        auto ba = new Button(_("Add")); ba.addOnClicked(delegate(Button) { onAdd(); });
        auto be = new Button(_("Edit")); be.addOnClicked(delegate(Button) { onEdit(); });
        auto br = new Button(_("Remove")); br.addOnClicked(delegate(Button) { onRemove(); });
        auto bd = new Button(_("Restore defaults")); bd.addOnClicked(delegate(Button) { onDefaults(); });
        b.add(ba); b.add(be); b.add(br); b.add(bd);
        return b;
    }

    int selectedIndex(TreeView tv, ListStore ls) {
        auto sel = tv.getSelectedIter();
        if (sel is null) return -1;
        return ls.getPath(sel).getIndices()[0];
    }

    ShopEntry[] loadShopsFromDefaults() {
        ShopEntry[] r;
        foreach (line; defaultShops()) r ~= ShopEntry.fromSetting(line);
        return r;
    }

    QuickAction[] loadQuickFromDefaults() {
        QuickAction[] r;
        foreach (line; defaultQuickActionsClean()) r ~= QuickAction.fromSetting(line);
        return r;
    }

    void reloadShops() {
        shops = loadShops(gsSettings);
        lsShops.clear();
        foreach (s; shops) {
            auto it = lsShops.createIter();
            lsShops.setValue(it, S_NAME, s.name);
            lsShops.setValue(it, S_CMD, s.command);
        }
    }

    void reloadQuick() {
        quickActions = loadQuickActions(gsSettings);
        lsQuick.clear();
        foreach (q; quickActions) {
            auto it = lsQuick.createIter();
            lsQuick.setValue(it, Q_NAME, q.name);
            lsQuick.setValue(it, Q_CMD, q.command);
            lsQuick.setValue(it, Q_SEC, q.section);
        }
    }

    void persistShops() { saveShops(shops, gsSettings); }
    void persistQuick() { saveQuickActions(quickActions, gsSettings); }

    void editShop(int index) {
        ShopEntry cur;
        if (index >= 0 && index < shops.length) cur = shops[index];
        auto d = new SimpleKVDialog(cast(Window) getToplevel(), _("Shop"), cur.name, cur.command, _("Name"), _("SSH / command"));
        scope(exit) d.destroy();
        d.showAll();
        if (d.run() == ResponseType.OK) {
            auto s = ShopEntry(d.key, d.value);
            if (s.name.length == 0 || s.command.length == 0) return;
            if (index >= 0 && index < shops.length) shops[index] = s;
            else shops ~= s;
            persistShops();
            reloadShops();
        }
    }

    void editQuick(int index) {
        QuickAction cur;
        if (index >= 0 && index < quickActions.length) cur = quickActions[index];
        auto d = new QuickEditDialog(cast(Window) getToplevel(), cur);
        scope(exit) d.destroy();
        d.showAll();
        if (d.run() == ResponseType.OK) {
            auto q = d.result;
            if (q.name.length == 0 || q.command.length == 0) return;
            if (index >= 0 && index < quickActions.length) quickActions[index] = q;
            else quickActions ~= q;
            persistQuick();
            reloadQuick();
        }
    }

public:
    this(GSettings gsSettings) {
        super(Orientation.VERTICAL, 6);
        this.gsSettings = gsSettings;
        bh = new BindingHelper(gsSettings);
        createUI();
        reloadShops();
        reloadQuick();
        addOnDestroy(delegate(Widget) {
            if (bh !is null) { bh.unbind(); bh = null; }
        });
    }
}

private:

class SimpleKVDialog : Dialog {
    Entry eKey, eVal;
    this(Window parent, string title, string k, string v, string lblK, string lblV) {
        super(title, parent, GtkDialogFlags.MODAL + GtkDialogFlags.USE_HEADER_BAR,
            [_("OK"), _("Cancel")], [ResponseType.OK, ResponseType.CANCEL]);
        auto g = new Grid();
        g.setColumnSpacing(8); g.setRowSpacing(6);
        g.setMarginTop(12); g.setMarginBottom(12); g.setMarginStart(12); g.setMarginEnd(12);
        eKey = new Entry(); eKey.setText(k); eKey.setWidthChars(40);
        eVal = new Entry(); eVal.setText(v); eVal.setWidthChars(40);
        g.attach(new Label(lblK), 0, 0, 1, 1);
        g.attach(eKey, 1, 0, 1, 1);
        g.attach(new Label(lblV), 0, 1, 1, 1);
        g.attach(eVal, 1, 1, 1, 1);
        getContentArea().add(g);
    }
    @property string key() { return eKey.getText().strip(); }
    @property string value() { return eVal.getText().strip(); }
}

class QuickEditDialog : Dialog {
    Entry eName, eSec, eCmd;
    this(Window parent, QuickAction q) {
        super(_("Quick Action"), parent, GtkDialogFlags.MODAL + GtkDialogFlags.USE_HEADER_BAR,
            [_("OK"), _("Cancel")], [ResponseType.OK, ResponseType.CANCEL]);
        auto g = new Grid();
        g.setColumnSpacing(8); g.setRowSpacing(6);
        g.setMarginTop(12); g.setMarginBottom(12); g.setMarginStart(12); g.setMarginEnd(12);
        eName = new Entry(); eName.setText(q.name); eName.setWidthChars(40);
        eSec = new Entry(); eSec.setText(q.section.length ? q.section : "General"); eSec.setWidthChars(40);
        eCmd = new Entry(); eCmd.setText(q.command); eCmd.setWidthChars(40);
        g.attach(new Label(_("Name")), 0, 0, 1, 1); g.attach(eName, 1, 0, 1, 1);
        g.attach(new Label(_("Section")), 0, 1, 1, 1); g.attach(eSec, 1, 1, 1, 1);
        g.attach(new Label(_("Command")), 0, 2, 1, 1); g.attach(eCmd, 1, 2, 1, 1);
        getContentArea().add(g);
    }
    @property QuickAction result() {
        return QuickAction(eName.getText().strip(), eCmd.getText().strip(), eSec.getText().strip());
    }
}
