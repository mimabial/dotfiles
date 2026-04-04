# GPU detection for UWSM env.

gpu_lines=
if command -v lspci >/dev/null 2>&1; then
  gpu_lines="$(lspci -nn 2>/dev/null | grep -E '(VGA|3D)' || true)"
fi

NVIDIA=0
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 || lsmod | grep -q 'nvidia'; then
  NVIDIA=1
fi

AMD=0
case "${gpu_lines}" in
  *1002*) AMD=1 ;;
esac

INTEL=0
case "${gpu_lines}" in
  *8086*) INTEL=1 ;;
esac

NOUVEAU=0
lsmod | grep -q 'nouveau' && NOUVEAU=1

NVIDIA_VAAPI=0
if [ -f "/usr/lib/dri/nvidia_drv_video.so" ] || [ -f "/usr/lib64/dri/nvidia_drv_video.so" ]; then
  NVIDIA_VAAPI=1
fi

key="${AMD}${INTEL}${NOUVEAU}${NVIDIA}"

case "$key" in
0101)
  GPU_SETUP="hybrid-intel-nvidia"
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export VK_LAYER_NV_optimus=1
  # Let VA-API auto-detect between Intel iHD/i965
  # GBM_BACKEND=nvidia-drm removed - optional and can cause Firefox crashes
  if [ "$NVIDIA_VAAPI" = "1" ]; then
    export NVD_BACKEND=direct # Requires 'libva-nvidia-driver' package
    # Let applications auto-detect VA-API driver (nvidia vs iHD)
  fi
  ;;

1100)
  GPU_SETUP="hybrid-amd-intel"
  # AMD usually has better driver support, so only set if needed
  # export LIBVA_DRIVER_NAME=radeonsi
  # export VDPAU_DRIVER=radeonsi
  ;;

0110)
  GPU_SETUP="hybrid-intel-nouveau"
  # Let system auto-detect best drivers - don't force specific drivers
  ;;

0001)
  GPU_SETUP="nvidia-only"
  # NVIDIA requires these for proper Wayland/Hyprland support
  export LIBVA_DRIVER_NAME=nvidia
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __GL_VRR_ALLOWED=1
  if [ "$NVIDIA_VAAPI" = "1" ]; then
    export NVD_BACKEND=direct # Requires 'libva-nvidia-driver' package
  fi
  ;;

1000)
  GPU_SETUP="amd-only"
  # AMD drivers usually auto-detect correctly
  # export LIBVA_DRIVER_NAME=radeonsi
  # export VDPAU_DRIVER=radeonsi
  ;;

0010)
  GPU_SETUP="nouveau-only"
  # Let system auto-detect best Nouveau drivers
  ;;

0100)
  GPU_SETUP="intel-only"
  # Let system auto-detect Intel VA-API driver (iHD vs i965)
  ;;

*)
  GPU_SETUP="unknown or we don't need to do anything"
  ;;
esac

export GPU_SETUP
echo "GPU setup detected: $GPU_SETUP"
