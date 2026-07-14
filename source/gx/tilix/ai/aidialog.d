/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.ai.aidialog;

import std.algorithm;
import std.conv;
import std.experimental.logger;
import std.format;
import std.string;

import gobject.Type;
import gobject.Value;

import gtk.Box;
import gtk.Button;
import gtk.CellRendererText;
import gtk.Dialog;
import gtk.Label;
import gtk.ListStore;
import gtk.ScrolledWindow;
import gtk.TreeIter;
import gtk.TreePath;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.Window;

import gtkc.gtktypes : GtkAlign;

import gx.i18n.l10n;

import gx.tilix.ai.tools;

/**
 * Dialog to pick an AI session to resume for a given tool.
 */
class AIResumeDialog : Dialog {
private:
    AITool tool;
    TreeView tv;
    ListStore ls;
    AISessionEntry[] sessions;
    string _selectedId;
    string _selectedSummary;

    enum COL_SUMMARY = 0;
    enum COL_UPDATED = 1;
    enum COL_STATUS = 2;
    enum COL_ID = 3;

    void createUI() {
        auto box = new Box(Orientation.VERTICAL, 6);
        box.setMarginTop(12);
        box.setMarginBottom(12);
        box.setMarginStart(12);
        box.setMarginEnd(12);

        auto lbl = new Label(format(_("Sessions for %s — select one to resume"), tool.name));
        lbl.setHalign(GtkAlign.START);
        box.add(lbl);

        ls = new ListStore([GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
        tv = new TreeView(ls);
        tv.setHeadersVisible(true);
        tv.appendColumn(new TreeViewColumn(_("Summary"), new CellRendererText(), "text", COL_SUMMARY));
        tv.appendColumn(new TreeViewColumn(_("Updated"), new CellRendererText(), "text", COL_UPDATED));
        tv.appendColumn(new TreeViewColumn(_("Status"), new CellRendererText(), "text", COL_STATUS));
        auto colId = new TreeViewColumn(_("ID"), new CellRendererText(), "text", COL_ID);
        colId.setVisible(false);
        tv.appendColumn(colId);

        tv.addOnRowActivated(delegate(TreePath, TreeViewColumn, TreeView) {
            response(ResponseType.OK);
        });

        auto sw = new ScrolledWindow(tv);
        sw.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        sw.setSizeRequest(560, 320);
        sw.setShadowType(ShadowType.ETCHED_IN);
        box.add(sw);

        auto btnRefresh = new Button(_("Refresh"));
        btnRefresh.addOnClicked(delegate(Button) { reload(); });
        box.add(btnRefresh);

        getContentArea().add(box);
        reload();
    }

    void reload() {
        ls.clear();
        sessions = listSessionsForTool(tool, 40);
        foreach (s; sessions) {
            auto iter = ls.createIter();
            ls.setValue(iter, COL_SUMMARY, s.summary.length ? s.summary : s.id);
            ls.setValue(iter, COL_UPDATED, s.updated);
            ls.setValue(iter, COL_STATUS, s.status);
            ls.setValue(iter, COL_ID, s.id);
        }
        if (sessions.length == 0) {
            auto iter = ls.createIter();
            ls.setValue(iter, COL_SUMMARY, _("No sessions found (check list command / network)"));
            ls.setValue(iter, COL_UPDATED, "");
            ls.setValue(iter, COL_STATUS, "");
            ls.setValue(iter, COL_ID, "");
        }
    }

public:
    this(Window parent, AITool tool) {
        super(format(_("Resume %s"), tool.name), parent, GtkDialogFlags.MODAL + GtkDialogFlags.USE_HEADER_BAR,
            [_("Resume"), _("Cancel")], [ResponseType.OK, ResponseType.CANCEL]);
        this.tool = tool;
        setDefaultResponse(ResponseType.OK);
        createUI();
    }

    @property string selectedId() {
        auto sel = tv.getSelectedIter();
        if (sel is null) return null;
        return ls.getValueString(sel, COL_ID);
    }

    @property string selectedSummary() {
        auto sel = tv.getSelectedIter();
        if (sel is null) return null;
        return ls.getValueString(sel, COL_SUMMARY);
    }
}
