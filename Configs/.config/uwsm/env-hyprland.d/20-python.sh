#!/usr/bin/env sh
# Keep Python bytecode caches out of source trees.
PYTHONPYCACHEPREFIX="${XDG_CACHE_HOME:-$HOME/.cache}/python"
export PYTHONPYCACHEPREFIX
