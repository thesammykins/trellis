"""Finder layout for the personal Trellis disk image."""

import os


_root = os.getcwd()
_background = os.path.join(_root, "assets", "dmg", "background.png")

format = "UDZO"
volume_name = "Trellis"
files = [os.path.join(_root, "dist", "Trellis.app")]
symlinks = {"Applications": "/Applications"}

window_rect = ((100, 100), (720, 440))
background = _background
icon_size = 112
text_size = 14
icon_locations = {
    "Trellis.app": (180, 210),
    "Applications": (540, 210),
}

default_view = "icon-view"
show_icon_preview = False
show_item_info = False
show_toolbar = False
show_status_bar = False
show_sidebar = False
sidebar_width = 0
include_icon_view_settings = "auto"
include_list_view_settings = "auto"
show_pathbar = False
show_tab_view = False
