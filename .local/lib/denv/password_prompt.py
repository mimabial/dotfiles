#!/usr/bin/env python3

import subprocess
import sys
import time
import os
from typing import List, Optional, Tuple

class PasswordPromptHelper:
    def __init__(self):
        self.terminals = [
            # Terminal with floating window support
            {
                'command': ['alacritty'],
                'title_args': ['-t'],
                'exec_args': ['-e'],
                'floating_args': ['--class', 'floating'],
                'geometry_args': ['--option', 'window.dimensions.columns=80', '--option', 'window.dimensions.lines=20']
            },
            {
                'command': ['kitty'],
                'title_args': ['--title'],
                'exec_args': [],
                'floating_args': ['--class', 'floating'],
                'geometry_args': ['-o', 'initial_window_width=800', '-o', 'initial_window_height=400']
            },
            {
                'command': ['foot'],
                'title_args': ['--title'],
                'exec_args': [],
                'floating_args': ['--app-id', 'floating'],
                'geometry_args': ['--window-size-pixels', '800x400']
            },
            {
                'command': ['gnome-terminal'],
                'title_args': ['--title'],
                'exec_args': ['--'],
                'floating_args': [],  # GNOME Terminal doesn't have built-in floating
                'geometry_args': ['--geometry', '80x20']
            },
            {
                'command': ['konsole'],
                'title_args': ['--title'],
                'exec_args': ['-e'],
                'floating_args': [],
                'geometry_args': ['--geometry', '800x400']
            },
            {
                'command': ['xterm'],
                'title_args': ['-T'],
                'exec_args': ['-e'],
                'floating_args': [],
                'geometry_args': ['-geometry', '80x20']
            },
            {
                'command': ['urxvt'],
                'title_args': ['-title'],
                'exec_args': ['-e'],
                'floating_args': [],
                'geometry_args': ['-geometry', '80x20']
            }
        ]

    def _get_gui_environment(self):
        """Get proper environment for GUI applications launched from waybar"""
        env = os.environ.copy()
        
        # Ensure critical GUI environment variables
        gui_vars = {
            'DISPLAY': ':0',  # Fallback for X11
            'WAYLAND_DISPLAY': 'wayland-1',  # Fallback for Wayland
            'XDG_RUNTIME_DIR': f'/run/user/{os.getuid()}',
            'XDG_SESSION_TYPE': 'wayland',  # Most modern systems
            'QT_QPA_PLATFORM': 'wayland',
            'GDK_BACKEND': 'wayland,x11',
        }
        
        # Only set if not already present
        for var, default in gui_vars.items():
            if var not in env:
                env[var] = default
        
        # Special handling for DISPLAY and WAYLAND_DISPLAY
        if not env.get('DISPLAY') and not env.get('WAYLAND_DISPLAY'):
            # Try to detect available display
            if os.path.exists('/tmp/.X11-unix'):
                env['DISPLAY'] = ':0'
            if os.path.exists(f"/run/user/{os.getuid()}"):
                wayland_sockets = [f for f in os.listdir(f"/run/user/{os.getuid()}") 
                                 if f.startswith('wayland-')]
                if wayland_sockets:
                    env['WAYLAND_DISPLAY'] = wayland_sockets[0]
        
        return env

    def _detect_window_manager(self):
        """Detect the current window manager for better floating window support"""
        wm_detection = {
            'sway': ['swaymsg', '-v'],
            'hyprland': ['hyprctl', 'version'],
            'i3': ['i3-msg', '--version'],
            'gnome': ['gnome-shell', '--version'],
            'kde': ['kwin_wayland', '--version'],
        }
        
        for wm, cmd in wm_detection.items():
            try:
                result = subprocess.run(cmd, capture_output=True, timeout=1)
                if result.returncode == 0:
                    return wm
            except:
                continue
        
        return 'unknown'

    def _get_terminal_with_wm_support(self, terminal):
        """Enhance terminal configuration based on window manager"""
        wm = self._detect_window_manager()
        terminal = terminal.copy()
        
        # Hyprland-specific configuration
        if wm == 'hyprland':
            if terminal['command'][0] == 'kitty':
                # Kitty on Hyprland - use class
                terminal['floating_args'] = ['--class', 'floating-privacy-prompt']
            elif terminal['command'][0] == 'gnome-terminal':
                # GNOME Terminal - no built-in floating, rely on Hyprland rules
                terminal['floating_args'] = []
        
        return terminal

    def is_running_in_terminal(self) -> bool:
        """Detect if we're already running in a terminal session"""
        # Check if we're launched from waybar (not a real terminal)
        if 'waybar' in os.environ.get('_', '').lower():
            return False
        
        # Check if parent process is waybar
        try:
            ppid = os.getppid()
            with open(f'/proc/{ppid}/comm', 'r') as f:
                parent_name = f.read().strip()
                if parent_name == 'waybar':
                    return False
        except:
            pass
        
        # Check if stdin/stdout are connected to a terminal
        if hasattr(os, 'isatty'):
            if os.isatty(0) and os.isatty(1):  # stdin and stdout are TTY
                return True
        
        # Check for terminal-specific environment variables
        terminal_vars = ['TERM', 'TERM_PROGRAM', 'TERMINAL_EMULATOR']
        for var in terminal_vars:
            if os.environ.get(var):
                return True
        
        # Check if we're in an SSH session
        if os.environ.get('SSH_CONNECTION') or os.environ.get('SSH_CLIENT'):
            return True
            
        return False

    def should_use_floating_terminal(self) -> bool:
        """Determine if we should use floating terminal or current terminal"""
        # If already in a terminal, use current terminal
        if self.is_running_in_terminal():
            return False
        
        # If no display available, can't open floating windows
        if not os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
            return False
        
        # If explicitly requested via environment variable
        if os.environ.get('PRIVACY_MODULE_FORCE_FLOATING') == '1':
            return True
        
        if os.environ.get('PRIVACY_MODULE_FORCE_TERMINAL') == '1':
            return False
        
        # Default: use floating if we seem to be in GUI context
        return True

    def find_available_terminal(self) -> Optional[dict]:
        """Find the first available terminal emulator"""
        for terminal in self.terminals:
            try:
                result = subprocess.run(['which', terminal['command'][0]], 
                                      capture_output=True, timeout=1)
                if result.returncode == 0:
                    return self._get_terminal_with_wm_support(terminal)
            except:
                continue
        return None

    def create_sudo_script_with_output(self, command: List[str], title: str, description: str, output_file: str) -> str:
        """Create a temporary script for sudo command execution with output capture"""
        script_content = f'''#!/bin/bash

# Privacy Module Password Prompt
echo "╭────────────────────────────────────────────────────────╮"
echo "│                    Privacy Module                       │"
echo "│                 Password Required                       │"
echo "╰────────────────────────────────────────────────────────╯"
echo
echo "Action: {title}"
echo "Description: {description}"
echo
echo "Command to execute:"
echo "  {' '.join(command)}"
echo
echo "This command requires administrator privileges."
echo

# Function to execute command with better error handling
execute_command() {{
    if {' '.join(command)} > "{output_file}" 2>&1; then
        echo
        echo "✅ Command executed successfully!"
        echo "📄 Output saved to temporary file"
        echo
        read -p "Press Enter to close this window..." dummy
        exit 0
    else
        echo
        echo "❌ Command failed!"
        echo
        echo "Possible reasons:"
        echo "  • Incorrect password"
        echo "  • Insufficient privileges"
        echo "  • Command not available"
        echo "  • Hardware not supported"
        echo
        read -p "Press Enter to close this window..." dummy
        exit 1
    fi
}}

# Ask for confirmation
echo "Do you want to proceed? (y/N)"
read -n 1 -r REPLY
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Executing command..."
    echo
    execute_command
else
    echo "Operation cancelled by user."
    echo
    read -p "Press Enter to close this window..." dummy
    exit 1
fi
'''
        
        # Create temporary script
        import tempfile
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
            f.write(script_content)
            temp_script = f.name
        
        os.chmod(temp_script, 0o755)
        return temp_script

    def run_sudo_command_with_output_floating(self, command: List[str], title: str, description: str) -> Tuple[bool, str, str]:
        """Run a sudo command in a floating terminal and capture output"""
        terminal = self.find_available_terminal()
        
        if not terminal:
            # Try notification instead of print when in GUI context
            try:
                subprocess.run(['notify-send', 'Privacy Module Error', 
                               'No terminal emulator found\nInstall: alacritty, kitty, or foot'], 
                               capture_output=True, timeout=2)
            except:
                pass
            return False, "", "No terminal found"
        
        # Create temporary output file
        import tempfile
        output_file = tempfile.mktemp()
        
        # Create the sudo script
        temp_script = self.create_sudo_script_with_output(command, title, description, output_file)
        
        try:
            # Build terminal command
            terminal_cmd = terminal['command'].copy()
            
            # Add floating window arguments (for Wayland compositors)
            if terminal['floating_args']:
                terminal_cmd.extend(terminal['floating_args'])
            
            # Add geometry
            if terminal['geometry_args']:
                terminal_cmd.extend(terminal['geometry_args'])
            
            # Add title
            if terminal['title_args']:
                terminal_cmd.extend(terminal['title_args'])
                terminal_cmd.append(f"Privacy Module - {title}")
            
            # Add execution arguments
            if terminal['exec_args']:
                terminal_cmd.extend(terminal['exec_args'])
            
            # Add the script to execute
            terminal_cmd.extend(['bash', temp_script])
            
            # Ensure proper environment for GUI apps launched from waybar
            env = self._get_gui_environment()
            
            # Launch terminal and wait for completion
            process = subprocess.Popen(
                terminal_cmd, 
                stdout=subprocess.DEVNULL, 
                stderr=subprocess.DEVNULL,
                env=env,
                start_new_session=True
            )
            
            # Wait for process to complete
            process.wait()
            
            # Read output if available
            stdout = ""
            stderr = ""
            if os.path.exists(output_file):
                with open(output_file, 'r') as f:
                    stdout = f.read()
                success = process.returncode == 0
            else:
                success = False
                stderr = "No output file created"
            
            return success, stdout, stderr
            
        except Exception as e:
            return False, "", f"Failed to launch terminal: {str(e)}"
        finally:
            # Clean up temp files
            for file_path in [temp_script, output_file]:
                try:
                    os.unlink(file_path)
                except:
                    pass

    def run_sudo_command_with_output_terminal(self, command: List[str], title: str, description: str) -> Tuple[bool, str, str]:
        """Run sudo command in current terminal and capture output"""
        print("╭────────────────────────────────────────────────────────╮")
        print("│                    Privacy Module                       │")
        print("│                 Password Required                       │")
        print("╰────────────────────────────────────────────────────────╯")
        print()
        print(f"Action: {title}")
        print(f"Description: {description}")
        print()
        print("Command to execute:")
        print(f"  {' '.join(command)}")
        print()
        print("This command requires administrator privileges.")
        print()
        
        # Ask for confirmation
        try:
            response = input("Do you want to proceed? (y/N): ")
            if response.lower() in ['y', 'yes']:
                print("Executing command...")
                print()
                
                # Execute the command and capture output
                result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                
                if result.returncode == 0:
                    print()
                    print("✅ Command executed successfully!")
                    return True, result.stdout, result.stderr
                else:
                    print()
                    print("❌ Command failed!")
                    return False, result.stdout, result.stderr
            else:
                print("Operation cancelled by user.")
                return False, "", "Cancelled by user"
                
        except (KeyboardInterrupt, EOFError):
            print("\nOperation cancelled by user.")
            return False, "", "Cancelled by user"
        except Exception as e:
            print(f"\n❌ Error: {e}")
            return False, "", str(e)

    def run_sudo_command_with_output(self, command: List[str], title: str, description: str) -> Tuple[bool, str, str]:
        """Run a sudo command with context-aware interface and capture output"""
        
        # Ensure sudo is in the command
        if command[0] != 'sudo':
            command = ['sudo'] + command
        
        # Decide based on context
        if self.should_use_floating_terminal():
            # GUI context - use floating terminal
            return self.run_sudo_command_with_output_floating(command, title, description)
        else:
            # Terminal context - use current terminal
            return self.run_sudo_command_with_output_terminal(command, title, description)

    def run_sudo_command(self, command: List[str], title: str, description: str) -> bool:
        """Run a sudo command with context-aware interface (backwards compatibility)"""
        success, stdout, stderr = self.run_sudo_command_with_output(command, title, description)
        return success

    # ... (rest of the methods remain the same)

# Global instance for easy access
password_helper = PasswordPromptHelper()

def run_sudo_command(command: List[str], title: str, description: str) -> bool:
    """Convenience function to run sudo commands with context awareness"""
    return password_helper.run_sudo_command(command, title, description)

def run_sudo_command_with_output(command: List[str], title: str, description: str) -> Tuple[bool, str, str]:
    """Convenience function to run sudo commands with output capture"""
    return password_helper.run_sudo_command_with_output(command, title, description)
