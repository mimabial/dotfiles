# Qt uses Wayland with X11 fallback. qt6ct provides the generic Qt6 palette
# bridge, while Kvantum provides the widget style.
QT_QPA_PLATFORMTHEME=qt6ct
QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"
QT_STYLE_OVERRIDE="${QT_STYLE_OVERRIDE:-kvantum}"

MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
GDK_SCALE="${GDK_SCALE:-1}"
ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"

# Let Hyprland select hyprland.lua; discard stale values inherited from shells.
unset HYPRLAND_CONFIG
# UWSM owns readiness and the activation environment.
HYPRLAND_NO_SD_NOTIFY=1
HYPRLAND_NO_SD_VARS=1

export ELECTRON_OZONE_PLATFORM_HINT GDK_SCALE MOZ_ENABLE_WAYLAND \
  QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
  HYPRLAND_NO_SD_NOTIFY HYPRLAND_NO_SD_VARS
