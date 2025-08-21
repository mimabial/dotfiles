#!/usr/bin/env python3
"""
Custom Privacy Module for Waybar
Monitors webcam, microphone, and screen sharing activity
"""

import json
import subprocess
import sys
import os
import glob
import time
from pathlib import Path
from typing import Dict, List, Optional

class PrivacyMonitor:
    def __init__(self):
        # Status-aware icons showing actual state
        self.icons = {
            'webcam_active': '📹',      # Camera is recording
            'webcam_available': '📷',   # Camera available but not recording
            'webcam_disabled': '📵',    # Camera disabled/unavailable
            'microphone_active': '🎤',  # Mic is active and unmuted
            'microphone_available': '🎙️', # Mic available but not in use
            'microphone_muted': '🔇',   # Mic is muted
            'microphone_unavailable': '❌', # No mic detected
            'screenshare_active': '🖥️', # Currently screen sharing
            'screenshare_ready': '💻',  # Screen sharing app running but not sharing
            'location_active': '📍',    # Location actively being accessed
            'location_available': '🗺️', # Location services available
            'location_unavailable': '🚫' # No location services
        }
        
        # Alternative Nerd Font icons (uncomment if preferred)
        # self.icons = {
        #     'webcam_active': '󰄀',      # Camera recording
        #     'webcam_available': '󰄂',   # Camera available
        #     'webcam_disabled': '󰄃',    # Camera disabled
        #     'microphone_active': '󰍬',  # Mic active
        #     'microphone_available': '󰍮', # Mic available
        #     'microphone_muted': '󰍭',   # Mic muted
        #     'microphone_unavailable': '󰍯', # No mic
        #     'screenshare_active': '󰍹',  # Screen sharing
        #     'screenshare_ready': '󰍺',   # Ready to share
        #     'location_active': '󰆤',    # Location active
        #     'location_available': '󰆣', # Location available
        #     'location_unavailable': '󰌎' # Location unavailable
        # }

    def run_in_terminal(self, command: str, title: str = "Privacy Module") -> bool:
        """Run a command in a terminal window"""
        terminals = [
            ['alacritty', '-t', title, '-e', 'sh', '-c'],
            ['kitty', '--title', title, 'sh', '-c'],
            ['foot', '--title', title, 'sh', '-c'],
            ['gnome-terminal', '--title', title, '--', 'sh', '-c'],
            ['konsole', '--title', title, '-e', 'sh', '-c'],
            ['xterm', '-T', title, '-e', 'sh', '-c'],
            ['urxvt', '-T', title, '-e', 'sh', '-c']
        ]
        
        for terminal_cmd in terminals:
            try:
                # Check if terminal exists
                if subprocess.run(['which', terminal_cmd[0]], capture_output=True).returncode == 0:
                    # Build full command
                    full_cmd = terminal_cmd + [f'{command}; echo "\nPress Enter to close..."; read']
                    subprocess.Popen(full_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    return True
            except:
                continue
        
        return False

    def show_menu(self) -> None:
        """Show context menu with all privacy options"""
        # Menu options with icons and descriptions
        menu_options = [
            ("🎤 Toggle Microphone", "toggle-microphone", "Mute/unmute microphone"),
            ("📷 Toggle Camera", "toggle-webcam", "Enable/disable camera hardware"),
            ("🔪 Kill Camera Apps", "kill-camera-apps", "Stop apps using camera"),
            ("⚙️  Open Settings", "open-settings", "Open audio settings"),
            ("📊 Show Status", "status", "Show detailed privacy status"),
            ("🔍 Who's Using Devices", "who-is-using", "See what's accessing your devices"),
            ("🧪 Debug Toggle", "debug-toggle", "Debug camera toggle logic"),
            ("🎵 Debug PipeWire", "debug-pipewire", "Debug PipeWire detection"),
            ("❓ Explain Devices", "explain-devices", "Explain cryptic device names"),
            ("📋 List All Devices", "list-devices", "Show all audio/video devices")
        ]
        
        # Try different menu systems
        if self._show_wofi_menu(menu_options):
            return
        elif self._show_rofi_menu(menu_options):
            return
        elif self._show_dmenu_menu(menu_options):
            return
        else:
            # Fallback to terminal menu
            self._show_terminal_menu(menu_options)
    
    def _show_wofi_menu(self, options) -> bool:
        """Show menu using wofi (Wayland-native)"""
        try:
            if subprocess.run(['which', 'wofi'], capture_output=True).returncode != 0:
                return False
            
            # Create menu items
            menu_text = "\n".join([f"{opt[0]} - {opt[2]}" for opt in options])
            
            # Run wofi
            result = subprocess.run(['wofi', '--dmenu', '--prompt', 'Privacy Module', 
                                   '--width', '400', '--height', '300'],
                                  input=menu_text, text=True, capture_output=True)
            
            if result.returncode == 0 and result.stdout.strip():
                selected = result.stdout.strip()
                # Find the command for the selected option
                for opt in options:
                    if selected.startswith(opt[0]):
                        self._execute_menu_command(opt[1])
                        return True
            
            return True  # wofi was available even if nothing selected
        except:
            return False
    
    def _show_rofi_menu(self, options) -> bool:
        """Show menu using rofi"""
        try:
            if subprocess.run(['which', 'rofi'], capture_output=True).returncode != 0:
                return False
            
            # Create menu items
            menu_text = "\n".join([f"{opt[0]} - {opt[2]}" for opt in options])
            
            # Run rofi
            result = subprocess.run(['rofi', '-dmenu', '-p', 'Privacy Module', 
                                   '-theme-str', 'window {width: 400px;}'],
                                  input=menu_text, text=True, capture_output=True)
            
            if result.returncode == 0 and result.stdout.strip():
                selected = result.stdout.strip()
                # Find the command for the selected option
                for opt in options:
                    if selected.startswith(opt[0]):
                        self._execute_menu_command(opt[1])
                        return True
            
            return True  # rofi was available
        except:
            return False
    
    def _show_dmenu_menu(self, options) -> bool:
        """Show menu using dmenu"""
        try:
            if subprocess.run(['which', 'dmenu'], capture_output=True).returncode != 0:
                return False
            
            # Create menu items (shorter for dmenu)
            menu_text = "\n".join([opt[0] for opt in options])
            
            # Run dmenu
            result = subprocess.run(['dmenu', '-p', 'Privacy Module'],
                                  input=menu_text, text=True, capture_output=True)
            
            if result.returncode == 0 and result.stdout.strip():
                selected = result.stdout.strip()
                # Find the command for the selected option
                for opt in options:
                    if selected == opt[0]:
                        self._execute_menu_command(opt[1])
                        return True
            
            return True  # dmenu was available
        except:
            return False
    
    def _show_terminal_menu(self, options) -> None:
        """Fallback terminal-based menu"""
        menu_script = f"""
echo "╔══════════════════════════════════════╗"
echo "║           Privacy Module Menu        ║"
echo "╠══════════════════════════════════════╣"
"""
        
        for i, (icon_text, cmd, desc) in enumerate(options, 1):
            menu_script += f'echo "║ {i:2d}. {icon_text:<30} ║"\n'
        
        menu_script += f"""
echo "╚══════════════════════════════════════╝"
echo ""
read -p "Select option (1-{len(options)}) or press Enter to cancel: " choice
echo ""

case "$choice" in
"""
        
        for i, (icon_text, cmd, desc) in enumerate(options, 1):
            menu_script += f'    {i}) ~/.config/waybar/scripts/privacy.py {cmd};;\n'
        
        menu_script += """
    *) echo "Cancelled or invalid option";;
esac

echo ""
echo "Press Enter to close..."
read
"""
        
        self.run_in_terminal(menu_script, "Privacy Module Menu")
    
    def _execute_menu_command(self, command: str) -> None:
        """Execute a menu command"""
        try:
            # Get the script path
            script_path = sys.argv[0]
            
            if command in ['status', 'who-is-using', 'debug-toggle', 'debug-pipewire', 
                          'explain-devices', 'list-devices']:
                # Commands that show output - run in terminal
                cmd = f"{script_path} {command}"
                self.run_in_terminal(cmd, f"Privacy Module - {command}")
            else:
                # Commands that just execute - run directly
                subprocess.Popen([sys.executable, script_path, command],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            try:
                subprocess.run(['notify-send', 'Privacy Module', f'Error: {str(e)}'], 
                             capture_output=True, timeout=2)
            except:
                pass
        """Run a command in a terminal window"""
        terminals = [
            ['alacritty', '-t', title, '-e', 'sh', '-c'],
            ['kitty', '--title', title, 'sh', '-c'],
            ['foot', '--title', title, 'sh', '-c'],
            ['gnome-terminal', '--title', title, '--', 'sh', '-c'],
            ['konsole', '--title', title, '-e', 'sh', '-c'],
            ['xterm', '-T', title, '-e', 'sh', '-c'],
            ['urxvt', '-T', title, '-e', 'sh', '-c']
        ]
        
        for terminal_cmd in terminals:
            try:
                # Check if terminal exists
                if subprocess.run(['which', terminal_cmd[0]], capture_output=True).returncode == 0:
                    # Build full command
                    full_cmd = terminal_cmd + [f'{command}; echo "\nPress Enter to close..."; read']
                    subprocess.Popen(full_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    return True
            except:
                continue
        
        return False

    def get_camera_module_name(self) -> str:
        """Detect which camera module is providing video devices"""
        try:
            # Method 1: Check udev info for video devices
            video_devices = glob.glob('/dev/video*')
            for device in video_devices:
                try:
                    result = subprocess.run(['udevadm', 'info', '--name', device], 
                                          capture_output=True, text=True, timeout=3)
                    if result.returncode == 0:
                        for line in result.stdout.split('\n'):
                            if 'DRIVER=' in line:
                                driver = line.split('DRIVER=')[-1].strip()
                                if driver and driver != 'video4linux':
                                    return driver
                except:
                    continue
            
            # Method 2: Check loaded modules for common camera drivers
            result = subprocess.run(['lsmod'], capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                # Look for common camera modules
                camera_modules = ['uvcvideo', 'gspca_main', 'gspca_ov534', 'gspca_pac7302', 
                                'gspca_spca561', 'gspca_zc3xx', 'usb_camera', 'v4l2loopback']
                
                for line in lines:
                    module_name = line.split()[0] if line.split() else ''
                    if module_name in camera_modules:
                        return module_name
                    # Check for gspca variants
                    if module_name.startswith('gspca_'):
                        return 'gspca_main'  # Parent module
            
            # Method 3: Check dmesg for recent camera module loads
            try:
                result = subprocess.run(['dmesg'], capture_output=True, text=True, timeout=3)
                if result.returncode == 0:
                    lines = result.stdout.split('\n')
                    for line in reversed(lines[-100:]):  # Check last 100 lines
                        if any(word in line.lower() for word in ['camera', 'video', 'webcam', 'uvc']):
                            if 'registered' in line.lower():
                                # Try to extract module name
                                for module in ['uvcvideo', 'gspca', 'usb']:
                                    if module in line:
                                        return module if module != 'gspca' else 'gspca_main'
            except:
                pass
                
        except Exception:
            pass
            
        return 'uvcvideo'  # Default fallback
        """Detect which camera module is providing video devices"""
        try:
            # Method 1: Check udev info for video devices
            video_devices = glob.glob('/dev/video*')
            for device in video_devices:
                try:
                    result = subprocess.run(['udevadm', 'info', '--name', device], 
                                          capture_output=True, text=True, timeout=3)
                    if result.returncode == 0:
                        for line in result.stdout.split('\n'):
                            if 'DRIVER=' in line:
                                driver = line.split('DRIVER=')[-1].strip()
                                if driver and driver != 'video4linux':
                                    return driver
                except:
                    continue
            
            # Method 2: Check loaded modules for common camera drivers
            result = subprocess.run(['lsmod'], capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                # Look for common camera modules
                camera_modules = ['uvcvideo', 'gspca_main', 'gspca_ov534', 'gspca_pac7302', 
                                'gspca_spca561', 'gspca_zc3xx', 'usb_camera', 'v4l2loopback']
                
                for line in lines:
                    module_name = line.split()[0] if line.split() else ''
                    if module_name in camera_modules:
                        return module_name
                    # Check for gspca variants
                    if module_name.startswith('gspca_'):
                        return 'gspca_main'  # Parent module
            
            # Method 3: Check dmesg for recent camera module loads
            try:
                result = subprocess.run(['dmesg'], capture_output=True, text=True, timeout=3)
                if result.returncode == 0:
                    lines = result.stdout.split('\n')
                    for line in reversed(lines[-100:]):  # Check last 100 lines
                        if any(word in line.lower() for word in ['camera', 'video', 'webcam', 'uvc']):
                            if 'registered' in line.lower():
                                # Try to extract module name
                                for module in ['uvcvideo', 'gspca', 'usb']:
                                    if module in line:
                                        return module if module != 'gspca' else 'gspca_main'
            except:
                pass
                
        except Exception:
            pass
            
        return 'uvcvideo'  # Default fallback

    def check_webcam_status(self) -> Dict[str, any]:
        """Check comprehensive webcam status"""
        status = {
            'active_streams': [],
            'available_devices': [],
            'devices_in_use': [],
            'has_webcam': False,
            'hardware_disabled': False,
            'camera_module': None,
            'device_details': []
        }
        
        # Detect camera module
        camera_module = self.get_camera_module_name()
        status['camera_module'] = camera_module
        
        # Check if camera module is loaded
        module_loaded = False
        try:
            result = subprocess.run(['lsmod'], capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                # Check for exact module or parent module
                if camera_module in result.stdout:
                    module_loaded = True
                elif camera_module == 'gspca_main':
                    # Check for any gspca variant
                    if any(line.strip().startswith('gspca_') for line in result.stdout.split('\n')):
                        module_loaded = True
        except:
            pass
        
        # Check for video devices
        video_devices = glob.glob('/dev/video*')
        
        # If no module and no devices, definitely disabled
        if not module_loaded and not video_devices:
            status['hardware_disabled'] = True
            return status
        
        # If module not loaded but devices exist, might be other driver
        if not module_loaded and video_devices:
            # Try to detect what's actually providing the devices
            status['camera_module'] = self.get_camera_module_name()
        
        # If no devices, might be starting up, wait and check again
        if not video_devices:
            import time
            time.sleep(0.5)  # Brief wait for devices to appear
            video_devices = glob.glob('/dev/video*')
            if not video_devices:
                status['hardware_disabled'] = True
                return status
        
        # Check each video device for functionality and categorize them
        main_capture_devices = []
        all_functional_devices = []
        processes_using_video = []
        
        for device in video_devices:
            device_info = {
                'device': device,
                'name': f"Device {device}",
                'is_capture': False,
                'is_main': False,
                'capabilities': []
            }
            
            try:
                # Check device capabilities
                result = subprocess.run(['v4l2-ctl', '--device', device, '--info'], 
                                      capture_output=True, text=True, timeout=2)
                if result.returncode == 0:
                    info_text = result.stdout
                    
                    # Get device name
                    device_name = self._get_camera_friendly_name_v4l(device)
                    device_info['name'] = device_name
                    
                    # Check capabilities
                    caps_result = subprocess.run(['v4l2-ctl', '--device', device, '--list-formats-ext'], 
                                                capture_output=True, text=True, timeout=2)
                    
                    # Determine if this is a main capture device
                    if 'Video Capture' in info_text:
                        device_info['is_capture'] = True
                        status['has_webcam'] = True
                        
                        # Consider it "main" if it has common video formats
                        if caps_result.returncode == 0:
                            formats = caps_result.stdout.lower()
                            if any(fmt in formats for fmt in ['yuyv', 'mjpg', 'nv12', 'rgb']):
                                device_info['is_main'] = True
                                main_capture_devices.append(device_info)
                        
                        all_functional_devices.append(device_info)
                    
                    # Check if device is in use
                    lsof_result = subprocess.run(['lsof', device], 
                                               capture_output=True, text=True, timeout=1)
                    if lsof_result.returncode == 0 and lsof_result.stdout.strip():
                        lines = lsof_result.stdout.strip().split('\n')
                        process_lines = [line for line in lines[1:] if line.strip()]
                        if process_lines:
                            for line in process_lines:
                                parts = line.split()
                                if len(parts) > 1:
                                    process_name = parts[0]
                                    pid = parts[1]
                                    # Only count main capture devices as "in use" for privacy purposes
                                    if device_info['is_main'] or device_info['is_capture']:
                                        status['devices_in_use'].append({
                                            'device': device,
                                            'process': process_name,
                                            'pid': pid,
                                            'name': device_name
                                        })
                                        processes_using_video.append(process_name)
                
                status['device_details'].append(device_info)
                                
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
                # If v4l2-ctl fails, try basic check
                if os.path.exists(device):
                    try:
                        with open(device, 'rb') as f:
                            pass
                        device_info['name'] = f"Camera {device}"
                        device_info['is_capture'] = True
                        status['has_webcam'] = True
                        all_functional_devices.append(device_info)
                        status['device_details'].append(device_info)
                    except:
                        pass
        
        # Use main capture devices for available devices list
        if main_capture_devices:
            status['available_devices'] = main_capture_devices
        else:
            # Fallback to all functional devices if no main ones detected
            status['available_devices'] = all_functional_devices
        
        # If we found devices but none are functional, consider hardware disabled
        if video_devices and not all_functional_devices:
            status['hardware_disabled'] = True
            status['has_webcam'] = False
            return status
        
        # Only check PipeWire streams if we have functional devices
        try:
            result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                
                for item in data:
                    if item.get('type') == 'PipeWire:Interface:Node':
                        props = item.get('info', {}).get('props', {})
                        media_class = props.get('media.class', '')
                        
                        # Only count as active if it's an actual application stream
                        if 'Stream/Input/Video' in media_class:
                            app_name = props.get('application.name', '')
                            app_process = props.get('application.process.binary', '')
                            app_pid = props.get('application.process.id', '')
                            
                            # Very strict filtering: only count if we have a real application
                            real_app = False
                            display_name = None
                            
                            # Check for real application process
                            if app_process and app_process not in ['Unknown', '', 'pipewire']:
                                if app_pid:
                                    try:
                                        subprocess.run(['kill', '-0', str(app_pid)], 
                                                     check=True, capture_output=True, timeout=1)
                                        real_app = True
                                        display_name = f"{app_process} (PID: {app_pid})"
                                    except:
                                        pass
                                else:
                                    try:
                                        result = subprocess.run(['pgrep', '-f', app_process], 
                                                              capture_output=True, timeout=1)
                                        if result.returncode == 0:
                                            real_app = True
                                            display_name = app_process
                                    except:
                                        pass
                            
                            # Check for real application name (not hardware)
                            elif (app_name and app_name not in ['Unknown', '', 'pipewire'] and 
                                  not app_name.startswith('v4l2_') and
                                  not 'input' in app_name.lower()):
                                real_app = True
                                display_name = app_name
                            
                            if real_app and display_name:
                                status['active_streams'].append(display_name)
                            
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            pass
            
        return status

    def _get_camera_friendly_name_v4l(self, device_path: str) -> str:
        """Get camera friendly name using v4l2-ctl"""
        try:
            result = subprocess.run(['v4l2-ctl', '--device', device_path, '--info'], 
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                for line in lines:
                    if 'Card type' in line:
                        camera_name = line.split(':')[-1].strip()
                        if camera_name and camera_name != device_path:
                            return camera_name
        except:
            pass
            
        # Fallback
        return f"Camera {device_path}"

    def _get_camera_friendly_name(self, device_path: str) -> str:
        """Convert v4l2 device path to friendly camera name"""
        try:
            # Extract USB info from the path
            if 'usb' in device_path:
                # Try to get camera model from v4l2 info
                video_devices = glob.glob('/dev/video*')
                for device in video_devices:
                    try:
                        # Get device info using v4l2-ctl if available
                        result = subprocess.run(['v4l2-ctl', '--device', device, '--info'], 
                                              capture_output=True, text=True, timeout=2)
                        if result.returncode == 0:
                            lines = result.stdout.split('\n')
                            for line in lines:
                                if 'Card type' in line or 'Device name' in line:
                                    camera_name = line.split(':')[-1].strip()
                                    if camera_name and camera_name != device:
                                        return camera_name
                    except:
                        continue
                        
                # Fallback: try to extract USB port info
                usb_parts = device_path.split('usb-')[-1].split('.')
                if len(usb_parts) > 1:
                    port_info = usb_parts[1].replace('_', '.')
                    return f"USB Camera (port {port_info})"
                else:
                    return "USB Camera"
            else:
                return "Built-in Camera"
                
        except Exception:
            pass
            
        return "Camera Device"

    def check_microphone_status(self) -> Dict[str, any]:
        """Check comprehensive microphone status"""
        status = {
            'active_streams': [],
            'is_muted': None,
            'has_microphone': False,
            'default_source': None
        }
        
        try:
            # Check if microphone exists and get default source
            result = subprocess.run(['pactl', 'get-default-source'], 
                                  capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                status['default_source'] = result.stdout.strip()
                status['has_microphone'] = True
                
                # Check mute status
                mute_result = subprocess.run(['pactl', 'get-source-mute', '@DEFAULT_SOURCE@'], 
                                           capture_output=True, text=True, timeout=3)
                if mute_result.returncode == 0:
                    status['is_muted'] = 'yes' in mute_result.stdout.lower()
                
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            pass
        
        # Check for active audio input streams
        try:
            result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                
                for item in data:
                    if item.get('type') == 'PipeWire:Interface:Node':
                        props = item.get('info', {}).get('props', {})
                        media_class = props.get('media.class', '')
                        
                        if 'Stream/Input/Audio' in media_class:
                            app_name = props.get('application.name', '')
                            app_process = props.get('application.process.binary', '')
                            
                            if app_name and app_name != 'Unknown':
                                display_name = app_name
                            elif app_process:
                                display_name = app_process
                            else:
                                display_name = "Audio input stream"
                                
                            status['active_streams'].append(display_name)
                            
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            pass
            
        return status

    def check_video_devices(self) -> List[str]:
        """Check if video devices are being accessed"""
        active_devices = []
        
        # Check /dev/video* devices
        video_devices = glob.glob('/dev/video*')
        
        for device in video_devices:
            try:
                # Check if device is busy by trying to get processes using it
                result = subprocess.run(['lsof', device], 
                                      capture_output=True, text=True, timeout=2)
                if result.returncode == 0 and result.stdout.strip():
                    lines = result.stdout.strip().split('\n')[1:]  # Skip header
                    for line in lines:
                        parts = line.split()
                        if len(parts) > 1:
                            process_name = parts[0]
                            active_devices.append(f"Device {device}: {process_name}")
            except (subprocess.TimeoutExpired, FileNotFoundError):
                continue
                
        return active_devices

    def check_screen_sharing_status(self) -> Dict[str, any]:
        """Check comprehensive screen sharing status"""
        status = {
            'active_sessions': [],
            'ready_apps': [],
            'is_sharing': False
        }
        
        # Apps that could be doing screen sharing
        sharing_apps = {
            'obs': 'OBS Studio',
            'zoom': 'Zoom',
            'teams': 'Microsoft Teams',
            'discord': 'Discord',
            'skype': 'Skype',
            'chrome': 'Chrome',
            'firefox': 'Firefox',
            'chromium': 'Chromium'
        }
        
        # Hyprland-specific screen tools
        hyprland_tools = {
            'grim': 'Screenshot (grim)',
            'slurp': 'Screen selection (slurp)', 
            'wf-recorder': 'Screen recording (wf-recorder)',
            'xdg-desktop-portal-hyprland': 'Hyprland Portal',
            'xdg-desktop-portal-wlr': 'wlroots Portal'
        }
        
        # Check for running processes
        all_apps = {**sharing_apps, **hyprland_tools}
        
        for process, display_name in all_apps.items():
            try:
                result = subprocess.run(['pgrep', '-f', process], 
                                      capture_output=True, text=True, timeout=2)
                if result.returncode == 0:
                    # Process is running, check if actually sharing
                    if self._is_actually_sharing_detailed(process):
                        status['active_sessions'].append(display_name)
                        status['is_sharing'] = True
                    else:
                        # Process running but not sharing
                        if process in ['obs', 'zoom', 'teams', 'discord']:
                            status['ready_apps'].append(display_name)
                            
            except (subprocess.TimeoutExpired, FileNotFoundError):
                continue
                
        return status

    def _is_actually_sharing_detailed(self, process_name: str) -> bool:
        """Enhanced check if process is actually sharing screen"""
        try:
            # Method 1: Check PipeWire for screen capture streams
            result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for item in data:
                    if item.get('type') == 'PipeWire:Interface:Node':
                        props = item.get('info', {}).get('props', {})
                        media_class = props.get('media.class', '')
                        app_name = props.get('application.name', '').lower()
                        
                        # Look for screen sharing streams
                        if 'Stream/Output/Video' in media_class:
                            if (process_name.lower() in app_name or 
                                'portal' in app_name or 
                                'screen' in app_name):
                                return True
            
            # Method 2: Hyprland tools are typically active when running
            if process_name in ['grim', 'slurp', 'wf-recorder']:
                return True
                
            # Method 3: Check if portal is handling screen share requests
            if 'portal' in process_name:
                try:
                    # Check for active portal sessions
                    portal_result = subprocess.run(['busctl', 'introspect', 
                                                  'org.freedesktop.portal.Desktop',
                                                  '/org/freedesktop/portal/desktop'], 
                                                 capture_output=True, text=True, timeout=2)
                    if portal_result.returncode == 0 and 'ScreenCast' in portal_result.stdout:
                        return True
                except:
                    pass
            
        except (json.JSONDecodeError, subprocess.TimeoutExpired):
            pass
            
        return False

    def check_location_status(self) -> Dict[str, any]:
        """Check comprehensive location access status"""
        status = {
            'active_access': [],
            'available_services': [],
            'is_active': False
        }
        
        try:
            # Check if geoclue service is running
            result = subprocess.run(['systemctl', '--user', 'is-active', 'geoclue'], 
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                status['available_services'].append('Geoclue location service')
                
                # Check for active clients
                clients_result = subprocess.run(['busctl', 'tree', 'org.freedesktop.GeoClue2'], 
                                              capture_output=True, text=True, timeout=3)
                if clients_result.returncode == 0:
                    client_lines = [line for line in clients_result.stdout.split('\n') 
                                  if '/org/freedesktop/GeoClue2/Client' in line]
                    if client_lines:
                        status['is_active'] = True
                        status['active_access'].append(f"Location: {len(client_lines)} active client(s)")
                        
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
            
        # Check for GPS/location processes
        location_processes = ['gpsd', 'chronyd', 'networkmanager']
        for process in location_processes:
            try:
                result = subprocess.run(['pgrep', '-f', process], 
                                      capture_output=True, text=True, timeout=1)
                if result.returncode == 0:
                    status['available_services'].append(f"{process} (location capable)")
            except:
                continue
                
        return status

    def _is_actually_sharing(self, process_name: str) -> bool:
        """Check if process is actually sharing screen, not just running"""
        try:
            # For Hyprland portal
            if 'hyprland' in process_name:
                # Check if portal is actually handling a screen share request
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=3)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            # Look for screen sharing streams
                            if 'Stream/Output/Video' in media_class:
                                app_name = props.get('application.name', '')
                                if 'portal' in app_name.lower() or 'screen' in app_name.lower():
                                    return True
            
            # For PipeWire-based screen sharing
            elif 'pipewire' in process_name or 'portal' in process_name:
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=3)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            if 'Stream/Output/Video' in media_class:
                                return True
            
            # For Hyprland screenshot/recording tools
            elif process_name in ['grim', 'slurp', 'wf-recorder']:
                # These are typically short-lived, so if they're running, they're probably active
                return True
            
            # For specific applications, be more conservative
            elif process_name in ['obs', 'zoom', 'teams']:
                # Only report as sharing if we can detect actual streams
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=3)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            app_name = props.get('application.name', '').lower()
                            if process_name in app_name:
                                return True
                
        except (json.JSONDecodeError, subprocess.TimeoutExpired):
            pass
            
        return False

    def check_location_access(self) -> List[str]:
        """Check for location access via Geoclue"""
        active_location = []
        
        try:
            # Check if geoclue is running and has active clients
            result = subprocess.run(['busctl', 'tree', 'org.freedesktop.GeoClue2'], 
                                  capture_output=True, text=True, timeout=3)
            if result.returncode == 0 and '/org/freedesktop/GeoClue2/Client' in result.stdout:
                active_location.append("Location: Active")
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
            
        return active_location

    def get_privacy_status(self) -> Dict:
        """Get comprehensive privacy status with detailed state information"""
        webcam_status = self.check_webcam_status()
        microphone_status = self.check_microphone_status()
        screen_status = self.check_screen_sharing_status()
        location_status = self.check_location_status()
        
        return {
            'webcam': webcam_status,
            'microphone': microphone_status,
            'screenshare': screen_status,
            'location': location_status
        }

    def format_output(self, status: Dict) -> Dict:
        """Format output for Waybar with state-aware icons"""
        active_indicators = []
        tooltip_lines = []
        css_classes = []
        
        # Webcam status
        webcam = status['webcam']
        if webcam['active_streams'] or webcam['devices_in_use']:
            active_indicators.append(self.icons['webcam_active'])
            css_classes.append('webcam-active')
            tooltip_lines.append("📹 WEBCAM ACTIVE:")
            for stream in webcam['active_streams']:
                tooltip_lines.append(f"  • {stream}")
            for device in webcam['devices_in_use']:
                tooltip_lines.append(f"  • {device['name']}: {device['process']}")
        elif webcam['hardware_disabled']:
            active_indicators.append(self.icons['webcam_disabled'])
            css_classes.append('webcam-disabled')
            tooltip_lines.append("📵 Camera disabled/unavailable")
        elif webcam['has_webcam'] and webcam['available_devices']:
            active_indicators.append(self.icons['webcam_available'])
            css_classes.append('webcam-available')
            tooltip_lines.append("📷 Camera available:")
            for device in webcam['available_devices']:
                tooltip_lines.append(f"  • {device['name']}")
        
        # Microphone status (always show if microphone exists)
        microphone = status['microphone']
        if microphone['has_microphone']:
            if microphone['is_muted']:
                active_indicators.append(self.icons['microphone_muted'])
                css_classes.append('microphone-muted')
                tooltip_lines.append("🔇 MICROPHONE MUTED")
            elif microphone['active_streams']:
                active_indicators.append(self.icons['microphone_active'])
                css_classes.append('microphone-active')
                tooltip_lines.append("🎤 MICROPHONE ACTIVE:")
                for stream in microphone['active_streams']:
                    tooltip_lines.append(f"  • {stream}")
            else:
                # Mic available but not in use - show this state
                active_indicators.append(self.icons['microphone_available'])
                css_classes.append('microphone-available')
                tooltip_lines.append("🎙️ Microphone available")
        else:
            active_indicators.append(self.icons['microphone_unavailable'])
            css_classes.append('microphone-unavailable')
            tooltip_lines.append("❌ No microphone detected")
        
        # Screen sharing status
        screenshare = status['screenshare']
        if screenshare['is_sharing'] and screenshare['active_sessions']:
            active_indicators.append(self.icons['screenshare_active'])
            css_classes.append('screenshare-active')
            tooltip_lines.append("🖥️ SCREEN SHARING ACTIVE:")
            for session in screenshare['active_sessions']:
                tooltip_lines.append(f"  • {session}")
        elif screenshare['ready_apps']:
            active_indicators.append(self.icons['screenshare_ready'])
            css_classes.append('screenshare-ready')
            tooltip_lines.append("💻 Screen sharing apps ready:")
            for app in screenshare['ready_apps']:
                tooltip_lines.append(f"  • {app}")
        
        # Location status (always show)
        location = status['location']
        if location['is_active'] and location['active_access']:
            active_indicators.append(self.icons['location_active'])
            css_classes.append('location-active')
            tooltip_lines.append("📍 LOCATION ACTIVE:")
            for access in location['active_access']:
                tooltip_lines.append(f"  • {access}")
        elif location['available_services']:
            # Show available location services
            active_indicators.append(self.icons['location_available'])
            css_classes.append('location-available')
            tooltip_lines.append("🗺️ Location services available:")
            for service in location['available_services']:
                tooltip_lines.append(f"  • {service}")
        else:
            # No location services detected
            active_indicators.append(self.icons['location_unavailable'])
            css_classes.append('location-unavailable')
            tooltip_lines.append("🚫 No location services detected")
        
        # Add empty lines between sections
        if tooltip_lines:
            formatted_tooltip = []
            current_section = []
            for line in tooltip_lines:
                if line.startswith(('📹', '🔇', '🎤', '🎙️', '🖥️', '💻', '📍')):
                    if current_section:
                        formatted_tooltip.extend(current_section)
                        formatted_tooltip.append("")  # Empty line between sections
                    current_section = [line]
                else:
                    current_section.append(line)
            if current_section:
                formatted_tooltip.extend(current_section)
            tooltip_text = "\n".join(formatted_tooltip).strip()
        else:
            tooltip_text = "Privacy: All quiet 🔒"
        
        # Determine overall status
        if active_indicators:
            # Show privacy concerns with appropriate urgency
            urgent_indicators = [icon for icon in active_indicators 
                               if icon in [self.icons['webcam_active'], 
                                         self.icons['microphone_active'],
                                         self.icons['screenshare_active'],
                                         self.icons['location_active']]]
            
            if urgent_indicators:
                css_class = "privacy-active"
            else:
                css_class = "privacy-ready"
            
            return {
                "text": " ".join(active_indicators),
                "tooltip": tooltip_text,
                "class": css_class
            }
        else:
            return {
                "text": "",
                "tooltip": tooltip_text,
                "class": "privacy-inactive"
            }

def main():
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "toggle-webcam":
            # Smart webcam toggle with terminal for sudo commands
            try:
                monitor = PrivacyMonitor()
                webcam_status = monitor.check_webcam_status()
                camera_module = webcam_status.get('camera_module', 'uvcvideo')
                
                if webcam_status['devices_in_use']:
                    # Camera is in use - kill the processes using it
                    killed_processes = []
                    for device_info in webcam_status['devices_in_use']:
                        try:
                            subprocess.run(['kill', device_info['pid']], capture_output=True)
                            killed_processes.append(device_info['process'])
                        except:
                            continue
                    
                    message = f"Stopped camera access: {', '.join(killed_processes)}" if killed_processes else "Camera access stopped"
                    
                elif webcam_status['hardware_disabled']:
                    # Camera is disabled - enable it in terminal
                    cmd = f"echo 'Enabling camera hardware...'; sudo modprobe {camera_module} && echo 'Camera enabled successfully!' || echo 'Failed to enable camera'"
                    if monitor.run_in_terminal(cmd, "Enable Camera"):
                        message = f"Opening terminal to enable camera ({camera_module})"
                    else:
                        message = "No terminal found - please run: sudo modprobe " + camera_module
                    
                elif webcam_status['has_webcam']:
                    # Camera available - disable it in terminal  
                    cmd = f"echo 'Disabling camera hardware...'; sudo modprobe -r {camera_module} && echo 'Camera disabled successfully!' || echo 'Failed to disable camera'"
                    if monitor.run_in_terminal(cmd, "Disable Camera"):
                        message = f"Opening terminal to disable camera ({camera_module})"
                    else:
                        message = "No terminal found - please run: sudo modprobe -r " + camera_module
                else:
                    message = "No camera detected"
                
                # Send notification and print result
                try:
                    subprocess.run(['notify-send', 'Privacy Module', message], 
                                 capture_output=True, timeout=2)
                except:
                    pass
                print(f"Privacy Module: {message}")
                
            except Exception as e:
                error_msg = f"Camera toggle failed: {str(e)}"
                try:
                    subprocess.run(['notify-send', 'Privacy Module', error_msg], 
                                 capture_output=True, timeout=2)
                except:
                    pass
                print(f"Privacy Module: {error_msg}")
            return
        elif command == "toggle-microphone":
            # Toggle microphone mute (works with PipeWire/PulseAudio compat)
            result = subprocess.run(['pactl', 'set-source-mute', '@DEFAULT_SOURCE@', 'toggle'], 
                         capture_output=True, text=True)
            
            # Check current mute status to provide feedback
            try:
                status_result = subprocess.run(['pactl', 'get-source-mute', '@DEFAULT_SOURCE@'], 
                                             capture_output=True, text=True)
                if status_result.returncode == 0:
                    is_muted = 'yes' in status_result.stdout.lower()
                    status_msg = "Microphone MUTED" if is_muted else "Microphone UNMUTED"
                    
                    # Send notification
                    try:
                        subprocess.run(['notify-send', 'Privacy Module', status_msg], 
                                     capture_output=True, timeout=2)
                    except:
                        pass
                    print(f"Privacy Module: {status_msg}")
            except:
                # Fallback message
                try:
                    subprocess.run(['notify-send', 'Privacy Module', 'Microphone toggled'], 
                                 capture_output=True, timeout=2)
                except:
                    pass
                print("Privacy Module: Microphone toggled")
            return
        elif command == "open-settings":
            # Launch settings apps in background so they stay open
            settings_options = [
                ['pavucontrol'],  # Audio settings (works for mic)
                ['alacritty', '-e', 'wpctl', 'status'],  # WirePlumber in terminal
                ['kitty', '-e', 'wpctl', 'status'],  # WirePlumber in kitty
                ['foot', '-e', 'wpctl', 'status'],  # WirePlumber in foot
                ['thunar', '/dev'],  # File manager showing /dev (for video devices)
                ['dolphin', '/dev'],
                ['nautilus', '/dev'],
                ['nemo', '/dev']
            ]
            
            for app_cmd in settings_options:
                try:
                    # Check if the command exists
                    if subprocess.run(['which', app_cmd[0]], capture_output=True).returncode == 0:
                        # Launch in background with Popen so it stays open
                        subprocess.Popen(app_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        # Also send a notification if notify-send is available
                        try:
                            subprocess.run(['notify-send', 'Privacy Settings', f'Opened {app_cmd[0]}'], 
                                         capture_output=True, timeout=1)
                        except:
                            pass
                        break
                except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
                    continue
            return
        elif command == "list-devices":
            # List audio/video devices for debugging
            print("=== Audio/Video Device Status ===")
            try:
                print("\n📊 WirePlumber Status:")
                subprocess.run(['wpctl', 'status'], timeout=5)
                
                print("\n📹 Video devices:")
                result = subprocess.run(['ls', '-la', '/dev/video*'], 
                                      capture_output=True, text=True, timeout=2)
                if result.returncode == 0:
                    print(result.stdout)
                else:
                    print("No video devices found")
                
                print("\n🔍 Processes using video devices:")
                video_devices = glob.glob('/dev/video*')
                for device in video_devices:
                    try:
                        result = subprocess.run(['lsof', device], 
                                              capture_output=True, text=True, timeout=2)
                        if result.returncode == 0 and result.stdout.strip():
                            print(f"{device}:")
                            print(result.stdout)
                        else:
                            print(f"{device}: Not in use")
                    except:
                        continue
                        
            except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
                print("❌ Error getting device information")
            return
        elif command == "debug-toggle":
            # Debug the toggle logic step by step
            print("=== Camera Toggle Debug ===")
            
            monitor = PrivacyMonitor()
            webcam_status = monitor.check_webcam_status()
            camera_module = webcam_status.get('camera_module', 'unknown')
            
            print(f"\n🔍 Current Status:")
            print(f"  Camera module: {camera_module}")
            print(f"  has_webcam: {webcam_status['has_webcam']}")
            print(f"  hardware_disabled: {webcam_status['hardware_disabled']}")
            print(f"  devices_in_use: {len(webcam_status['devices_in_use'])}")
            print(f"  available_devices: {len(webcam_status['available_devices'])}")
            
            print(f"\n🔍 Module Check:")
            try:
                result = subprocess.run(['lsmod'], capture_output=True, text=True, timeout=2)
                if result.returncode == 0:
                    if camera_module in result.stdout:
                        print(f"  ✅ {camera_module} module is loaded")
                    else:
                        print(f"  ❌ {camera_module} module is NOT loaded")
                        
                        # Show what camera modules are loaded
                        camera_modules = []
                        for line in result.stdout.split('\n'):
                            module_name = line.split()[0] if line.split() else ''
                            if any(cam in module_name for cam in ['uvc', 'gspca', 'camera', 'video']):
                                camera_modules.append(module_name)
                        
                        if camera_modules:
                            print(f"  📋 Camera-related modules found: {', '.join(camera_modules)}")
                        else:
                            print("  📋 No camera-related modules found")
                else:
                    print("  ❌ Failed to check lsmod")
            except Exception as e:
                print(f"  ❌ Error checking modules: {e}")
            
            print(f"\n🔍 Video Devices:")
            video_devices = glob.glob('/dev/video*')
            if video_devices:
                print(f"  Found {len(video_devices)} video devices:")
                for device in video_devices:
                    print(f"    • {device}")
                    
                    # Check device driver
                    try:
                        result = subprocess.run(['udevadm', 'info', '--name', device], 
                                              capture_output=True, text=True, timeout=2)
                        if result.returncode == 0:
                            for line in result.stdout.split('\n'):
                                if 'DRIVER=' in line:
                                    driver = line.split('DRIVER=')[-1].strip()
                                    print(f"      Driver: {driver}")
                                    break
                    except:
                        pass
            else:
                print("  ❌ No video devices found")
            
            print(f"\n🔍 Toggle Logic Would Choose:")
            if webcam_status['devices_in_use']:
                print("  → Kill processes using camera")
            elif webcam_status['hardware_disabled']:
                print(f"  → Enable camera hardware (modprobe {camera_module})")
            elif webcam_status['has_webcam']:
                print(f"  → Disable camera hardware (modprobe -r {camera_module})")
            else:
                print("  → No camera detected")
            
            return
            # Debug what PipeWire is telling us about video
            print("=== PipeWire Video Node Debug ===")
            
            try:
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    
                    print("\n🔍 All Video-Related Nodes:")
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            
                            if 'Video' in media_class:
                                app_name = props.get('application.name', 'N/A')
                                app_process = props.get('application.process.binary', 'N/A')
                                node_name = props.get('node.name', 'N/A')
                                node_desc = props.get('node.description', 'N/A')
                                
                                print(f"\n  Node: {node_name}")
                                print(f"    Class: {media_class}")
                                print(f"    App Name: {app_name}")
                                print(f"    App Process: {app_process}")
                                print(f"    Description: {node_desc}")
                                
                                # Show why this would/wouldn't be counted as active
                                if 'Stream/Input/Video' in media_class:
                                    if (app_name and app_name not in ['Unknown', ''] and 
                                        not app_name.startswith('v4l2_input')):
                                        print(f"    ❌ WOULD COUNT AS ACTIVE (app_name: {app_name})")
                                    elif app_process and app_process not in ['Unknown', '']:
                                        print(f"    ❌ WOULD COUNT AS ACTIVE (app_process: {app_process})")
                                    else:
                                        print(f"    ✅ CORRECTLY FILTERED OUT (hardware only)")
                                else:
                                    print(f"    ✅ NOT INPUT STREAM (ignored)")
                else:
                    print("Could not get PipeWire dump")
                    
            except Exception as e:
                print(f"Error: {e}")
            
            return
            # Detailed breakdown of what's using privacy-sensitive devices
            print("=== Who's Using Your Privacy Devices ===")
            
            # Check video devices with detailed process info
            print("\n📹 CAMERA USAGE:")
            video_devices = glob.glob('/dev/video*')
            camera_users_found = False
            
            for device in video_devices:
                try:
                    result = subprocess.run(['lsof', device], 
                                          capture_output=True, text=True, timeout=2)
                    if result.returncode == 0 and result.stdout.strip():
                        print(f"  {device}:")
                        lines = result.stdout.strip().split('\n')[1:]  # Skip header
                        for line in lines:
                            parts = line.split()
                            if len(parts) >= 2:
                                process_name = parts[0]
                                pid = parts[1]
                                user = parts[2] if len(parts) > 2 else "unknown"
                                
                                # Get more process info
                                try:
                                    cmd_result = subprocess.run(['ps', '-p', pid, '-o', 'comm,args'], 
                                                              capture_output=True, text=True, timeout=1)
                                    if cmd_result.returncode == 0:
                                        cmd_lines = cmd_result.stdout.strip().split('\n')[1:]
                                        if cmd_lines:
                                            full_cmd = cmd_lines[0]
                                            print(f"    → {process_name} (PID: {pid}, User: {user})")
                                            print(f"      Command: {full_cmd}")
                                    else:
                                        print(f"    → {process_name} (PID: {pid}, User: {user})")
                                except:
                                    print(f"    → {process_name} (PID: {pid}, User: {user})")
                                
                                camera_users_found = True
                    else:
                        print(f"  {device}: Not in use")
                except Exception as e:
                    print(f"  {device}: Error checking ({e})")
            
            if not camera_users_found:
                print("  No processes directly accessing camera devices")
            
            # Check PipeWire streams
            print("\n🎵 PIPEWIRE VIDEO STREAMS:")
            try:
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    video_streams_found = False
                    
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            
                            if 'Video' in media_class and ('Input' in media_class or 'Source' in media_class):
                                app_name = props.get('application.name', 'Unknown')
                                app_process = props.get('application.process.binary', 'Unknown')
                                app_pid = props.get('application.process.id', 'Unknown')
                                node_name = props.get('node.name', 'Unknown')
                                
                                print(f"  → App: {app_name}")
                                print(f"    Process: {app_process} (PID: {app_pid})")
                                print(f"    Node: {node_name}")
                                print(f"    Class: {media_class}")
                                print()
                                video_streams_found = True
                    
                    if not video_streams_found:
                        print("  No active video streams found in PipeWire")
                else:
                    print("  Could not access PipeWire info")
            except Exception as e:
                print(f"  Error checking PipeWire: {e}")
            
            # Check audio streams too
            print("\n🎤 MICROPHONE USAGE:")
            try:
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    audio_streams_found = False
                    
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            
                            if 'Audio' in media_class and 'Input' in media_class and 'Stream' in media_class:
                                app_name = props.get('application.name', 'Unknown')
                                app_process = props.get('application.process.binary', 'Unknown')
                                app_pid = props.get('application.process.id', 'Unknown')
                                
                                print(f"  → {app_name} ({app_process}, PID: {app_pid})")
                                audio_streams_found = True
                    
                    if not audio_streams_found:
                        print("  No active audio input streams")
                else:
                    print("  Could not access PipeWire audio info")
            except Exception as e:
                print(f"  Error checking audio: {e}")
            
            return
            # Explain what those cryptic device names mean
            print("=== Understanding Device Names ===")
            print()
            print("📹 Video Device Names Decoded:")
            print("• v4l2_input.pci-0000_00_14.0-usb-0_5_1.0")
            print("  └─ v4l2_input: Video4Linux2 input device (your webcam)")
            print("  └─ pci-0000_00_14.0: PCI bus location (USB controller)")
            print("  └─ usb-0_5_1.0: USB hub 0, port 5, device 1, interface 0")
            print()
            print("🔍 Why 'Unknown' appears:")
            print("• PipeWire detects the hardware but doesn't know which app is using it")
            print("• Some apps don't properly report their name to PipeWire")
            print("• Raw camera access shows as hardware path instead of app name")
            print()
            print("💡 To see which app is actually using your camera:")
            try:
                video_devices = glob.glob('/dev/video*')
                if video_devices:
                    print("Current camera usage:")
                    for device in video_devices:
                        try:
                            result = subprocess.run(['lsof', device], 
                                                  capture_output=True, text=True, timeout=2)
                            if result.returncode == 0 and result.stdout.strip():
                                lines = result.stdout.strip().split('\n')[1:]  # Skip header
                                for line in lines:
                                    parts = line.split()
                                    if len(parts) > 1:
                                        process_name = parts[0]
                                        pid = parts[1]
                                        print(f"  • {device}: {process_name} (PID: {pid})")
                            else:
                                print(f"  • {device}: Not in use")
                        except:
                            print(f"  • {device}: Could not check")
                else:
                    print("  No video devices found")
            except Exception as e:
                print(f"  Error checking devices: {e}")
            return
        elif command == "status":
            # Show detailed current status
            print("=== Current Privacy Status ===")
            monitor = PrivacyMonitor()
            status = monitor.get_privacy_status()
            
            # Webcam status
            webcam = status['webcam']
            camera_module = webcam.get('camera_module', 'unknown')
            
            if webcam['active_streams'] or webcam['devices_in_use']:
                print("📹 WEBCAM: ACTIVE")
                for stream in webcam['active_streams']:
                    print(f"  • {stream}")
                for device in webcam['devices_in_use']:
                    print(f"  • {device['name']}: {device['process']} (PID: {device['pid']})")
            elif webcam['hardware_disabled']:
                print("📵 WEBCAM: DISABLED/UNAVAILABLE")
                print(f"  • Camera module: {camera_module}")
                if not glob.glob('/dev/video*'):
                    print("  • No video devices found")
                else:
                    try:
                        result = subprocess.run(['lsmod'], capture_output=True, text=True, timeout=2)
                        if result.returncode == 0 and camera_module not in result.stdout:
                            print(f"  • Camera module ({camera_module}) not loaded")
                    except:
                        pass
            elif webcam['has_webcam']:
                print("📷 WEBCAM: Available but not in use")
                print(f"  • Camera module: {camera_module}")
                for device in webcam['available_devices']:
                    print(f"  • {device['name']}")
            else:
                print("📵 WEBCAM: No camera detected")
                print(f"  • Camera module checked: {camera_module}")
            
            # Microphone status
            microphone = status['microphone']
            if microphone['has_microphone']:
                if microphone['is_muted']:
                    print("🔇 MICROPHONE: MUTED")
                elif microphone['active_streams']:
                    print("🎤 MICROPHONE: ACTIVE")
                    for stream in microphone['active_streams']:
                        print(f"  • {stream}")
                else:
                    print("🎤 MICROPHONE: Available and unmuted")
                if microphone['default_source']:
                    print(f"  • Default source: {microphone['default_source']}")
            else:
                print("🎙️ MICROPHONE: Not detected")
            
            # Screen sharing status
            screenshare = status['screenshare']
            if screenshare['is_sharing']:
                print("🖥️ SCREEN SHARING: ACTIVE")
                for session in screenshare['active_sessions']:
                    print(f"  • {session}")
            elif screenshare['ready_apps']:
                print("💻 SCREEN SHARING: Apps ready")
                for app in screenshare['ready_apps']:
                    print(f"  • {app}")
            else:
                print("💻 SCREEN SHARING: Inactive")
            
            # Location status
            location = status['location']
            if location['is_active']:
                print("📍 LOCATION: ACTIVE")
                for access in location['active_access']:
                    print(f"  • {access}")
            elif location['available_services']:
                print("🗺️ LOCATION: Services available")
                for service in location['available_services']:
                    print(f"  • {service}")
            else:
                print("🚫 LOCATION: No services detected")
            
            return
        elif command == "explain-devices":
            # Explain what those cryptic device names mean
            print("=== Understanding Device Names ===")
            print()
            print("📹 Video Device Names Decoded:")
            print("• v4l2_input.pci-0000_00_14.0-usb-0_5_1.0")
            print("  └─ v4l2_input: Video4Linux2 input device (your webcam)")
            print("  └─ pci-0000_00_14.0: PCI bus location (USB controller)")
            print("  └─ usb-0_5_1.0: USB hub 0, port 5, device 1, interface 0")
            print()
            print("🔍 Why 'Unknown' appears:")
            print("• PipeWire detects the hardware but doesn't know which app is using it")
            print("• Some apps don't properly report their name to PipeWire")
            print("• Raw camera access shows as hardware path instead of app name")
            print()
            print("💡 To see which app is actually using your camera:")
            try:
                video_devices = glob.glob('/dev/video*')
                if video_devices:
                    print("Current camera usage:")
                    for device in video_devices:
                        try:
                            result = subprocess.run(['lsof', device], 
                                                  capture_output=True, text=True, timeout=2)
                            if result.returncode == 0 and result.stdout.strip():
                                lines = result.stdout.strip().split('\n')[1:]  # Skip header
                                for line in lines:
                                    parts = line.split()
                                    if len(parts) > 1:
                                        process_name = parts[0]
                                        pid = parts[1]
                                        print(f"  • {device}: {process_name} (PID: {pid})")
                            else:
                                print(f"  • {device}: Not in use")
                        except:
                            print(f"  • {device}: Could not check")
                else:
                    print("  No video devices found")
            except Exception as e:
                print(f"  Error checking devices: {e}")
            return
        elif command == "test":
            # Test all functions and show what would happen
            print("=== Privacy Module Test Mode ===")
            monitor = PrivacyMonitor()
            status = monitor.get_privacy_status()
            
            print("\n📊 Current Privacy Status:")
            for category, streams in status.items():
                print(f"  {category.title()}: {len(streams)} active")
                for stream in streams:
                    print(f"    • {stream}")
            
            print(f"\n📋 Waybar Output:")
            output = monitor.format_output(status)
            print(f"  Text: '{output['text']}'")
            print(f"  Class: {output['class']}")
            print(f"  Tooltip: {output['tooltip']}")
            
            print(f"\n🔧 Available Commands:")
            print(f"  {sys.argv[0]} status             # Show current detailed status")
            print(f"  {sys.argv[0]} who-is-using       # Detailed breakdown of what's using devices")
            print(f"  {sys.argv[0]} debug-pipewire     # Debug PipeWire video detection")
            print(f"  {sys.argv[0]} debug-toggle       # Debug webcam toggle logic")
            print(f"  {sys.argv[0]} open-settings      # Open audio settings")
            print(f"  {sys.argv[0]} toggle-microphone  # Toggle mic mute")
            print(f"  {sys.argv[0]} toggle-webcam      # Smart webcam control")
            print(f"  {sys.argv[0]} kill-camera-apps   # Kill apps using camera")
            print(f"  {sys.argv[0]} list-devices       # Show devices")
            print(f"  {sys.argv[0]} explain-devices    # Explain cryptic device names")
            print(f"  {sys.argv[0]} test               # This test mode")
            return
        elif command == "kill-camera-apps":
            # Kill applications actually using camera, not just running
            camera_apps = ['zoom', 'teams', 'discord', 'obs', 'vlc', 'skype']
            browser_apps = ['chrome', 'firefox', 'chromium', 'brave']
            killed_apps = []
            
            # Always kill dedicated video apps if running
            for app in camera_apps:
                try:
                    check_result = subprocess.run(['pgrep', '-f', app], capture_output=True)
                    if check_result.returncode == 0:
                        kill_result = subprocess.run(['pkill', '-f', app], capture_output=True)
                        if kill_result.returncode == 0:
                            killed_apps.append(app)
                except subprocess.CalledProcessError:
                    continue
            
            # Only kill browsers if they're actually using video devices
            for browser in browser_apps:
                try:
                    # Check if browser is running
                    check_result = subprocess.run(['pgrep', '-f', browser], capture_output=True)
                    if check_result.returncode == 0:
                        # Check if this browser is actually using video
                        is_using_camera = False
                        
                        # Method 1: Check PipeWire streams
                        try:
                            result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=3)
                            if result.returncode == 0:
                                data = json.loads(result.stdout)
                                for item in data:
                                    if item.get('type') == 'PipeWire:Interface:Node':
                                        props = item.get('info', {}).get('props', {})
                                        app_name = props.get('application.name', '').lower()
                                        media_class = props.get('media.class', '')
                                        if browser.lower() in app_name and 'Video' in media_class:
                                            is_using_camera = True
                                            break
                        except:
                            pass
                        
                        # Method 2: Check if browser process has video device open
                        if not is_using_camera:
                            video_devices = glob.glob('/dev/video*')
                            for device in video_devices:
                                try:
                                    result = subprocess.run(['lsof', device], 
                                                          capture_output=True, text=True, timeout=1)
                                    if result.returncode == 0 and browser in result.stdout.lower():
                                        is_using_camera = True
                                        break
                                except:
                                    continue
                        
                        # Only kill if actually using camera
                        if is_using_camera:
                            kill_result = subprocess.run(['pkill', '-f', browser], capture_output=True)
                            if kill_result.returncode == 0:
                                killed_apps.append(f"{browser} (was using camera)")
                        
                except subprocess.CalledProcessError:
                    continue
            
            # Provide feedback about what was killed
            if killed_apps:
                message = f"Killed: {', '.join(killed_apps)}"
                try:
                    subprocess.run(['notify-send', 'Privacy Module', message], 
                                 capture_output=True, timeout=2)
                except:
                    pass
                print(f"Privacy Module: {message}")
            else:
                message = "No apps using camera found running"
                try:
                    subprocess.run(['notify-send', 'Privacy Module', message], 
                                 capture_output=True, timeout=2)
                except:
                    pass
                print(f"Privacy Module: {message}")
            return
        elif command == "debug-pipewire":
            # Debug what PipeWire is telling us about video
            print("=== PipeWire Video Node Debug ===")
            
            try:
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    
                    print("\n🔍 All Video-Related Nodes:")
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            
                            if 'Video' in media_class:
                                app_name = props.get('application.name', 'N/A')
                                app_process = props.get('application.process.binary', 'N/A')
                                node_name = props.get('node.name', 'N/A')
                                node_desc = props.get('node.description', 'N/A')
                                
                                print(f"\n  Node: {node_name}")
                                print(f"    Class: {media_class}")
                                print(f"    App Name: {app_name}")
                                print(f"    App Process: {app_process}")
                                print(f"    Description: {node_desc}")
                                
                                # Show why this would/wouldn't be counted as active
                                if 'Stream/Input/Video' in media_class:
                                    if (app_name and app_name not in ['Unknown', ''] and 
                                        not app_name.startswith('v4l2_input')):
                                        print(f"    ❌ WOULD COUNT AS ACTIVE (app_name: {app_name})")
                                    elif app_process and app_process not in ['Unknown', '']:
                                        print(f"    ❌ WOULD COUNT AS ACTIVE (app_process: {app_process})")
                                    else:
                                        print(f"    ✅ CORRECTLY FILTERED OUT (hardware only)")
                                else:
                                    print(f"    ✅ NOT INPUT STREAM (ignored)")
                else:
                    print("Could not get PipeWire dump")
                    
            except Exception as e:
                print(f"Error: {e}")
            
            return
        elif command == "who-is-using":
            # Detailed breakdown of what's using privacy-sensitive devices
            print("=== Who's Using Your Privacy Devices ===")
            
            # Check video devices with detailed process info
            print("\n📹 CAMERA USAGE:")
            video_devices = glob.glob('/dev/video*')
            camera_users_found = False
            
            for device in video_devices:
                try:
                    result = subprocess.run(['lsof', device], 
                                          capture_output=True, text=True, timeout=2)
                    if result.returncode == 0 and result.stdout.strip():
                        print(f"  {device}:")
                        lines = result.stdout.strip().split('\n')[1:]  # Skip header
                        for line in lines:
                            parts = line.split()
                            if len(parts) >= 2:
                                process_name = parts[0]
                                pid = parts[1]
                                user = parts[2] if len(parts) > 2 else "unknown"
                                
                                # Get more process info
                                try:
                                    cmd_result = subprocess.run(['ps', '-p', pid, '-o', 'comm,args'], 
                                                              capture_output=True, text=True, timeout=1)
                                    if cmd_result.returncode == 0:
                                        cmd_lines = cmd_result.stdout.strip().split('\n')[1:]
                                        if cmd_lines:
                                            full_cmd = cmd_lines[0]
                                            print(f"    → {process_name} (PID: {pid}, User: {user})")
                                            print(f"      Command: {full_cmd}")
                                    else:
                                        print(f"    → {process_name} (PID: {pid}, User: {user})")
                                except:
                                    print(f"    → {process_name} (PID: {pid}, User: {user})")
                                
                                camera_users_found = True
                    else:
                        print(f"  {device}: Not in use")
                except Exception as e:
                    print(f"  {device}: Error checking ({e})")
            
            if not camera_users_found:
                print("  No processes directly accessing camera devices")
            
            # Check PipeWire streams
            print("\n🎵 PIPEWIRE VIDEO STREAMS:")
            try:
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    video_streams_found = False
                    
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            
                            if 'Video' in media_class and ('Input' in media_class or 'Source' in media_class):
                                app_name = props.get('application.name', 'Unknown')
                                app_process = props.get('application.process.binary', 'Unknown')
                                app_pid = props.get('application.process.id', 'Unknown')
                                node_name = props.get('node.name', 'Unknown')
                                
                                print(f"  → App: {app_name}")
                                print(f"    Process: {app_process} (PID: {app_pid})")
                                print(f"    Node: {node_name}")
                                print(f"    Class: {media_class}")
                                print()
                                video_streams_found = True
                    
                    if not video_streams_found:
                        print("  No active video streams found in PipeWire")
                else:
                    print("  Could not access PipeWire info")
            except Exception as e:
                print(f"  Error checking PipeWire: {e}")
            
            # Check audio streams too
            print("\n🎤 MICROPHONE USAGE:")
            try:
                result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    audio_streams_found = False
                    
                    for item in data:
                        if item.get('type') == 'PipeWire:Interface:Node':
                            props = item.get('info', {}).get('props', {})
                            media_class = props.get('media.class', '')
                            
                            if 'Audio' in media_class and 'Input' in media_class and 'Stream' in media_class:
                                app_name = props.get('application.name', 'Unknown')
                                app_process = props.get('application.process.binary', 'Unknown')
                                app_pid = props.get('application.process.id', 'Unknown')
                                
                                print(f"  → {app_name} ({app_process}, PID: {app_pid})")
                                audio_streams_found = True
                    
                    if not audio_streams_found:
                        print("  No active audio input streams")
                else:
                    print("  Could not access PipeWire audio info")
            except Exception as e:
                print(f"  Error checking audio: {e}")
            
            return

    # Default: get status
    monitor = PrivacyMonitor()
    status = monitor.get_privacy_status()
    output = monitor.format_output(status)
    
    print(json.dumps(output))

if __name__ == "__main__":
    main()
