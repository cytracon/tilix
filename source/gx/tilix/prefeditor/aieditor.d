/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.prefeditor.aieditor;

import std.algorithm;
import std.conv;
import std.experimental.logger;
import std.format;
import std.string;

import gio.Settings : GSettings = Settings;

import gtk.Box;
import gtk.Button;
import gtk.CellRendererText;
import gtk.CheckButton;
import gtk.Dialog;
import gtk.Entry;
import gtk.Grid;
import gtk.Label;
import gtk.ListStore;
import gtk.ScrolledWindow;
import gtk.TreeIter;
import gtk.TreePath;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.Widget;
import gtk.Window;

import gtkc.gtktypes : GtkAlign;

import gx.gtk.settings;
import gx.gtk.util;
import gx.i18n.l10n;

import gx.tilix.ai.tools;
import gx.tilix.preferences;

/**
 * Preferences page for defining AI tools (Grok, Codex, server wrappers, …).
 */
class AIPreferences : Box {
private:
    GSettings gsSettings;
    BindingHelper bh;
    TreeView tv;
    ListStore ls;
    AITool[] tools;

    enum COL_NAME = 0;
    enum COL_CMD = 1;
    enum COL_RESUME = 2;
    enum COL_LIST = 3;

    void createUI() {
        setMarginLeft(18);
        setMarginRight(18);
        setMarginTop(18);
        setMarginBottom(18);

        auto lbl = new Label(format("<b>%s</b>", _("AI Tools")));
        lbl.setUseMarkup(true);
        lbl.setHalign(GtkAlign.START);
        add(lbl);

        auto desc = new Label(_("Define AI CLIs shown in the header bar. Resume command may use {id}. List command should print session UUIDs (e.g. grok sessions list). Empty list restores Cytracon defaults."));
        desc.setLineWrap(true);
        desc.setHalign(GtkAlign.START);
        desc.setMarginBottom(6);
        add(desc);

        ls = new ListStore([GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
        tv = new TreeView(ls);
        tv.setHeadersVisible(true);
        tv.appendColumn(new TreeViewColumn(_("Name"), new CellRendererText(), "text", COL_NAME));
        tv.appendColumn(new TreeViewColumn(_("Start command"), new CellRendererText(), "text", COL_CMD));
        tv.appendColumn(new TreeViewColumn(_("Resume command"), new CellRendererText(), "text", COL_RESUME));
        tv.appendColumn(new TreeViewColumn(_("List command"), new CellRendererText(), "text", COL_LIST));

        auto sw = new ScrolledWindow(tv);
        sw.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        sw.setShadowType(ShadowType.ETCHED_IN);
        sw.setSizeRequest(-1, 220);
        sw.setHexpand(true);
        sw.setVexpand(true);
        add(sw);

        auto btnBox = new Box(Orientation.HORIZONTAL, 6);
        btnBox.setMarginTop(6);
        auto btnAdd = new Button(_("Add"));
        auto btnEdit = new Button(_("Edit"));
        auto btnRemove = new Button(_("Remove"));
        auto btnDefaults = new Button(_("Restore defaults"));
        btnAdd.addOnClicked(delegate(Button) { editTool(-1); });
        btnEdit.addOnClicked(delegate(Button) {
            auto sel = tv.getSelectedIter();
            if (sel is null) return;
            auto path = ls.getPath(sel);
            editTool(path.getIndices()[0]);
        });
        btnRemove.addOnClicked(delegate(Button) {
            auto sel = tv.getSelectedIter();
            if (sel is null) return;
            auto path = ls.getPath(sel);
            int idx = path.getIndices()[0];
            if (idx >= 0 && idx < tools.length) {
                tools = tools[0 .. idx] ~ tools[idx + 1 .. $];
                persist();
                reload();
            }
        });
        btnDefaults.addOnClicked(delegate(Button) {
            tools = loadAIToolsFromDefaults();
            persist();
            reload();
        });
        btnBox.add(btnAdd);
        btnBox.add(btnEdit);
        btnBox.add(btnRemove);
        btnBox.add(btnDefaults);
        add(btnBox);

        auto cbNl = new CheckButton(_("Append Enter when injecting AI commands"));
        bh.bind(SETTINGS_AI_FEED_NEWLINE_KEY, cbNl, "active", GSettingsBindFlags.DEFAULT);
        cbNl.setMarginTop(12);
        add(cbNl);
    }

    AITool[] loadAIToolsFromDefaults() {
        AITool[] t;
        foreach (line; defaultAIToolSettings()) {
            t ~= AITool.fromSetting(line);
        }
        return t;
    }

    void reload() {
        tools = loadAITools(gsSettings);
        ls.clear();
        foreach (t; tools) {
            auto iter = ls.createIter();
            ls.setValue(iter, COL_NAME, t.name);
            ls.setValue(iter, COL_CMD, t.command);
            ls.setValue(iter, COL_RESUME, t.resumeCommand);
            ls.setValue(iter, COL_LIST, t.listCommand);
        }
    }

    void persist() {
        saveAITools(tools, gsSettings);
    }

    void editTool(int index) {
        AITool current;
        if (index >= 0 && index < tools.length) {
            current = tools[index];
        }
        auto dlg = new AIToolEditDialog(cast(Window) getToplevel(), current);
        scope (exit) dlg.destroy();
        dlg.showAll();
        if (dlg.run() == ResponseType.OK) {
            auto t = dlg.result;
            if (t.name.length == 0 || t.command.length == 0) return;
            if (index >= 0 && index < tools.length) {
                tools[index] = t;
            } else {
                tools ~= t;
            }
            persist();
            reload();
        }
    }

public:
    this(GSettings gsSettings) {
        super(Orientation.VERTICAL, 6);
        this.gsSettings = gsSettings;
        bh = new BindingHelper(gsSettings);
        createUI();
        reload();
        addOnDestroy(delegate(Widget) {
            if (bh !is null) {
                bh.unbind();
                bh = null;
            }
        });
    }
}

private:

class AIToolEditDialog : Dialog {
    Entry eName, eCmd, eResume, eList;
    AITool _result;

    this(Window parent, AITool initial) {
        super(_("Edit AI Tool"), parent, GtkDialogFlags.MODAL + GtkDialogFlags.USE_HEADER_BAR,
            [_("OK"), _("Cancel")], [ResponseType.OK, ResponseType.CANCEL]);
        setDefaultResponse(ResponseType.OK);

        auto grid = new Grid();
        grid.setColumnSpacing(12);
        grid.setRowSpacing(6);
        grid.setMarginTop(12);
        grid.setMarginBottom(12);
        grid.setMarginStart(12);
        grid.setMarginEnd(12);

        int row = 0;
        void addRow(string label, ref Entry entry, string value, string placeholder) {
            auto lbl = new Label(label);
            lbl.setHalign(GtkAlign.END);
            entry = new Entry();
            entry.setText(value);
            entry.setWidthChars(48);
            entry.setPlaceholderText(placeholder);
            entry.setHexpand(true);
            grid.attach(lbl, 0, row, 1, 1);
            grid.attach(entry, 1, row, 1, 1);
            row++;
        }

        addRow(_("Name"), eName, initial.name, "Grok");
        addRow(_("Start command"), eCmd, initial.command, "grok");
        addRow(_("Resume command"), eResume, initial.resumeCommand, "grok --resume {id}");
        addRow(_("List command"), eList, initial.listCommand, "grok sessions list -n 30");

        getContentArea().add(grid);
    }

    @property AITool result() {
        AITool t;
        t.name = eName.getText().strip();
        t.command = eCmd.getText().strip();
        t.resumeCommand = eResume.getText().strip();
        t.listCommand = eList.getText().strip();
        return t;
    }
}
