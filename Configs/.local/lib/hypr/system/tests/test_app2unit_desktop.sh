#!/usr/bin/env bash
set -euo pipefail

system_dir="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$system_dir/applications/desktop-exec.bash"

argv=() workdir=""
desktop_entry_exec_tokenize_spec_into argv 'printf "two words" literal=%%c'
[[ "${argv[0]##*/}" == printf ]]
[[ "${argv[*]}" == 'printf two words literal=%%c' ]]

desktop_entry_exec_resolve_into argv workdir firefox.desktop 'https://example.com/a b'
[[ "${argv[0]##*/}" == firefox ]]
[[ "${argv[-1]}" == 'https://example.com/a b' ]]

python3 - "$system_dir/desktop-entry.py" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("desktop_entry", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
meta = ("Localized", "test-icon", "/tmp/test.desktop")
cases = {
    "cmd --label=%c:%k": ([], [["cmd", "--label=Localized:/tmp/test.desktop"]]),
    "cmd --open=%u:%c": (["/tmp/日本 語"], [["cmd", "--open=file:///tmp/%E6%97%A5%E6%9C%AC%20%E8%AA%9E:Localized"]]),
    "cmd literal=%%c:%%k:%%f": ([], [["cmd", "literal=%c:%k:%f"]]),
    "cmd x%d%c%k%D%n%N%v%m": ([], [["cmd", "xLocalized/tmp/test.desktop"]]),
    "cmd %i": ([], [["cmd", "--icon", "test-icon"]]),
    "cmd %F": (["one", "two three"], [["cmd", "one", "two three"]]),
    "cmd open=%f": (["one", "two"], [["cmd", "open=one"], ["cmd", "open=two"]]),
    "cmd drop=%f": ([], [["cmd"]]),
}
for command, (args, expected) in cases.items():
    assert module.render(module.tokenize(command), args, *meta) == expected
for command in ("cmd x%i", "cmd x%F", "cmd %F%d", "cmd %f%f", "cmd %f%u", "cmd %", "cmd %z"):
    try:
        module.render(module.tokenize(command), ["one"], *meta)
    except ValueError:
        continue
    raise AssertionError(command)
PY
