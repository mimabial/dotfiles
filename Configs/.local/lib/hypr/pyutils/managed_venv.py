import importlib
import os
import sys
from pathlib import Path

from pyutils.xdg_base_dirs import xdg_state_home


def managed_environment_dir() -> Path:
    return xdg_state_home() / "hypr/pip_env"


def use_managed_site_packages() -> None:
    site_packages_path = str(managed_environment_dir() / "lib" /
                            f"python{sys.version_info.major}.{sys.version_info.minor}/site-packages")
    # Managed Hypr dependencies should not be mixed with foreign site-packages.
    # Keep stdlib paths, but drop other package roots once the managed venv is in use.
    sys.path[:] = [site_packages_path, *(
        path for path in sys.path if path != site_packages_path
        and "site-packages" not in path and "dist-packages" not in path
    )]


def managed_python_executable() -> Path | None:
    python_executable = managed_environment_dir() / "bin/python"
    if python_executable.is_file() and os.access(python_executable, os.X_OK):
        return python_executable
    return None


def reexec_in_managed_environment(argv=None):
    managed_python = managed_python_executable()
    if managed_python is None or Path(sys.prefix).resolve() == managed_environment_dir().resolve():
        return False
    os.execv(str(managed_python), [str(managed_python), *(sys.argv if argv is None else argv)])


def import_managed_dependency(module_name):
    """Never installs; a missing module raises ImportError."""
    use_managed_site_packages()
    try:
        return importlib.import_module(module_name)
    except ImportError as error:
        raise ImportError(
            f"Missing optional Python dependency '{module_name}'. "
            f"Install it explicitly with `hyprshell pip install {module_name}` "
            "or provision the managed Hypr venv first."
        ) from error
