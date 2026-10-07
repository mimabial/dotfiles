#!/usr/bin/env bash

_hypr_core_dir="${BASH_SOURCE[0]%/*}"
[[ "${_hypr_core_dir}" != "${BASH_SOURCE[0]}" ]] || _hypr_core_dir=.
for _hypr_core_module in services lua events processes dbus cli math paths config-layers geometry; do
  # shellcheck source=/dev/null
  source "${_hypr_core_dir}/${_hypr_core_module}.bash" || return 1
done
unset _hypr_core_dir _hypr_core_module
