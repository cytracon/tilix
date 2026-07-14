# -*- coding: UTF-8 -*-
# This example is contributed by Martin Enlund
# Example modified for Tilix
# Shortcuts Provider was inspired by captain nemo extension
# Cytracon: hardened remote URI handling (no shell=True, quote all fields)

from gettext import gettext, textdomain
from subprocess import Popen
import re
import shutil
import shlex
try:
    from urllib import unquote
    from urlparse import urlparse
except ImportError:
    from urllib.parse import unquote, urlparse


from gi.repository import Gio, GObject, Nautilus
from gi import require_version
if hasattr(Nautilus, "LocationWidgetProvider"):
    require_version('Gtk', '3.0')
    from gi.repository import Gtk


TERMINAL = shutil.which("tilix")
TILIX_KEYBINDINGS = "com.gexperts.Tilix.Keybindings"
GSETTINGS_OPEN_TERMINAL = "nautilus-open"
REMOTE_URI_SCHEME = ['ftp', 'sftp']
# Conservative host/user validation to reject metacharacters
_SAFE_HOST = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
_SAFE_USER = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')
textdomain("tilix")
_ = gettext

def _checkdecode(s):
    """Decode string assuming utf encoding if it's bytes, else return unmodified"""
    return s.decode('utf-8') if isinstance(s, bytes) else s

def open_terminal_in_file(filename):
    if not TERMINAL:
        return
    if filename:
        Popen([TERMINAL, '-w', filename])
    else:
        Popen([TERMINAL])

def _build_ssh_command(result, remote_cd=None):
    """Build a shellParseArgv-safe -e argument for ssh without shell=True."""
    if not result.hostname or not _SAFE_HOST.match(result.hostname):
        raise ValueError("unsafe hostname")
    if result.username and not _SAFE_USER.match(result.username):
        raise ValueError("unsafe username")

    argv = ['ssh', '-t']
    if result.port:
        argv.extend(['-p', str(int(result.port))])
    if result.username:
        argv.append('%s@%s' % (result.username, result.hostname))
    else:
        argv.append(result.hostname)
    if remote_cd:
        # Single remote argument executed by ssh
        argv.append('cd %s ; exec "$SHELL"' % shlex.quote(remote_cd))
    # Join so Tilix shellParseArgv reconstructs argv correctly
    return ' '.join(shlex.quote(a) for a in argv)

# Nautilus 43 doesn't offer the LocationWidgetProvider any more
if hasattr(Nautilus, "LocationWidgetProvider"):
    class OpenTilixShortcutProvider(GObject.GObject,
                                    Nautilus.LocationWidgetProvider):

        def __init__(self):
            source = Gio.SettingsSchemaSource.get_default()
            if source.lookup(TILIX_KEYBINDINGS, True):
                self._gsettings = Gio.Settings.new(TILIX_KEYBINDINGS)
                self._gsettings.connect("changed", self._bind_shortcut)
                self._create_accel_group()
            self._window = None
            self._uri = None

        def _create_accel_group(self):
            self._accel_group = Gtk.AccelGroup()
            shortcut = self._gsettings.get_string(GSETTINGS_OPEN_TERMINAL)
            key, mod = Gtk.accelerator_parse(shortcut)
            self._accel_group.connect(key, mod, Gtk.AccelFlags.VISIBLE,
                                      self._open_terminal)

        def _bind_shortcut(self, gsettings, key):
            if key == GSETTINGS_OPEN_TERMINAL:
                self._accel_group.disconnect(self._open_terminal)
                self._create_accel_group()

        def _open_terminal(self, *args):
            filename = unquote(self._uri[7:])
            open_terminal_in_file(filename)

        def get_widget(self, uri, window):
            self._uri = uri
            if self._window:
                self._window.remove_accel_group(self._accel_group)
            if self._gsettings:
                window.add_accel_group(self._accel_group)
            self._window = window
            return None


class OpenTilixExtension(GObject.GObject, Nautilus.MenuProvider):

    def _open_terminal(self, file_):
        if not TERMINAL:
            return
        if file_.get_uri_scheme() in REMOTE_URI_SCHEME:
            result = urlparse(file_.get_uri())
            try:
                remote_cd = result.path if file_.is_directory() else None
                value = _build_ssh_command(result, remote_cd)
            except (ValueError, TypeError):
                return
            Popen([TERMINAL, '-e', value])
        else:
            filename = Gio.File.new_for_uri(file_.get_uri()).get_path()
            open_terminal_in_file(filename)

    def _menu_activate_cb(self, menu, file_):
        self._open_terminal(file_)

    def _menu_background_activate_cb(self, menu, file_):
        self._open_terminal(file_)

    def get_file_items(self, *args):
        files = args[-1]
        if len(files) != 1:
            return
        items = []
        file_ = files[0]

        if file_.is_directory():

            if file_.get_uri_scheme() in REMOTE_URI_SCHEME:
                uri = _checkdecode(file_.get_uri())
                item = Nautilus.MenuItem(name='NautilusPython::open_remote_item',
                                         label=_(u'Open Remote Tilix'),
                                         tip=_(u'Open Remote Tilix In {}').format(uri))
                item.connect('activate', self._menu_activate_cb, file_)
                items.append(item)

            filename = _checkdecode(file_.get_name())
            item = Nautilus.MenuItem(name='NautilusPython::open_file_item',
                                     label=_(u'Open In Tilix'),
                                     tip=_(u'Open Tilix In {}').format(filename))
            item.connect('activate', self._menu_activate_cb, file_)
            items.append(item)

        return items

    def get_background_items(self, *args):
        file_ = args[-1]
        items = []
        if file_.get_uri_scheme() in REMOTE_URI_SCHEME:
            item = Nautilus.MenuItem(name='NautilusPython::open_bg_remote_item',
                                     label=_(u'Open Remote Tilix Here'),
                                     tip=_(u'Open Remote Tilix In This Directory'))
            item.connect('activate', self._menu_activate_cb, file_)
            items.append(item)

        item = Nautilus.MenuItem(name='NautilusPython::open_bg_file_item',
                                 label=_(u'Open Tilix Here'),
                                 tip=_(u'Open Tilix In This Directory'))
        item.connect('activate', self._menu_background_activate_cb, file_)
        items.append(item)
        return items
