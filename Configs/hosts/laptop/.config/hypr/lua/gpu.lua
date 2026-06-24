hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("__VK_LAYER_NV_optimus", "NVIDIA_only")
hl.env("GBM_BACKEND", "nvidia-drm")

hl.config({cursor = {no_hardware_cursors = true}})
