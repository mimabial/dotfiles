gpu_lines=
if command -v lspci >/dev/null 2>&1; then
  gpu_lines="$(lspci -nn 2>/dev/null | grep -E '(VGA|3D)' || :)"
fi
modules="$(lsmod 2>/dev/null || :)"

AMD=0 INTEL=0 NOUVEAU=0 NVIDIA=0 NVIDIA_VAAPI=0
case "$gpu_lines" in *1002*) AMD=1 ;; esac
case "$gpu_lines" in *8086*) INTEL=1 ;; esac
case "$modules" in *nouveau*) NOUVEAU=1 ;; esac
case "$modules" in
  *nvidia*) NVIDIA=1 ;;
  *) command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 && NVIDIA=1 ;;
esac
if [ -f /usr/lib/dri/nvidia_drv_video.so ] || [ -f /usr/lib64/dri/nvidia_drv_video.so ]; then
  NVIDIA_VAAPI=1
fi

detected_gpus=
[ "$AMD" = 1 ] && detected_gpus="$detected_gpus amd"
[ "$INTEL" = 1 ] && detected_gpus="$detected_gpus intel"
[ "$NOUVEAU" = 1 ] && detected_gpus="$detected_gpus nouveau"
[ "$NVIDIA" = 1 ] && detected_gpus="$detected_gpus nvidia"
case "${detected_gpus# }" in
"intel nvidia")
  GPU_SETUP=hybrid-intel-nvidia
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export VK_LAYER_NV_optimus=1
  [ "$NVIDIA_VAAPI" = 1 ] && export NVD_BACKEND=direct
  ;;
"amd intel") GPU_SETUP=hybrid-amd-intel ;;
"intel nouveau") GPU_SETUP=hybrid-intel-nouveau ;;
nvidia)
  GPU_SETUP=nvidia-only
  export LIBVA_DRIVER_NAME=nvidia __GLX_VENDOR_LIBRARY_NAME=nvidia __GL_VRR_ALLOWED=1
  [ "$NVIDIA_VAAPI" = 1 ] && export NVD_BACKEND=direct
  ;;
amd) GPU_SETUP=amd-only ;;
nouveau) GPU_SETUP=nouveau-only ;;
intel) GPU_SETUP=intel-only ;;
*) GPU_SETUP="unknown or we don't need to do anything" ;;
esac

export GPU_SETUP
echo "GPU setup detected: $GPU_SETUP"
