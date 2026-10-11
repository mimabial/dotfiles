import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils.notifications import send_notification_async  # noqa: E402
from pyutils.managed_venv import managed_environment_dir  # noqa: E402
from pyutils import child_process  # noqa: E402

PIP_IMPORT_TIMEOUT_SECONDS = 5
REQUIREMENTS_FILE = Path(__file__).with_name("requirements.txt")
NOTIFICATION_TITLE = "PIP"
INSTALL_REQUIREMENTS_FAILED = "Failed to install requirements"


def pip_executable_in(environment_dir):
    return os.path.join(environment_dir, "bin", "pip")


def is_environment_usable(environment_dir):
    python_executable = os.path.join(environment_dir, "bin", "python")
    version_file = os.path.join(environment_dir, "pyvenv.cfg")
    if not (os.path.isfile(python_executable) and os.access(python_executable, os.X_OK)):
        return False
    try:
        pip_import = child_process.run(
            [python_executable, "-c", "import pip"], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=PIP_IMPORT_TIMEOUT_SECONDS,
        )
        if pip_import.returncode != 0:
            return False
        if os.path.exists(version_file):
            with open(version_file) as configuration:
                for line in configuration:
                    key, separator, value = line.partition("=")
                    if separator and key.strip() == "version":
                        return value.strip().split(".")[:2] == [str(sys.version_info.major), str(sys.version_info.minor)]
    except (OSError, subprocess.SubprocessError):
        return False
    return True


def run_pip_or_raise(pip_executable, arguments, failure_message):
    result = subprocess.run([pip_executable, *arguments], capture_output=True, text=True)
    if result.returncode != 0:
        send_notification_async(NOTIFICATION_TITLE, f"{failure_message}:\n{result.stderr or result.stdout}", urgency="critical")
        result.check_returncode()
    return result


def create_environment(environment_dir, requirements_file=None):
    pip_executable = pip_executable_in(environment_dir)
    if os.path.exists(pip_executable):
        return
    subprocess.run([sys.executable, "-m", "venv", environment_dir], check=True)
    if requirements_file and os.path.exists(requirements_file):
        with open(requirements_file) as requirements_input:
            requirements_summary = "\n".join(
                f"📦 {line.strip()}" for line in requirements_input
                if line.strip() and not line.startswith("#")
            )
        send_notification_async(NOTIFICATION_TITLE, f"⏳ Installing virtual environment Dependencies:\n {requirements_summary}")
        run_pip_or_raise(pip_executable, ["install", "-r", requirements_file], INSTALL_REQUIREMENTS_FAILED)
    send_notification_async(NOTIFICATION_TITLE, "✅ Virtual environment created successfully")


def remove_environment(environment_dir):
    if os.path.exists(environment_dir):
        shutil.rmtree(environment_dir)


def remove_broken_environment(environment_dir):
    if os.path.exists(environment_dir) and not is_environment_usable(environment_dir):
        send_notification_async(NOTIFICATION_TITLE, "⚠️ Python version changed or virtualenv is broken, rebuilding…")
        remove_environment(environment_dir)


def install_requirements(environment_dir, requirements_file):
    if not os.path.exists(environment_dir):
        create_environment(environment_dir, requirements_file)
    else:
        run_pip_or_raise(pip_executable_in(environment_dir), ["install", "-r", requirements_file], INSTALL_REQUIREMENTS_FAILED)


def install_package(environment_dir, package):
    remove_broken_environment(environment_dir)
    if not os.path.exists(environment_dir):
        create_environment(environment_dir)
    run_pip_or_raise(pip_executable_in(environment_dir), ["install", package], "Failed to install package")


def uninstall_package(environment_dir, package):
    run_pip_or_raise(pip_executable_in(environment_dir), ["uninstall", "-y", package], "Failed to uninstall package")


def pip_result_summary(result):
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


def notify_pip_result(result):
    if summary := pip_result_summary(result):
        send_notification_async(NOTIFICATION_TITLE, summary)


def outdated_dependency_names(pip_executable):
    result = run_pip_or_raise(pip_executable, ["list", "--outdated", "--format=json"], "Failed to list outdated packages")
    try:
        outdated = json.loads(result.stdout) if result.stdout.strip() else []
        # Keep the venv's bootstrap pip paired with the system Python.
        # Self-upgrading pip while it is running can leave a partial install.
        return [package["name"] for package in outdated if package["name"].lower() != "pip"]
    except (json.JSONDecodeError, KeyError) as error:
        send_notification_async(NOTIFICATION_TITLE, f"Failed to parse outdated packages: {error}", urgency="critical")
        raise ValueError("Failed to parse outdated packages") from error


def repair_environment_and_upgrade_packages(environment_dir, requirements_file):
    remove_broken_environment(environment_dir)
    pip_executable = pip_executable_in(environment_dir)
    if not os.path.exists(pip_executable):
        create_environment(environment_dir)
    if requirements_file and os.path.exists(requirements_file):
        result = run_pip_or_raise(pip_executable, ["install", "--upgrade", "-r", requirements_file], INSTALL_REQUIREMENTS_FAILED)
        notify_pip_result(result)
    packages = outdated_dependency_names(pip_executable)
    if packages:
        result = run_pip_or_raise(pip_executable, ["install", "--upgrade", "-q", *packages], "Failed to upgrade packages")
        notify_pip_result(result)
    send_notification_async(NOTIFICATION_TITLE, "✅ Virtual environment rebuilt and packages updated.")


def build_environment_cli_parser():
    parser = argparse.ArgumentParser(description="Python environment manager for Hyprland")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("create", help="Create the virtual environment")
    install_parser = subparsers.add_parser("install", help="Install dependencies or a single package")
    install_parser.add_argument("packages", nargs="*", help="Packages to install")
    install_parser.add_argument("-f", "--requirements", type=str, help="The requirements file to use for installation")
    uninstall_parser = subparsers.add_parser("uninstall", help="Uninstall a single package")
    uninstall_parser.add_argument("package", help="Package to uninstall")
    subparsers.add_parser("destroy", help="Destroy the virtual environment")
    subparsers.add_parser("rebuild", help="Repair the virtual environment and upgrade packages")
    return parser


def main(argv) -> int:
    parser = build_environment_cli_parser()
    arguments = parser.parse_args(argv)
    environment_dir = managed_environment_dir()
    try:
        if arguments.command == "create":
            create_environment(environment_dir, REQUIREMENTS_FILE)
        elif arguments.command == "install" and arguments.packages:
            for package in arguments.packages:
                install_package(environment_dir, package)
        elif arguments.command == "install":
            install_requirements(environment_dir, arguments.requirements or REQUIREMENTS_FILE)
        elif arguments.command == "uninstall":
            uninstall_package(environment_dir, arguments.package)
        elif arguments.command == "destroy":
            remove_environment(environment_dir)
        elif arguments.command == "rebuild":
            repair_environment_and_upgrade_packages(environment_dir, REQUIREMENTS_FILE)
        else:
            parser.print_help()
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"Python environment update failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
