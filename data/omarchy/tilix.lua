-- Cytracon Tilix on Omarchy / Hyprland.
-- Loaded from ~/.config/hypr/hyprland.lua via require("hypr.tilix")

-- Treat Tilix as a real terminal (tiled), not a 875x600 floating dialog.
-- Omarchy's floating-window tag is for TUIs/dialogs; a daily driver terminal
-- must tile like foot/kitty.
o.window("com\\.gexperts\\.Tilix", { tag = "+terminal" })
o.window("com\\.gexperts\\.Tilix", { scroll_touchpad = 1.5 })
