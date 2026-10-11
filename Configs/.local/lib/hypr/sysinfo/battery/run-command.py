import os
import shlex
import sys

try:
    command_args = shlex.split(sys.argv[1], posix=True)
    if command_args:
        os.execvp(command_args[0], command_args)
except (ValueError, OSError) as error:
    print(f"Battery command failed: {error}", file=sys.stderr)
    raise SystemExit(1)
