/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.constants;

import std.path;

import gx.i18n.l10n;

/****************************************************************
 * Compilation Flags, these are used to test various things or
 * to turn off work that is in process
 ****************************************************************/

/**
 * Whether to use a pixbuf for drag and Drop image
 */
immutable bool USE_PIXBUF_DND = false;

/**
 * Renders clipboard options as buttons in context menu
 */
immutable bool CLIPBOARD_BTN_IN_CONTEXT = false;

/**
 * All logs go to the file /tmp/tilix.log, useful
 * when debugging launchers or other spots where
 * stdout isn't easily viewed.
 */
immutable bool USE_FILE_LOGGING = false;

/**
 * Determines whether synchronization of multiple terminals
 * is driven off of the commit event or by keystrokes. The commit
 * event allows for IME to work but causes some issues with
 * certain programs like VIM. See #888
 */
immutable bool USE_COMMIT_SYNCHRONIZATION = false;

/**
 * Compile tilix with support for VTE method vte_terminal_get_color_background_for_draw,
 * only needed until VTE 0.54 is released and GtkD is updated.
 */
immutable bool COMPILE_VTE_BACKGROUND_COLOR = false;

/**************************************
 * Application Constants
 **************************************/

// GTK Version required
enum GTK_VERSION_MAJOR = 3;
enum GTK_VERSION_MINOR = 18;
enum GTK_VERSION_PATCH = 0;

// GTK version required for scrolledwindow
enum GTK_SCROLLEDWINDOW_VERSION = 22;

// GetText Domain
enum TILIX_DOMAIN = "tilix";

/**
 * Application ID
 */
enum APPLICATION_ID = "com.gexperts.Tilix";

// Application values used in About Dialog
enum APPLICATION_NAME = "Tilix";
enum APPLICATION_VERSION = "1.9.8-cytracon.11";
enum APPLICATION_AUTHOR = "Gerald Nunn";
enum APPLICATION_COPYRIGHT = "Copyright \xc2\xa9 2020 " ~ APPLICATION_AUTHOR ~ " / Cytracon fork";
enum APPLICATION_COMMENTS = N_("A VTE based terminal emulator for Linux (Cytracon fork)");
enum APPLICATION_LICENSE = N_("This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.");
enum APPLICATION_ICON_NAME = "com.gexperts.Tilix";
