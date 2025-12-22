#!/usr/bin/env bash
# pywal16.gtk.sh - Create Pywal16-Gtk theme with dynamic border-radius
# Optimized: single awk pass + change detection

themesDir="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
hashFile="${XDG_RUNTIME_DIR:-/tmp}/wal-gtk-hash"

# Get Hyprland border radius
if command -v hyprctl &>/dev/null && command -v jq &>/dev/null; then
    hypr_border=$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r '.int // 8')
else
    hypr_border=8  # Default fallback
fi

# Change detection: skip if inputs unchanged
input_hash=$(cat "$cacheDir/colors-gtk3.css" "$cacheDir/colors-gtk4.css" 2>/dev/null | md5sum | cut -d' ' -f1)
combined_hash="${input_hash}-${hypr_border}"
if [[ -f "$hashFile" && "$(cat "$hashFile" 2>/dev/null)" == "$combined_hash" ]]; then
    exit 0  # Nothing changed
fi

# Create theme directory structure
mkdir -p "$themesDir/Pywal16-Gtk/gtk-3.0" "$themesDir/Pywal16-Gtk/gtk-4.0"

# Awk script for border-radius scaling (single pass, all patterns)
scale_radius() {
    local input_file="$1"
    local output_file="$2"

    awk -v r="$hypr_border" '
    BEGIN {
        # Pre-compute all scaled values
        r2 = int(r * 2)
        r7_3 = int(r * 7 / 3)
        r5_3 = int(r * 5 / 3)
        r3_2 = int(r + r / 2)
        r4_3 = int(r * 4 / 3)
        r7_6 = int(r * 7 / 6)
        r5_6 = int(r * 5 / 6)
        r2_3 = int(r * 2 / 3)
        r1_2 = int(r / 2)
        r1_3 = int(r / 3)
        r1_6 = int(r / 6)
    }
    {
        # Multi-value patterns (must come first to avoid partial matches)
        gsub(/border-radius: 12px 12px 12px 12px;/, "border-radius: " r2 "px " r2 "px " r2 "px " r2 "px;")
        gsub(/border-radius: 12px 12px 0 0;/, "border-radius: " r2 "px " r2 "px 0 0;")
        gsub(/border-radius: 0 0 12px 12px;/, "border-radius: 0 0 " r2 "px " r2 "px;")
        gsub(/border-radius: 0 12px 12px 0;/, "border-radius: 0 " r2 "px " r2 "px 0;")
        gsub(/border-radius: 0 0 12px 0;/, "border-radius: 0 0 " r2 "px 0;")
        gsub(/border-radius: 0 0 0 12px;/, "border-radius: 0 0 0 " r2 "px;")
        gsub(/border-radius: 6px 6px 6px 6px;/, "border-radius: " r "px " r "px " r "px " r "px;")
        gsub(/border-radius: 6px 6px 0 0;/, "border-radius: " r "px " r "px 0 0;")
        gsub(/border-radius: 6px 0 0 6px;/, "border-radius: " r "px 0 0 " r "px;")
        gsub(/border-radius: 0 6px 6px 0;/, "border-radius: 0 " r "px " r "px 0;")
        gsub(/border-radius: 0 0 6px 6px;/, "border-radius: 0 0 " r "px " r "px;")
        gsub(/border-radius: 0 0 6px 0;/, "border-radius: 0 0 " r "px 0;")
        gsub(/border-radius: 0 0 0 6px;/, "border-radius: 0 0 0 " r "px;")

        # Single-value patterns (order matters: larger values first)
        gsub(/([a-z-]*radius:) 14px;/, "\\1 " r7_3 "px;")
        gsub(/([a-z-]*radius:) 12px;/, "\\1 " r2 "px;")
        gsub(/([a-z-]*radius:) 10px;/, "\\1 " r5_3 "px;")
        gsub(/([a-z-]*radius:) 9px;/, "\\1 " r3_2 "px;")
        gsub(/([a-z-]*radius:) 8px;/, "\\1 " r4_3 "px;")
        gsub(/([a-z-]*radius:) 7px;/, "\\1 " r7_6 "px;")
        gsub(/([a-z-]*radius:) 6px;/, "\\1 " r "px;")
        gsub(/([a-z-]*radius:) 5px;/, "\\1 " r5_6 "px;")
        gsub(/([a-z-]*radius:) 4px;/, "\\1 " r2_3 "px;")
        gsub(/([a-z-]*radius:) 3px;/, "\\1 " r1_2 "px;")
        gsub(/([a-z-]*radius:) 2px;/, "\\1 " r1_3 "px;")
        gsub(/([a-z-]*radius:) 1px;/, "\\1 " r1_6 "px;")

        print
    }
    ' "$input_file" > "$output_file"
}

# GTK 3.0
if [ -f "$cacheDir/colors-gtk3.css" ]; then
    {
        echo "/* Hyprland border radius: ${hypr_border}px */"
        echo ""
        cat "$cacheDir/colors-gtk3.css"
    } > "$themesDir/Pywal16-Gtk/gtk-3.0/gtk.css.tmp"

    scale_radius "$themesDir/Pywal16-Gtk/gtk-3.0/gtk.css.tmp" "$themesDir/Pywal16-Gtk/gtk-3.0/gtk.css"
    rm -f "$themesDir/Pywal16-Gtk/gtk-3.0/gtk.css.tmp"

    # Create gtk-dark.css symlink
    ln -sf gtk.css "$themesDir/Pywal16-Gtk/gtk-3.0/gtk-dark.css"
fi

# GTK 4.0
if [ -f "$cacheDir/colors-gtk4.css" ]; then
    {
        echo "/* Hyprland border radius: ${hypr_border}px */"
        echo ""
        cat "$cacheDir/colors-gtk4.css"
    } > "$themesDir/Pywal16-Gtk/gtk-4.0/gtk.css.tmp"

    scale_radius "$themesDir/Pywal16-Gtk/gtk-4.0/gtk.css.tmp" "$themesDir/Pywal16-Gtk/gtk-4.0/gtk.css"
    rm -f "$themesDir/Pywal16-Gtk/gtk-4.0/gtk.css.tmp"

    # Create gtk-dark.css symlink
    ln -sf gtk.css "$themesDir/Pywal16-Gtk/gtk-4.0/gtk-dark.css"
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

# Save hash for next run (before notifying apps)
echo "$combined_hash" > "$hashFile"

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
        pkill -HUP xsettingsd 2>/dev/null
    fi
fi

# Method 2: Update GTK settings.ini files (triggers inotify watches)
for gtk_config in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
    if [ -f "$gtk_config" ]; then
        sed -i 's/^gtk-theme-name=.*/gtk-theme-name=Adwaita/' "$gtk_config"
    fi
done

sleep 0.05  # Reduced from 0.1

for gtk_config in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
    if [ -f "$gtk_config" ]; then
        sed -i 's/^gtk-theme-name=.*/gtk-theme-name=Pywal16-Gtk/' "$gtk_config"
    fi
done
