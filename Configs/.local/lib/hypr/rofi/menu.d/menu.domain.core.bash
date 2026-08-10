#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

menu_register_domain_core() {
  menu_define dev_tools "Dev Tools"
  menu_add_item dev_tools "󰊢  Git (LazyGit)" action dev_git
  menu_add_item dev_tools "  Docker (LazyDocker)" action dev_docker
  menu_add_item dev_tools "󰻠  CPU Monitor (Htop)" action dev_cpu_monitor
  menu_add_item dev_tools "  GPU Monitor (Nvtop)" action dev_gpu_monitor
  menu_add_item dev_tools "  Disk Usage (Dua)" action dev_disk_usage
  menu_add_item dev_tools "  Music Player (Rmpc)" action dev_music_player

  menu_define learn "Learn"
  menu_add_item learn "  Keybindings" action learn_keybindings
  menu_add_item learn "󱆃  Scripting" submenu learn_scripting

  menu_define learn_scripting "Scripting"
  menu_add_item learn_scripting "󱆃  Bash" submenu learn_bash
  menu_add_item learn_scripting "  Python" submenu learn_python

  menu_define learn_bash "Bash Scripting"
  menu_add_item learn_bash "󱆃  Bash Cheatsheet" action learn_bash_cheatsheet
  menu_add_item learn_bash "󰄬  ShellCheck" action learn_bash_shellcheck
  menu_add_item learn_bash "  POSIX Shell" action learn_bash_posix

  menu_define learn_python "Python Scripting"
  menu_add_item learn_python "  Python Docs" action learn_python_docs
  menu_add_item learn_python "󰏓  pip/pipx" action learn_python_pip
  menu_add_item learn_python "󰮲  PyGObject" action learn_python_pygobject
  menu_add_item learn_python "󱃾  subprocess" action learn_python_subprocess
  menu_add_item learn_python "󰙲  pydbus" action learn_python_pydbus
  menu_add_item learn_python "󰉋  pathlib" action learn_python_pathlib
  menu_add_item learn_python "󰘦  argparse" action learn_python_argparse
  menu_add_item learn_python "󰖟  requests" action learn_python_requests
  menu_add_item learn_python "󰍛  psutil" action learn_python_psutil
}

menu_run_action_core() {
  local action_id="$1"

  case "${action_id}" in
    main_apps) hyprshell rofi/rofi-launch.sh ;;
    dev_git) present_terminal --hypr-profile tui --app-id org.tui.LazyGit --title LazyGit -- lazygit ;;
    dev_docker) present_terminal --hypr-profile tui --app-id org.tui.LazyDocker --title LazyDocker -- lazydocker ;;
    dev_cpu_monitor) present_terminal --hypr-profile tui --app-id org.tui.Htop --title Htop -- htop ;;
    dev_gpu_monitor) present_terminal --hypr-profile tui --app-id org.tui.Nvtop --title Nvtop -- nvtop ;;
    dev_disk_usage) present_terminal --hypr-profile tui --app-id org.tui.Dua --title Dua -- dua i ;;
    dev_music_player) hyprshell launch/summon.sh --float-if-workspace-occupied class:org.tui.Rmpc -- hyprshell launch/tui.sh --app-id org.tui.Rmpc --title Rmpc -- "${XDG_CONFIG_HOME}/rmpc/lib/launch" ;;
    learn_keybindings) hyprshell keybinds/keybinds_hint.sh ;;
    learn_bash_cheatsheet) hyprshell launch/webapp.sh "https://devhints.io/bash" ;;
    learn_bash_shellcheck) hyprshell launch/webapp.sh "https://www.shellcheck.net/wiki/" ;;
    learn_bash_posix) hyprshell launch/webapp.sh "https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html" ;;
    learn_python_docs) hyprshell launch/webapp.sh "https://docs.python.org/3/" ;;
    learn_python_pip) hyprshell launch/webapp.sh "https://packaging.python.org/en/latest/guides/tool-recommendations/" ;;
    learn_python_pygobject) hyprshell launch/webapp.sh "https://pygobject.readthedocs.io/" ;;
    learn_python_subprocess) hyprshell launch/webapp.sh "https://docs.python.org/3/library/subprocess.html" ;;
    learn_python_pydbus) hyprshell launch/webapp.sh "https://github.com/LEW21/pydbus" ;;
    learn_python_pathlib) hyprshell launch/webapp.sh "https://docs.python.org/3/library/pathlib.html" ;;
    learn_python_argparse) hyprshell launch/webapp.sh "https://docs.python.org/3/library/argparse.html" ;;
    learn_python_requests) hyprshell launch/webapp.sh "https://requests.readthedocs.io/" ;;
    learn_python_psutil) hyprshell launch/webapp.sh "https://psutil.readthedocs.io/" ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_core
