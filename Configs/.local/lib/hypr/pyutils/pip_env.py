import argparse
import importlib
import json
import os
import shutil
import subprocess
import sys

lib_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, lib_dir)


import wrapper.libnotify as notify  # noqa: E402
import xdg_base_dirs  # noqa: E402


def is_venv_valid(venv_path):
    python_exe = os.path.join(venv_path, "bin", "python")
    pyvenv_cfg = os.path.join(venv_path, "pyvenv.cfg")

    if not (os.path.isfile(python_exe) and os.access(python_exe, os.X_OK)):
        return False

    try:
        pip_import = subprocess.run(
            [python_exe, "-c", "import pip"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
        if pip_import.returncode != 0:
            return False
    except Exception:
        return False

    if os.path.exists(pyvenv_cfg):
        try:
            with open(pyvenv_cfg, "r") as config_file:
                for line in config_file:
                    key, sep, value = line.partition("=")
                    if sep and key.strip() == "version":
                        venv_version = value.strip()
                        current_python_version = f"{sys.version_info.major}.{sys.version_info.minor}"
                        if not venv_version.startswith(current_python_version):
                            return False
        except Exception:
            return False

    return True


def hypr_venv_path():
    return os.path.join(xdg_base_dirs.xdg_state_home(), "hypr", "pip_env")


def activate_managed_venv_path():
    venv_path = hypr_venv_path()
    site_packages_path = os.path.join(
        venv_path,
        "lib",
        f"python{sys.version_info.major}.{sys.version_info.minor}",
        "site-packages",
    )
    sys.path.insert(0, site_packages_path)
    # Managed Hypr dependencies should not be mixed with foreign site-packages.
    # Keep stdlib paths, but drop other package roots once the managed venv is in use.
    sys.path[:] = [
        path
        for path in sys.path
        if path == site_packages_path
        or ("site-packages" not in path and "dist-packages" not in path)
    ]
    return venv_path


def managed_python_executable():
    venv_path = hypr_venv_path()
    python_executable = os.path.join(venv_path, "bin", "python")
    if os.path.isfile(python_executable) and os.access(python_executable, os.X_OK):
        return python_executable
    return None


def ensure_managed_interpreter(argv=None):
    """Re-execs the current script when it runs outside the managed venv."""
    managed_python = managed_python_executable()
    if managed_python is None:
        return False

    current_python = os.path.realpath(sys.executable)
    target_python = os.path.realpath(managed_python)
    if current_python == target_python:
        return False

    exec_argv = [managed_python]
    if argv is None:
        exec_argv.extend(sys.argv)
    else:
        exec_argv.extend(argv)

    os.execv(managed_python, exec_argv)


def create_venv(venv_path, requirements_file=None):
    if not os.path.exists(os.path.join(venv_path, "bin", "pip")):
        subprocess.run([sys.executable, "-m", "venv", venv_path], check=True)
        pip_executable = os.path.join(venv_path, "bin", "pip")
        if requirements_file and os.path.exists(requirements_file):
            with open(requirements_file, "r") as requirements_input:
                list_requirements = "\n".join(
                    [
                        f"📦 {line.strip()}"
                        for line in requirements_input
                        if line.strip() and not line.startswith("#")
                    ]
                )

            notify.send(
                "PIP",
                f"⏳ Installing virtual environment Dependencies:\n {list_requirements}",
            )
            result = subprocess.run(
                [pip_executable, "install", "-r", requirements_file],
                capture_output=True,
                text=True,
            )
            result.check_returncode()
        notify.send("PIP", "✅ Virtual environment created successfully")


def destroy_venv(venv_path):
    if os.path.exists(venv_path):
        shutil.rmtree(venv_path)


def install_dependencies(venv_path, requirements_file):
    if not os.path.exists(venv_path):
        create_venv(venv_path, requirements_file)
    else:
        pip_executable = os.path.join(venv_path, "bin", "pip")
        command = [pip_executable, "install", "-r", requirements_file]
        result = subprocess.run(command, capture_output=True, text=True)
        result.check_returncode()


def destroy_if_broken(venv_path):
    if os.path.exists(venv_path) and not is_venv_valid(venv_path):
        notify.send(
            "PIP",
            "⚠️ Python version changed or virtualenv is broken, rebuilding…",
        )
        destroy_venv(venv_path)


def install_package(venv_path, package):
    destroy_if_broken(venv_path)
    if not os.path.exists(venv_path):
        create_venv(venv_path)
    pip_executable = os.path.join(venv_path, "bin", "pip")
    result = subprocess.run(
        [pip_executable, "install", package],
        capture_output=True,
        text=True,
    )
    result.check_returncode()


def uninstall_package(venv_path, package):
    pip_executable = os.path.join(venv_path, "bin", "pip")
    result = subprocess.run(
        [pip_executable, "uninstall", "-y", package],
        capture_output=True,
        text=True,
    )
    result.check_returncode()


def pip_summary(result):
    for error_line in result.stderr.splitlines():
        if error_line.strip():
            return error_line.strip()
    stdout_lines = result.stdout.splitlines()
    satisfied = [line for line in stdout_lines if line.startswith("Requirement already satisfied")]
    if satisfied:
        return f"{len(satisfied)} requirements already satisfied"
    for output_line in stdout_lines:
        if output_line.startswith("Successfully installed"):
            return output_line.strip()
    return ""


def run_pip_step(pip_executable, arguments, failure):
    result = subprocess.run([pip_executable, *arguments], capture_output=True, text=True)
    if result.returncode != 0:
        notify.send("PIP", f"{failure}:\n{result.stderr or result.stdout}", urgency="critical")
        return None
    return result


def notify_summary(result):
    summary = pip_summary(result)
    if summary:
        notify.send("PIP", summary)


def outdated_packages(pip_executable):
    result = run_pip_step(pip_executable, ["list", "--outdated", "--format=json"], "Failed to list outdated packages")
    if result is None:
        return None
    try:
        outdated = json.loads(result.stdout) if result.stdout.strip() else []
        # Keep the venv's bootstrap pip paired with the system Python.
        # Self-upgrading pip while it is running can leave a partial install.
        return [pkg["name"] for pkg in outdated if pkg["name"].lower() != "pip"]
    except (json.JSONDecodeError, KeyError) as error:
        notify.send("PIP", f"Failed to parse outdated packages: {error}", urgency="critical")
        return None


def rebuild_venv(venv_path=None, requirements_file=None):
    if venv_path is None:
        venv_path = hypr_venv_path()
    destroy_if_broken(venv_path)
    pip_executable = os.path.join(venv_path, "bin", "pip")
    if not os.path.exists(pip_executable):
        create_venv(venv_path, requirements_file)

    if requirements_file and os.path.exists(requirements_file):
        result = run_pip_step(pip_executable, ["install", "--upgrade", "-r", requirements_file], "Failed to install requirements")
        if result is None:
            return
        notify_summary(result)

    packages = outdated_packages(pip_executable)
    if packages is None:
        return
    if packages:
        result = run_pip_step(pip_executable, ["install", "--upgrade", "-q", *packages], "Failed to upgrade packages")
        if result is None:
            return
        notify_summary(result)

    notify.send("PIP", "✅ Virtual environment rebuilt and packages updated.")


def v_import(module_name):
    """Never installs; a missing module raises ImportError."""
    venv_path = activate_managed_venv_path()
    sys.path.insert(0, venv_path)
    try:
        module = importlib.import_module(module_name)
        return module
    except ImportError as exc:
        raise ImportError(
            f"Missing optional Python dependency '{module_name}'. "
            f"Install it explicitly with `hyprshell pip install {module_name}` "
            "or provision the managed Hypr venv first."
        ) from exc


def build_parser():
    parser = argparse.ArgumentParser(description="Python environment manager for Hyprland")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("create", help="Create the virtual environment")
    install_parser = subparsers.add_parser("install", help="Install dependencies or a single package")
    install_parser.add_argument("packages", nargs="*", help="Packages to install")
    install_parser.add_argument("-f", "--requirements", type=str, help="The requirements file to use for installation")
    uninstall_parser = subparsers.add_parser("uninstall", help="Uninstall a single package")
    uninstall_parser.add_argument("package", help="Package to uninstall")
    subparsers.add_parser("destroy", help="Destroy the virtual environment")
    subparsers.add_parser("rebuild", help="Rebuild the virtual environment and update packages")
    return parser


def main(args):
    parser = build_parser()
    args = parser.parse_args(args)
    venv_path = activate_managed_venv_path()
    requirements_file = os.path.join(xdg_base_dirs.user_lib_dir(), "hypr", "pyutils", "requirements.txt")

    if args.command == "create":
        create_venv(venv_path, requirements_file)
    elif args.command == "install" and args.packages:
        for package in args.packages:
            install_package(venv_path, package)
    elif args.command == "install":
        install_dependencies(venv_path, args.requirements or requirements_file)
    elif args.command == "uninstall":
        uninstall_package(venv_path, args.package)
    elif args.command == "destroy":
        destroy_venv(venv_path)
    elif args.command == "rebuild":
        rebuild_venv(venv_path, requirements_file)
    else:
        parser.print_help()


if __name__ == "__main__":
    main(sys.argv[1:])

sys.path.insert(0, activate_managed_venv_path())
