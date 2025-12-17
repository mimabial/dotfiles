#!/usr/bin/env bash
# pywal16.gtk.sh - Create Pywal16-Gtk theme with dynamic border-radius

themesDir="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

# Get Hyprland border radius
if command -v hyprctl &>/dev/null && command -v jq &>/dev/null; then
    hypr_border=$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r '.int // 8')
else
    hypr_border=8  # Default fallback
fi

# Create theme directory structure
mkdir -p "$themesDir/Pywal16-Gtk/gtk-3.0"
mkdir -p "$themesDir/Pywal16-Gtk/gtk-4.0"

# GTK 3.0
if [ -f "$cacheDir/colors-gtk3.css" ]; then
    {
        echo "/* Hyprland border radius: ${hypr_border}px */"
        echo ""
        cat "$cacheDir/colors-gtk3.css"
    } | sed "
        s/border-radius: 12px 12px 12px 12px;/border-radius: $((hypr_border * 2))px $((hypr_border * 2))px $((hypr_border * 2))px $((hypr_border * 2))px;/g
        s/border-radius: 12px 12px 0 0;/border-radius: $((hypr_border * 2))px $((hypr_border * 2))px 0 0;/g
        s/border-radius: 0 0 12px 12px;/border-radius: 0 0 $((hypr_border * 2))px $((hypr_border * 2))px;/g
        s/border-radius: 0 12px 12px 0;/border-radius: 0 $((hypr_border * 2))px $((hypr_border * 2))px 0;/g
        s/border-radius: 0 0 12px 0;/border-radius: 0 0 $((hypr_border * 2))px 0;/g
        s/border-radius: 0 0 0 12px;/border-radius: 0 0 0 $((hypr_border * 2))px;/g
        s/border-radius: 6px 6px 6px 6px;/border-radius: ${hypr_border}px ${hypr_border}px ${hypr_border}px ${hypr_border}px;/g
        s/border-radius: 6px 6px 0 0;/border-radius: ${hypr_border}px ${hypr_border}px 0 0;/g
        s/border-radius: 6px 0 0 6px;/border-radius: ${hypr_border}px 0 0 ${hypr_border}px;/g
        s/border-radius: 0 6px 6px 0;/border-radius: 0 ${hypr_border}px ${hypr_border}px 0;/g
        s/border-radius: 0 0 6px 6px;/border-radius: 0 0 ${hypr_border}px ${hypr_border}px;/g
        s/border-radius: 0 0 6px 0;/border-radius: 0 0 ${hypr_border}px 0;/g
        s/border-radius: 0 0 0 6px;/border-radius: 0 0 0 ${hypr_border}px;/g
        s/\([a-z-]*radius:\) 14px;/\1 $((hypr_border * 7 / 3))px;/g
        s/\([a-z-]*radius:\) 12px;/\1 $((hypr_border * 2))px;/g
        s/\([a-z-]*radius:\) 10px;/\1 $((hypr_border * 5 / 3))px;/g
        s/\([a-z-]*radius:\) 9px;/\1 $((hypr_border + hypr_border / 2))px;/g
        s/\([a-z-]*radius:\) 8px;/\1 $((hypr_border * 4 / 3))px;/g
        s/\([a-z-]*radius:\) 7px;/\1 $((hypr_border * 7 / 6))px;/g
        s/\([a-z-]*radius:\) 6px;/\1 ${hypr_border}px;/g
        s/\([a-z-]*radius:\) 5px;/\1 $((hypr_border * 5 / 6))px;/g
        s/\([a-z-]*radius:\) 4px;/\1 $((hypr_border * 2 / 3))px;/g
        s/\([a-z-]*radius:\) 3px;/\1 $((hypr_border / 2))px;/g
        s/\([a-z-]*radius:\) 2px;/\1 $((hypr_border / 3))px;/g
        s/\([a-z-]*radius:\) 1px;/\1 $((hypr_border / 6))px;/g
    " > "$themesDir/Pywal16-Gtk/gtk-3.0/gtk.css"

    # Create gtk-dark.css symlink (cd to directory for relative symlink)
    cd "$themesDir/Pywal16-Gtk/gtk-3.0" && ln -sf gtk.css gtk-dark.css
fi

