#!/usr/bin/env bash

authentication_agents=(
  /usr/libexec/hyprpolkitagent
  /usr/lib/hyprpolkitagent
  /usr/lib/hyprpolkitagent/hyprpolkitagent

  /usr/lib/polkit-kde-authentication-agent-1
  /usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1
  /usr/libexec/polkit-kde-authentication-agent-1

  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
  /usr/libexec/polkit-gnome-authentication-agent-1
  /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
  /usr/lib/polkit-gnome-authentication-agent-1
  /usr/bin/polkit-gnome-authentication-agent-1

  /usr/libexec/polkit-mate-authentication-agent-1
  /usr/bin/lxqt-policykit-agent
  /usr/libexec/xfce-polkit
  /usr/lib/cinnamon-polkit-agent
  /usr/lib/polkit-1-dde/dde-polkit-agent
)

for authentication_agent in "${authentication_agents[@]}"; do
  if [[ -f "${authentication_agent}" && -x "${authentication_agent}" ]]; then
    exec "${authentication_agent}"
  fi
done

printf 'polkit-agent: no polkit authentication agent found on this system\n' >&2
exit 1
