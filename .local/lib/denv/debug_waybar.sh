#!/bin/bash
# debug_waybar.sh - Test waybar execution environment

# Log everything to a file for debugging
LOG_FILE="/tmp/waybar_debug.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Waybar Debug Test $(date) ==="
echo "Process ID: $$"
echo "Parent PID: $PPID"
echo "User: $(whoami)"
echo "Environment variables:"
printenv | grep -E "(DISPLAY|WAYLAND|XDG|PATH)" | sort

echo "Testing notify-send:"
if notify-send "Debug Test" "From waybar script"; then
    echo "✅ notify-send works"
else
    echo "❌ notify-send failed"
fi

echo "Testing terminal availability:"
for term in alacritty kitty foot gnome-terminal; do
    if which "$term" >/dev/null 2>&1; then
        echo "✅ $term found"
    else
        echo "❌ $term not found"
    fi
done

echo "Testing subprocess spawn:"
if python3 -c "
import subprocess
import os
print('Python subprocess test')
try:
    result = subprocess.run(['notify-send', 'Python Test', 'Subprocess works'], 
                          capture_output=True, timeout=5)
    print(f'Return code: {result.returncode}')
    print('✅ Python subprocess works')
except Exception as e:
    print(f'❌ Python subprocess failed: {e}')
"; then
    echo "✅ Python execution works"
else
    echo "❌ Python execution failed"
fi

echo "=== End Debug Test ==="