# GTK 4.0
if [ -f "$cacheDir/colors-gtk4.css" ]; then
    {
        echo "/* Hyprland border radius: ${hypr_border}px */"
        echo ""
        cat "$cacheDir/colors-gtk4.css"
    } | sed "
        s/border-radius: 12px 12px 12px 12px;/border-radius: $((hypr_border * 2))px $((hypr_border * 2))px $((hypr_border * 2))px $((hypr_border * 2))px;/g
        s/border-radius: 12px 12px 0 0;/border-radius: $((hypr_border * 2))px $((hypr_border * 2))px 0 0;/g
        s/border-radius: 0 0 12px 12px;/border-radius: 0 0 $((hypr_border * 2))px $((hypr_border * 2))px;/g
        s/border-radius: 0 12px 12px 0;/border-radius: 0 $((hypr_border * 2))px $((hypr_border * 2))px 0;/g
        s/border-radius: 0 0 12px 0;/border-radius: 0 0 $((hypr_border * 2))px 0;/g
        s/border-radius: 0 0 0 12px;/border-radius: 0 0 0 $((hypr_border * 2))px;/g
        s/border-radius: 6px 6px 6px 6px;/border-radius: ${hypr_border}px ${hypr_border}px ${hypr_border}px ${hypr_border}px;/g
        s/border-radius: 6px 6px 0 0;/border-radius: ${hypr_border}px ${hypr_border}px 0 0;/g
        s/border-radius: 6px 0 0 6px;/border-radius: ${hypr_border}px 0 0 ${hypr_border}px;/g
        s/border-radius: 0 6px 6px 0;/border-radius: 0 ${hypr_border}px ${hypr_border}px 0;/g
        s/border-radius: 0 0 6px 6px;/border-radius: 0 0 ${hypr_border}px ${hypr_border}px;/g
        s/border-radius: 0 0 6px 0;/border-radius: 0 0 ${hypr_border}px 0;/g
        s/border-radius: 0 0 0 6px;/border-radius: 0 0 0 ${hypr_border}px;/g
        s/\([a-z-]*radius:\) 14px;/\1 $((hypr_border * 7 / 3))px;/g
        s/\([a-z-]*radius:\) 12px;/\1 $((hypr_border * 2))px;/g
        s/\([a-z-]*radius:\) 10px;/\1 $((hypr_border * 5 / 3))px;/g
        s/\([a-z-]*radius:\) 9px;/\1 $((hypr_border + hypr_border / 2))px;/g
        s/\([a-z-]*radius:\) 8px;/\1 $((hypr_border * 4 / 3))px;/g
        s/\([a-z-]*radius:\) 7px;/\1 $((hypr_border * 7 / 6))px;/g
        s/\([a-z-]*radius:\) 6px;/\1 ${hypr_border}px;/g
        s/\([a-z-]*radius:\) 5px;/\1 $((hypr_border * 5 / 6))px;/g
        s/\([a-z-]*radius:\) 4px;/\1 $((hypr_border * 2 / 3))px;/g
        s/\([a-z-]*radius:\) 3px;/\1 $((hypr_border / 2))px;/g
        s/\([a-z-]*radius:\) 2px;/\1 $((hypr_border / 3))px;/g
        s/\([a-z-]*radius:\) 1px;/\1 $((hypr_border / 6))px;/g
    " > "$themesDir/Pywal16-Gtk/gtk-4.0/gtk.css"

    # Create gtk-dark.css symlink (cd to directory for relative symlink)
    cd "$themesDir/Pywal16-Gtk/gtk-4.0" && ln -sf gtk.css gtk-dark.css
fi

# GTK 2.0
if [ -f "$cacheDir/colors-gtk2.rc" ]; then
    mkdir -p "$themesDir/Pywal16-Gtk/gtk-2.0"
    cp "$cacheDir/colors-gtk2.rc" "$themesDir/Pywal16-Gtk/gtk-2.0/gtkrc"
fi

# Create index.theme if it doesn't exist
if [ ! -f "$themesDir/Pywal16-Gtk/index.theme" ]; then
    cat > "$themesDir/Pywal16-Gtk/index.theme" <<EOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Pywal16-Gtk
Comment=Dynamic GTK theme generated from pywal16 colors
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Pywal16-Gtk
MetacityTheme=Pywal16-Gtk
IconTheme=Adwaita
CursorTheme=Adwaita
ButtonLayout=close,minimize,maximize:menu
EOF
fi

# Notify GTK apps of theme changes
# Method 1: Use xsettingsd to broadcast theme changes (if available)
if command -v xsettingsd &>/dev/null && pgrep -x xsettingsd >/dev/null; then
    xsettingsd_conf="${XDG_CONFIG_HOME:-$HOME/.config}/xsettingsd/xsettingsd.conf"
    if [ -f "$xsettingsd_conf" ]; then
        # Toggle theme name to force apps to notice the change
        sed -i 's/^Net\/ThemeName "Pywal16-Gtk"$/Net\/ThemeName "Adwaita"/' "$xsettingsd_conf"
        pkill -HUP xsettingsd 2>/dev/null
        # Change back to Pywal16-Gtk
        sed -i 's/^Net\/ThemeName "Adwaita"$/Net\/ThemeName "Pywal16-Gtk"/' "$xsettingsd_conf"
        pkill -HUP xsettingsd 2>/dev/null
    else
        # Fallback if config doesn't exist
        pkill -HUP xsettingsd 2>/dev/null
    fi
fi

# Method 2: Update GTK settings.ini files (triggers inotify watches)
for gtk_config in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
    if [ -f "$gtk_config" ]; then
        # Toggle to Adwaita first
        sed -i 's/^gtk-theme-name=.*/gtk-theme-name=Adwaita/' "$gtk_config"
    fi
done

# Brief moment for apps to register the change
sleep 0.1

for gtk_config in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
    if [ -f "$gtk_config" ]; then
        # Change back to Pywal16-Gtk
        sed -i 's/^gtk-theme-name=.*/gtk-theme-name=Pywal16-Gtk/' "$gtk_config"
    fi
done
