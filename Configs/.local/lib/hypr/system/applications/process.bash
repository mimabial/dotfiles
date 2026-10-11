app_launch_load_qt_env() {
  [[ -r "$qt_environment_path" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != \#* ]] || continue
    qt_environment+=("$line")
  done <"$qt_environment_path"
}

app_launch_build_uwsm_command() {
  launch_command=(uwsm-app -s "$launch_slice" -t "$launch_unit_type")
  [[ -z "$launch_app_name" ]] || launch_command+=(-a "$launch_app_name")
  [[ -z "$launch_unit_name" ]] || launch_command+=(-u "$launch_unit_name")
  [[ -z "$launch_description" ]] || launch_command+=(-d "$launch_description")
  [[ -z "$launch_silence" ]] || launch_command+=(-S "$launch_silence")
  $join_graphical_session && launch_command+=(-p After=graphical-session.target -p PartOf=graphical-session.target)
  local var
  # Scope units have no exec context, so systemd rejects Environment= there.
  for var in "${qt_environment[@]}"; do
    if [[ "$launch_unit_type" == service ]]; then launch_command+=(-p "Environment=$var"); else export "${var?}"; fi
  done
  launch_command+=(-- "${target_arguments[@]}")
}

app_launch_run_direct() {
  local redirect_out=false redirect_err=false detach=() var fd
  [[ "$launch_unit_type" == service ]] && detach=(--fork)
  for fd in /proc/self/fd/*; do fd=${fd##*/}; ((fd > 2)) && exec {fd}>&-; done
  case "$launch_silence" in out) redirect_out=true ;; err) redirect_err=true ;; both) redirect_out=true; redirect_err=true ;; esac
  for var in "${qt_environment[@]}"; do export "${var?}"; done
  $redirect_out && exec 1>/dev/null
  $redirect_err && exec 2>/dev/null
  if [[ "${target_arguments[0]}" == *.desktop || "${target_arguments[0]}" == *.desktop:* ]]; then
    exec python3 "$system_dir/desktop-entry.py" run "${target_arguments[@]}"
  fi
  command -v setsid >/dev/null 2>&1 && exec setsid "${detach[@]}" -- "${target_arguments[@]}"
  exec "${target_arguments[@]}"
}
