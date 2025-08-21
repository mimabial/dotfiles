#!/usr/bin/env python3
import subprocess
import os
import tempfile

# Create simple test script
script_content = '''#!/bin/bash
echo "✅ Floating terminal works!"
notify-send "Success" "Floating terminal opened from waybar"
echo "Press Enter to close..."
read dummy
'''

with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
    f.write(script_content)
    temp_script = f.name

os.chmod(temp_script, 0o755)

# Launch kitty with Hyprland floating class
try:
    subprocess.Popen([
        'kitty', 
        '--class', 'floating-privacy-prompt',
        '-o', 'initial_window_width=600',
        '-o', 'initial_window_height=300',
        '--title', 'Privacy Module Test',
        'bash', temp_script
    ], 
    stdout=subprocess.DEVNULL, 
    stderr=subprocess.DEVNULL,
    start_new_session=True
    )
    
    subprocess.run(['notify-send', 'Test', 'Terminal launch attempted'], 
                   capture_output=True, timeout=1)
except Exception as e:
    subprocess.run(['notify-send', 'Error', f'Failed: {str(e)}'], 
                   capture_output=True, timeout=1)
