#!/usr/bin/env python3
"""
Hardware/Device Privacy Module for Waybar
Monitors USB devices and Bluetooth connections
"""

import json
import subprocess
import sys
import time
import glob
import os
from typing import Dict, List

# Import password prompt helper
try:
    from password_prompt import run_sudo_command
except ImportError:
    def run_sudo_command(command, title, description):
        """Fallback if password_prompt module not available"""
        try:
            result = subprocess.run(command, timeout=30)
            return result.returncode == 0
        except:
            return False

class HardwarePrivacy:
    def __init__(self):
        self.icons = {
            'usb_storage': '💾',
            'usb_device': '🔌',
            'bluetooth_idle': '🔷',
            'bluetooth_discoverable': '📡',
            'bluetooth_connected': '🔵',
            'bluetooth_off': '🔴',
            'device_warning': '⚠️'
        }
        self._cache = {}
        self._cache_timeout = 2.0  # Hardware changes less frequently

    def _get_cached_or_run(self, key: str, func, *args, **kwargs):
        now = time.time()
        if key in self._cache:
            result, timestamp = self._cache[key]
            if now - timestamp < self._cache_timeout:
                return result
        
        result = func(*args, **kwargs)
        self._cache[key] = (result, now)
        return result

    def _run_command_fast(self, cmd: List[str], timeout: float = 1.0) -> tuple:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return result.returncode, result.stdout, result.stderr
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return -1, "", "timeout/not found"

    def _find_hidraw_devices(self) -> Dict[str, str]:
        """Find hidraw devices and map them to USB product names via sysfs"""
        usb_to_hidraw = {}
        
        try:
            # Get all hidraw devices
            hidraw_paths = glob.glob('/sys/class/hidraw/hidraw*')
            
            for hidraw_path in hidraw_paths:
                hidraw_name = os.path.basename(hidraw_path)
                hidraw_dev_path = f"/dev/{hidraw_name}"
                
                try:
                    # Follow device symlink to find parent USB device
                    device_link = os.path.join(hidraw_path, 'device')
                    if not os.path.exists(device_link):
                        continue
                        
                    real_device_path = os.path.realpath(device_link)
                    
                    # Walk up the path to find USB device
                    path_parts = real_device_path.split('/')
                    usb_product = None
                    
                    for i in range(len(path_parts) - 1, 0, -1):
                        test_path = '/'.join(path_parts[:i+1])
                        product_file = os.path.join(test_path, 'product')
                        
                        if os.path.exists(product_file):
                            try:
                                with open(product_file, 'r') as f:
                                    usb_product = f.read().strip()
                                    break
                            except:
                                continue
                    
                    if usb_product:
                        # Clean up product name to match USB enumeration
                        usb_product = usb_product[:40]
                        usb_to_hidraw[usb_product] = hidraw_dev_path
                        
                except Exception:
                    continue
                    
        except Exception:
            pass
            
        return usb_to_hidraw

    def _get_device_batteries(self) -> Dict:
        """Check battery levels for connected devices using upower"""
        batteries = {}
        
        try:
            # Get all power devices
            returncode, stdout, _ = self._run_command_fast(['upower', '-e'], 2.0)
            if returncode != 0:
                return batteries
                
            device_paths = [line.strip() for line in stdout.split('\n') if line.strip()]
            
            for device_path in device_paths:
                # Skip laptop battery, AC adapter, and display device
                if any(skip in device_path for skip in ['battery_BAT', 'line_power', 'DisplayDevice']):
                    continue
                    
                # Focus on wireless device batteries (hidpp, bluetooth, mouse, keyboard)
                if any(device_type in device_path.lower() for device_type in ['hidpp_battery', 'bluetooth', 'mouse', 'keyboard']):
                    # Get device info
                    returncode, device_info, _ = self._run_command_fast(['upower', '-i', device_path], 1.5)
                    if returncode == 0:
                        device_name = ""
                        battery_level = None
                        device_type = ""
                        
                        for line in device_info.split('\n'):
                            line = line.strip()
                            if line.startswith('model:'):
                                device_name = line.split(':', 1)[1].strip()
                            elif line.startswith('serial:') and not device_name:
                                # Fallback to serial if no model name
                                device_name = line.split(':', 1)[1].strip()
                            elif line.startswith('percentage:'):
                                percentage_line = line.split(':', 1)[1].strip()
                                if 'should be ignored' not in percentage_line:
                                    try:
                                        battery_level = int(percentage_line.replace('%', ''))
                                    except (ValueError, IndexError):
                                        pass
                            elif line.startswith('battery-level:'):
                                # Use battery-level as fallback for devices that don't report percentage
                                level_text = line.split(':', 1)[1].strip()
                                if battery_level is None:
                                    level_map = {
                                        'full': 100, 'high': 75, 'normal': 50, 
                                        'low': 25, 'critical': 10, 'empty': 0
                                    }
                                    battery_level = level_map.get(level_text, None)
                            elif line.startswith('type:'):
                                device_type = line.split(':', 1)[1].strip().lower()
                            elif line.strip() in ['mouse', 'keyboard', 'tablet', 'headset']:
                                # Sometimes device type appears on its own line
                                if not device_type:
                                    device_type = line.strip()
                        
                        # Use path-based name if no model found
                        if not device_name:
                            if 'hidpp_battery' in device_path:
                                device_name = f"Wireless Device {device_path.split('_')[-1]}"
                            else:
                                device_name = device_path.split('/')[-1]
                        
                        if battery_level is not None and device_name:
                            # Clean up device name
                            device_name = device_name[:25]  # Limit length
                            batteries[device_name] = {
                                'level': battery_level,
                                'type': device_type if device_type else 'wireless'
                            }
                            
        except Exception:
            pass
            
        return batteries

    def _get_battery_icon(self, level: int) -> str:
        """Get battery icon based on level"""
        if level >= 90:
            return "🔋"
        elif level >= 75:
            return "🔋"
        elif level >= 50:
            return "🔋"
        elif level >= 25:
            return "🪫"
        else:
            return "🪫"

    def _is_usb_device(self, device_name):
        """Check if a device is USB connected"""
        try:
            # Check if removable
            with open(f'/sys/block/{device_name}/removable', 'r') as f:
                if f.read().strip() == '1':
                    return True
        except:
            pass
            
        try:
            # Check if device path contains USB
            import os
            device_path = os.readlink(f'/sys/block/{device_name}')
            return 'usb' in device_path.lower()
        except:
            pass
            
        return False

    def _interactive_mount(self):
        """Show rofi/dmenu to select drive to mount"""
        # Get unmounted devices
        returncode, stdout, _ = self._run_command_fast(['lsblk', '-J', '-o', 'NAME,MOUNTPOINT,TYPE,FSTYPE,SIZE'], 2.0)
        if returncode != 0:
            subprocess.run(['notify-send', 'Hardware Privacy', 'Failed to list block devices'])
            return
            
        try:
            import json as json_module
            data = json_module.loads(stdout)
            unmounted_devices = []
            
            for device in data['blockdevices']:
                # Skip non-disk devices and swap
                if device['type'] != 'disk' or device.get('fstype') == 'swap':
                    continue
                    
                device_name = device['name']
                is_usb = self._is_usb_device(device_name)
                
                if device.get('children'):
                    for partition in device['children']:
                        mount_point = partition.get('mountpoint')
                        fstype = partition.get('fstype')
                        
                        # Include if USB and has filesystem but not mounted
                        if is_usb and fstype and not mount_point:
                            size = partition.get('size', 'Unknown')
                            unmounted_devices.append(f"/dev/{partition['name']} ({size}, {fstype})")
                elif device.get('fstype') and not device.get('mountpoint'):
                    # Whole disk with filesystem, not partitioned
                    if is_usb:
                        size = device.get('size', 'Unknown')
                        fstype = device.get('fstype', 'Unknown')
                        unmounted_devices.append(f"/dev/{device_name} ({size}, {fstype})")
            
            if not unmounted_devices:
                subprocess.run(['notify-send', 'Hardware Privacy', 'No unmounted USB drives found'])
                return
            
            selector_cmd = ['rofi', '-dmenu', '-p', 'Mount drive:']
            result = subprocess.run(selector_cmd, input='\n'.join(unmounted_devices), 
                                 text=True, capture_output=True, timeout=30)
            
            if result.returncode == 0 and result.stdout.strip():
                selected = result.stdout.strip()
                device = selected.split()[0]  # Extract device path
                self._mount_specific_device(device)
                subprocess.run(['notify-send', 'Hardware Privacy', f'Mounting {device}...'])
                    
        except Exception as e:
            subprocess.run(['notify-send', 'Hardware Privacy', f'Error: {e}'])

    def _interactive_unmount(self):
        """Show rofi/dmenu to select drive to unmount"""
        returncode, stdout, _ = self._run_command_fast(['findmnt', '-J', '-t', 'vfat,ntfs,ext4,exfat'], 2.0)
        if returncode != 0:
            subprocess.run(['notify-send', 'Hardware Privacy', 'No mounted storage devices found'])
            return
            
        try:
            import json as json_module
            data = json_module.loads(stdout)
            usb_mounts = self._find_usb_mounts(data['filesystems'])
            
            if not usb_mounts:
                subprocess.run(['notify-send', 'Hardware Privacy', 'No mounted USB drives found'])
                return
            
            selector_cmd = ['rofi', '-dmenu', '-p', 'Unmount drive:']
            result = subprocess.run(selector_cmd, input='\n'.join(usb_mounts), 
                                 text=True, capture_output=True, timeout=30)

            if result.returncode == 0 and result.stdout.strip():
                selected = result.stdout.strip()
                mount_point = selected.split(' (')[0]  # Extract mount point before parentheses
                self._unmount_specific_device(mount_point)
                subprocess.run(['notify-send', 'Hardware Privacy', f'Unmounting {mount_point}...'])
                    
        except Exception as e:
            subprocess.run(['notify-send', 'Hardware Privacy', f'Error: {e}'])

    def _interactive_hidraw_chmod(self):
        """Show rofi/dmenu to select input device hidraw to chmod"""
        usb_to_hidraw = self._find_hidraw_devices()
        
        if not usb_to_hidraw:
            subprocess.run(['notify-send', 'Hardware Privacy', 'No USB input hidraw devices found'])
            return
        
        # Format as "Device Name → /dev/hidrawX"
        device_options = []
        for usb_name, hidraw_path in usb_to_hidraw.items():
            device_options.append(f"{usb_name} → {hidraw_path}")
        
        selector_cmd = ['rofi', '-dmenu', '-p', 'Grant access to input device:']
        result = subprocess.run(selector_cmd, input='\n'.join(device_options), 
                             text=True, capture_output=True, timeout=30)
        
        if result.returncode == 0 and result.stdout.strip():
            selected = result.stdout.strip()
            # Extract hidraw path
            hidraw_path = selected.split(' → ')[-1]
            self._chmod_hidraw_device(hidraw_path)

    def _chmod_hidraw_device(self, hidraw_path: str):
        """Change permissions on hidraw device"""
        success = run_sudo_command(
            ['chmod', 'a+rw', hidraw_path],
            f"Grant Access to {hidraw_path}",
            f"Allow read/write access to HID device: {os.path.basename(hidraw_path)}"
        )
        
        if success:
            subprocess.run(['notify-send', 'Hardware Privacy', 
                         f'✅ Granted access to {hidraw_path}'], capture_output=True)
        else:
            subprocess.run(['notify-send', 'Hardware Privacy', 
                         f'❌ Failed to grant access to {hidraw_path}'], capture_output=True)

    def _find_usb_mounts(self, filesystems):
        """Recursively find USB mounts in filesystem tree"""
        usb_mounts = []
        
        def search_tree(fs_list):
            for mount in fs_list:
                target = mount['target']
                source = mount['source']
                
                # Check if this is a USB mount
                is_usb_mount = any(usb_path in target for usb_path in ['/run/media/', '/media/', '/mnt/'])
                is_usb = False
                
                if source.startswith('/dev/sd'):
                    device_name = source.split('/')[2][:3]  # e.g., sda from /dev/sda1
                    is_usb = self._is_usb_device(device_name)
                
                if is_usb_mount or is_usb:
                    usb_mounts.append(f"{target} ({source})")
                
                # Recursively search children
                if mount.get('children'):
                    search_tree(mount['children'])
        
        search_tree(filesystems)
        return usb_mounts

    def _list_unmounted_devices(self):
        """List available USB storage devices that can be mounted"""
        returncode, stdout, _ = self._run_command_fast(['lsblk', '-J', '-o', 'NAME,MOUNTPOINT,TYPE,FSTYPE,SIZE'], 2.0)
        if returncode != 0:
            print("Failed to list block devices")
            return
            
        try:
            import json as json_module
            data = json_module.loads(stdout)
            unmounted_devices = []
            
            for device in data['blockdevices']:
                # Look for USB devices (usually sdb, sdc, etc., not sda which is typically internal)
                if device['name'].startswith('sd') and device['name'] != 'sda':
                    if device.get('children'):
                        for partition in device['children']:
                            if partition.get('fstype') and not partition.get('mountpoint'):
                                size = partition.get('size', 'Unknown')
                                fstype = partition.get('fstype', 'Unknown')
                                unmounted_devices.append({
                                    'device': f"/dev/{partition['name']}",
                                    'size': size,
                                    'fstype': fstype
                                })
                    elif device.get('fstype') and not device.get('mountpoint'):
                        size = device.get('size', 'Unknown')
                        fstype = device.get('fstype', 'Unknown')
                        unmounted_devices.append({
                            'device': f"/dev/{device['name']}",
                            'size': size,
                            'fstype': fstype
                        })
            
            if not unmounted_devices:
                print("No unmounted USB storage devices found")
                return
                
            print("=== Unmounted USB Storage Devices ===")
            for dev in unmounted_devices:
                print(f"💿 {dev['device']} ({dev['size']}, {dev['fstype']})")
                print(f"   To mount: denv-shell hardware_privacy mount-storage {dev['device']}")
                print()
                    
        except Exception as e:
            print(f"Error parsing device information: {e}")

    def _list_mounted_devices(self):
        """List mounted USB storage devices that can be unmounted"""
        returncode, stdout, _ = self._run_command_fast(['findmnt', '-J', '-t', 'vfat,ntfs,ext4,exfat'], 2.0)
        if returncode != 0:
            print("No mounted storage devices found")
            return
            
        try:
            import json as json_module
            data = json_module.loads(stdout)
            usb_mounts = []
            
            for mount in data['filesystems']:
                target = mount['target']
                source = mount['source']
                # Look for USB devices (typically in /media or /mnt, or devices like /dev/sdb*)
                if ('/media' in target or '/mnt' in target or 
                    (source.startswith('/dev/sd') and not source.startswith('/dev/sda'))):
                    usb_mounts.append((source, target))
            
            if not usb_mounts:
                print("No mounted USB storage devices found")
                return
                
            print("=== Mounted USB Storage Devices ===")
            for source, target in usb_mounts:
                print(f"📤 {source} -> {target}")
                print(f"   To unmount: denv-shell hardware_privacy unmount-storage {target}")
                print()
                    
        except Exception as e:
            print(f"Error parsing mount information: {e}")

    def _list_hidraw_devices(self):
        """List hidraw devices and their permissions"""
        all_hidraw = self._get_all_hidraw_devices()
        usb_to_hidraw = self._find_hidraw_devices()
        
        # Create reverse mapping for display
        hidraw_to_usb = {v: k for k, v in usb_to_hidraw.items()}
        
        if not all_hidraw:
            print("No hidraw devices found")
            return
        
        print("=== HID Raw Devices ===")
        for hidraw_path in all_hidraw:
            try:
                # Check current permissions
                stat_info = os.stat(hidraw_path)
                perms = oct(stat_info.st_mode)[-3:]
                
                usb_device = hidraw_to_usb.get(hidraw_path, "Non-USB device")
                print(f"🔌 {hidraw_path} (permissions: {perms})")
                print(f"   USB Device: {usb_device}")
                print(f"   To grant access: denv-shell hardware_privacy chmod-hidraw {hidraw_path}")
                print()
            except Exception as e:
                print(f"🔌 {hidraw_path} (error reading permissions: {e})")
                print()

    def _mount_specific_device(self, device):
        """Mount a specific device"""
        mount_point = f"/media/{device.split('/')[-1]}"
        
        # Create mount point first
        mkdir_success = run_sudo_command(
            ['mkdir', '-p', mount_point],
            f"Create Mount Point",
            f"Create directory: {mount_point}"
        )
        
        if mkdir_success:
            # Mount the device
            mount_success = run_sudo_command(
                ['mount', device, mount_point],
                f"Mount {device}",
                f"Mount storage device {device} to {mount_point}"
            )
            
            if mount_success:
                subprocess.run(['notify-send', 'Hardware Privacy', f'✅ Mounted {device} to {mount_point}'], capture_output=True)
            else:
                # Clean up mount point if mount failed
                subprocess.run(['sudo', 'rmdir', mount_point], capture_output=True, timeout=2)
                subprocess.run(['notify-send', 'Hardware Privacy', f'❌ Failed to mount {device}'], capture_output=True)
        else:
            subprocess.run(['notify-send', 'Hardware Privacy', f'❌ Failed to create mount point'], capture_output=True)

    def _unmount_specific_device(self, mount_point):
        """Unmount a specific device"""
        success = run_sudo_command(
            ['umount', mount_point],
            f"Unmount {mount_point}",
            f"Unmount storage device from {mount_point}"
        )
        
        if success:
            subprocess.run(['notify-send', 'Hardware Privacy', f'✅ Unmounted {mount_point}'], capture_output=True)
            # Clean up mount point if it's in /media
            if '/media' in mount_point:
                subprocess.run(['sudo', 'rmdir', mount_point], capture_output=True, timeout=2)
        else:
            subprocess.run(['notify-send', 'Hardware Privacy', f'❌ Failed to unmount {mount_point}'], capture_output=True)

    def check_usb_devices(self) -> Dict:
        return self._get_cached_or_run('usb', self._check_usb_impl)

    def _check_usb_impl(self) -> Dict:
        status = {
            'storage_devices': [],
            'input_devices': [],
            'input_hidraw': {},  # New: maps device name to hidraw path
            'camera_devices': [],
            'bluetooth_devices': [],
            'audio_devices': [],
            'unknown_devices': [],
            'total_count': 0,
            'mounted_storage': [],
            'device_batteries': {}
        }

        # Get USB product name to hidraw mapping
        usb_to_hidraw = self._find_hidraw_devices()

        # Use usb-devices for better device information
        returncode, stdout, _ = self._run_command_fast(['usb-devices'], 3.0)
        if returncode == 0:
            devices = stdout.split('\n\n')  # Devices are separated by blank lines
            
            for device_block in devices:
                if not device_block.strip():
                    continue
                    
                lines = device_block.split('\n')
                device_class = ""
                driver = ""
                product = ""
                manufacturer = ""
                
                # Parse device information
                for line in lines:
                    line = line.strip()
                    if line.startswith('D:') and 'Cls=' in line:
                        # Extract device class: Cls=08(stor.) -> stor
                        cls_match = line.split('Cls=')[1].split('(')[1].split(')')[0] if 'Cls=' in line else ""
                        device_class = cls_match
                    elif line.startswith('I:') and 'Driver=' in line:
                        # Extract driver
                        driver = line.split('Driver=')[1] if 'Driver=' in line else ""
                    elif line.startswith('S:  Product='):
                        product = line.split('S:  Product=')[1].strip()
                    elif line.startswith('S:  Manufacturer='):
                        manufacturer = line.split('S:  Manufacturer=')[1].strip()
                
                # Skip hubs and host controllers
                if device_class == 'hub' or 'Host Controller' in product:
                    continue
                    
                # Use product name, fallback to manufacturer if needed
                device_name = product if product else manufacturer
                if not device_name:
                    device_name = f"Unknown device ({device_class})"
                    
                device_name = device_name[:40]  # Limit length
                status['total_count'] += 1
                
                # Categorize by device class and driver
                if device_class == 'stor' or driver == 'uas':
                    status['storage_devices'].append(device_name)
                elif device_class == 'HID' or driver == 'usbhid':
                    status['input_devices'].append(device_name)
                    # Map to hidraw device using actual USB product name correlation
                    if device_name in usb_to_hidraw:
                        status['input_hidraw'][device_name] = usb_to_hidraw[device_name]
                elif device_class == 'video' or driver == 'uvcvideo':
                    status['camera_devices'].append(device_name)
                elif device_class == 'wlcon' or driver == 'btusb':
                    status['bluetooth_devices'].append(device_name)
                elif device_class in ['audio', 'sound'] or driver in ['snd-usb-audio']:
                    status['audio_devices'].append(device_name)
                else:
                    status['unknown_devices'].append(device_name)

        # Check mounted storage quickly
        returncode, stdout, _ = self._run_command_fast(['findmnt', '-t', 'vfat,ntfs,ext4,exfat', '-n'], 1.0)
        if returncode == 0:
            for line in stdout.split('\n'):
                if line.strip() and ('/media' in line or '/mnt' in line):
                    mount_point = line.split()[0] if line.split() else ''
                    if mount_point:
                        status['mounted_storage'].append(mount_point)

        # Check for USB device batteries
        status['device_batteries'] = self._get_device_batteries()

        return status

    def check_bluetooth_status(self) -> Dict:
        return self._get_cached_or_run('bluetooth', self._check_bluetooth_impl)

    def _check_bluetooth_impl(self) -> Dict:
        status = {
            'enabled': False,
            'discoverable': False,
            'connected_devices': [],
            'paired_count': 0,
            'adapter_present': False,
            'device_batteries': {}
        }

        # Quick Bluetooth adapter check
        returncode, stdout, _ = self._run_command_fast(['bluetoothctl', 'list'], 1.0)
        if returncode == 0 and stdout.strip():
            status['adapter_present'] = True
        else:
            return status  # No Bluetooth adapter

        # Check Bluetooth status
        returncode, stdout, _ = self._run_command_fast(['bluetoothctl', 'show'], 2.0)
        if returncode == 0:
            output = stdout.lower()
            status['enabled'] = 'powered: yes' in output
            status['discoverable'] = 'discoverable: yes' in output
            
            if status['enabled']:
                # Quick connected device check
                returncode, stdout, _ = self._run_command_fast(['bluetoothctl', 'devices', 'Connected'], 1.5)
                if returncode == 0:
                    connected_lines = [line for line in stdout.split('\n') if line.strip() and 'Device' in line]
                    for line in connected_lines:
                        device_info = line.replace('Device ', '').strip()
                        if device_info:
                            # Extract device name (MAC and name)
                            parts = device_info.split(' ', 1)
                            if len(parts) > 1:
                                device_name = parts[1][:30]  # Limit display length
                            else:
                                device_name = parts[0][:30]
                            status['connected_devices'].append(device_name)

                # Quick paired device count
                returncode, stdout, _ = self._run_command_fast(['bluetoothctl', 'devices'], 1.0)
                if returncode == 0:
                    status['paired_count'] = len([line for line in stdout.split('\n') if line.strip() and 'Device' in line])

        # Check battery levels for connected devices
        if status['connected_devices']:
            status['device_batteries'] = self._get_device_batteries()

        return status

    def check_recent_connections(self) -> Dict:
        return self._get_cached_or_run('recent', self._check_recent_impl)

    def _check_recent_impl(self) -> Dict:
        status = {
            'recent_usb': [],
            'recent_bluetooth': []
        }

        # Check dmesg for recent USB events (last 20 lines)
        try:
            returncode, stdout, _ = self._run_command_fast(['dmesg', '--time-format=reltime'], 1.0)
            if returncode == 0:
                lines = stdout.split('\n')
                for line in reversed(lines[-20:]):
                    if 'USB' in line and any(event in line for event in ['disconnect', 'connect', 'new']):
                        # Extract relevant info
                        if 'connect' in line or 'new' in line:
                            status['recent_usb'].append("USB device connected")
                        elif 'disconnect' in line:
                            status['recent_usb'].append("USB device disconnected")
                        
                        if len(status['recent_usb']) >= 3:  # Limit to last 3 events
                            break
        except:
            pass

        return status

    def get_status(self) -> Dict:
        return {
            'usb': self.check_usb_devices(),
            'bluetooth': self.check_bluetooth_status(),
            'recent': self.check_recent_connections()
        }

    def format_output(self, status: Dict) -> Dict:
        active_indicators = []
        tooltip_lines = []
        css_classes = []

        usb = status['usb']
        bluetooth = status['bluetooth']
        recent = status['recent']

        # USB Status - Show detailed device info in tooltip
        has_usb_devices = usb['total_count'] > 0
        has_storage = usb['storage_devices'] or usb['mounted_storage']
        
        if has_storage:
            active_indicators.append(self.icons['usb_storage'])
            css_classes.append('usb-storage')
        elif usb['total_count'] > 2:  # More than just basic devices
            active_indicators.append(self.icons['usb_device'])
            css_classes.append('usb-devices')

        # Always show USB device details if any devices present
        if has_usb_devices:
            tooltip_lines.append(f"🔌 USB DEVICES: {usb['total_count']} total")
            
            # Storage devices
            if usb['storage_devices']:
                tooltip_lines.append("  💾 Storage:")
                for device in usb['storage_devices'][:3]:
                    tooltip_lines.append(f"    • {device}")
                if len(usb['storage_devices']) > 3:
                    tooltip_lines.append(f"    • +{len(usb['storage_devices']) - 3} more")
            
            # Mounted storage
            if usb['mounted_storage']:
                tooltip_lines.append("  📁 Mounted:")
                for mount in usb['mounted_storage'][:3]:
                    tooltip_lines.append(f"    • {mount}")
                if len(usb['mounted_storage']) > 3:
                    tooltip_lines.append(f"    • +{len(usb['mounted_storage']) - 3} more")
            
            # Input devices with hidraw paths
            if usb['input_devices']:
                tooltip_lines.append("  ⌨️ Input:")
                for device in usb['input_devices'][:3]:
                    hidraw_info = ""
                    if device in usb['input_hidraw']:
                        hidraw_info = f" → {usb['input_hidraw'][device]}"
                    tooltip_lines.append(f"    • {device}{hidraw_info}")
                if len(usb['input_devices']) > 3:
                    tooltip_lines.append(f"    • +{len(usb['input_devices']) - 3} more")
            
            # Unknown devices
            if usb['unknown_devices']:
                tooltip_lines.append("  ❓ Other:")
                for device in usb['unknown_devices'][:3]:
                    tooltip_lines.append(f"    • {device}")
                if len(usb['unknown_devices']) > 3:
                    tooltip_lines.append(f"    • +{len(usb['unknown_devices']) - 3} more")

        # Bluetooth Status
        if not bluetooth['adapter_present']:
            pass  # No Bluetooth adapter, don't show anything
        elif bluetooth['discoverable']:
            active_indicators.append(self.icons['bluetooth_discoverable'])
            css_classes.append('bluetooth-discoverable')
            if tooltip_lines:
                tooltip_lines.append("")  # Separator
            tooltip_lines.append("📡 BLUETOOTH: Discoverable")
        elif bluetooth['connected_devices']:
            active_indicators.append(self.icons['bluetooth_connected'])
            css_classes.append('bluetooth-connected')
            if tooltip_lines:
                tooltip_lines.append("")  # Separator
            tooltip_lines.append(f"🔵 BLUETOOTH: {len(bluetooth['connected_devices'])} connected")
            for device in bluetooth['connected_devices'][:2]:
                battery_info = ""
                if device in bluetooth.get('device_batteries', {}):
                    battery_level = bluetooth['device_batteries'][device]['level']
                    battery_info = f" {self._get_battery_icon(battery_level)}{battery_level}%"
                tooltip_lines.append(f"  • {device}{battery_info}")
                
        elif bluetooth['enabled']:
            active_indicators.append(self.icons['bluetooth_idle'])
            css_classes.append('bluetooth-idle')
            if tooltip_lines:
                tooltip_lines.append("")  # Separator
            tooltip_lines.append(f"🔷 BLUETOOTH: Ready ({bluetooth['paired_count']} paired)")
        elif not bluetooth['enabled'] and bluetooth['adapter_present']:
            active_indicators.append(self.icons['bluetooth_off'])
            css_classes.append('bluetooth-off')

        # Recent activity
        if recent['recent_usb']:
            if tooltip_lines:
                tooltip_lines.append("")  # Separator
            tooltip_lines.append("Recent USB activity:")
            for event in recent['recent_usb'][:2]:
                tooltip_lines.append(f"  • {event}")

        # Security warnings
        if bluetooth['discoverable']:
            css_classes.append('security-warning')
        if len(usb['unknown_devices']) > 3:
            css_classes.append('device-warning')

        tooltip_text = "\n".join(tooltip_lines) if tooltip_lines else "Hardware: Secure 🔒"
        
        return {
            "text": " ".join(active_indicators) if active_indicators else "🔒",
            "tooltip": tooltip_text,
            "class": " ".join(css_classes) if css_classes else "hardware-secure"
        }

def main():
    monitor = HardwarePrivacy()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "status":
            status = monitor.get_status()
            print("=== Hardware Privacy Status ===")
            
            usb = status['usb']
            print(f"\n🔌 USB Devices: {usb['total_count']} total")
            if usb['storage_devices']:
                print(f"  Storage: {len(usb['storage_devices'])} devices")
                for device in usb['storage_devices'][:3]:
                    print(f"    • {device}")
            if usb['input_devices']:
                print(f"  Input: {len(usb['input_devices'])} devices")
                for device in usb['input_devices'][:3]:
                    hidraw_info = ""
                    if device in usb['input_hidraw']:
                        hidraw_info = f" → {usb['input_hidraw'][device]}"
                    print(f"    • {device}{hidraw_info}")
            if usb['camera_devices']:
                print(f"  Camera: {len(usb['camera_devices'])} devices")
                for device in usb['camera_devices'][:3]:
                    print(f"    • {device}")
            if usb['bluetooth_devices']:
                print(f"  Bluetooth: {len(usb['bluetooth_devices'])} devices")
                for device in usb['bluetooth_devices'][:3]:
                    print(f"    • {device}")
            if usb['audio_devices']:
                print(f"  Audio: {len(usb['audio_devices'])} devices")
                for device in usb['audio_devices'][:3]:
                    print(f"    • {device}")
            if usb['mounted_storage']:
                print(f"  Mounted: {len(usb['mounted_storage'])} devices")
                for mount in usb['mounted_storage']:
                    print(f"    • {mount}")
            
            bluetooth = status['bluetooth']
            if bluetooth['adapter_present']:
                print(f"\n📡 Bluetooth: {'Enabled' if bluetooth['enabled'] else 'Disabled'}")
                if bluetooth['enabled']:
                    print(f"  Discoverable: {'Yes' if bluetooth['discoverable'] else 'No'}")
                    print(f"  Connected: {len(bluetooth['connected_devices'])} devices")
                    print(f"  Paired: {bluetooth['paired_count']} devices")
                    
                    if bluetooth['connected_devices']:
                        print("  Connected devices:")
                        for device in bluetooth['connected_devices']:
                            battery_info = ""
                            if device in bluetooth.get('device_batteries', {}):
                                battery_level = bluetooth['device_batteries'][device]['level']
                                battery_icon = monitor._get_battery_icon(battery_level)
                                battery_info = f" {battery_icon}{battery_level}%"
                            print(f"    • {device}{battery_info}")
            else:
                print("\n📡 Bluetooth: No adapter found")
                
            # Show device batteries
            all_batteries = {}
            all_batteries.update(usb.get('device_batteries', {}))
            all_batteries.update(bluetooth.get('device_batteries', {}))
            
            if all_batteries:
                print(f"\n🔋 Device Batteries:")
                for device, battery_info in all_batteries.items():
                    battery_level = battery_info['level']
                    battery_icon = monitor._get_battery_icon(battery_level)
                    device_type = battery_info.get('type', 'device')
                    print(f"  • {device}: {battery_icon}{battery_level}% ({device_type})")
                
            return
            
        elif command == "bluetooth-on":
            bluetooth = monitor.check_bluetooth_status()
            if not bluetooth['adapter_present']:
                print("No Bluetooth adapter found")
                return
                
            try:
                subprocess.run(['bluetoothctl', 'power', 'on'], capture_output=True, timeout=3)
                print("Bluetooth enabled")
            except Exception as e:
                print(f"Failed to enable Bluetooth: {e}")
            return
            
        elif command == "bluetooth-off":
            bluetooth = monitor.check_bluetooth_status()
            if not bluetooth['adapter_present']:
                print("No Bluetooth adapter found")
                return
                
            try:
                subprocess.run(['bluetoothctl', 'power', 'off'], capture_output=True, timeout=3)
                print("Bluetooth disabled")
            except Exception as e:
                print(f"Failed to disable Bluetooth: {e}")
            return
            
        elif command == "bluetooth-discoverable":
            bluetooth = monitor.check_bluetooth_status()
            if not bluetooth['adapter_present']:
                print("No Bluetooth adapter found")
                return
            if not bluetooth['enabled']:
                print("Bluetooth is not enabled")
                return
                
            try:
                subprocess.run(['bluetoothctl', 'discoverable', 'on'], capture_output=True, timeout=3)
                print("Bluetooth made discoverable")
            except Exception as e:
                print(f"Failed to make Bluetooth discoverable: {e}")
            return
            
        elif command == "bluetooth-undiscoverable":
            bluetooth = monitor.check_bluetooth_status()
            if not bluetooth['adapter_present']:
                print("No Bluetooth adapter found")
                return
                
            try:
                subprocess.run(['bluetoothctl', 'discoverable', 'off'], capture_output=True, timeout=3)
                print("Bluetooth made undiscoverable")
            except Exception as e:
                print(f"Failed to make Bluetooth undiscoverable: {e}")
            return
            
        elif command == "toggle-discoverable":
            bluetooth = monitor.check_bluetooth_status()
            if not bluetooth['adapter_present']:
                print("No Bluetooth adapter found")
                return
            if not bluetooth['enabled']:
                print("Bluetooth is not enabled")
                return
                
            try:
                if bluetooth['discoverable']:
                    subprocess.run(['bluetoothctl', 'discoverable', 'off'], capture_output=True, timeout=3)
                    print("Bluetooth made undiscoverable")
                else:
                    subprocess.run(['bluetoothctl', 'discoverable', 'on'], capture_output=True, timeout=3)
                    print("Bluetooth made discoverable")
            except Exception as e:
                print(f"Failed to toggle discoverable: {e}")
            return
            
        elif command == "toggle-bluetooth":
            bluetooth = monitor.check_bluetooth_status()
            if not bluetooth['adapter_present']:
                print("No Bluetooth adapter found")
                return
                
            try:
                if bluetooth['enabled']:
                    subprocess.run(['bluetoothctl', 'power', 'off'], capture_output=True, timeout=3)
                    print("Bluetooth disabled")
                else:
                    subprocess.run(['bluetoothctl', 'power', 'on'], capture_output=True, timeout=3)
                    print("Bluetooth enabled")
            except Exception as e:
                print(f"Failed to toggle Bluetooth: {e}")
            return
            
        elif command == "usb-devices":
            usb = monitor.check_usb_devices()
            print("=== USB Device Details ===")
            print(f"Total devices: {usb['total_count']}")
            
            if usb['storage_devices']:
                print(f"💾 Storage Devices ({len(usb['storage_devices'])}):")
                for device in usb['storage_devices']:
                    print(f"  • {device}")
            
            if usb['input_devices']:
                print(f"⌨️ Input Devices ({len(usb['input_devices'])}):")
                for device in usb['input_devices']:
                    hidraw_info = ""
                    if device in usb['input_hidraw']:
                        hidraw_info = f" → {usb['input_hidraw'][device]}"
                    print(f"  • {device}{hidraw_info}")
            
            if usb['camera_devices']:
                print(f"📷 Camera Devices ({len(usb['camera_devices'])}):")
                for device in usb['camera_devices']:
                    print(f"  • {device}")
            
            if usb['bluetooth_devices']:
                print(f"📶 Bluetooth Devices ({len(usb['bluetooth_devices'])}):")
                for device in usb['bluetooth_devices']:
                    print(f"  • {device}")
            
            if usb['audio_devices']:
                print(f"🔊 Audio Devices ({len(usb['audio_devices'])}):")
                for device in usb['audio_devices']:
                    print(f"  • {device}")
            
            if usb['unknown_devices']:
                print(f"❓ Other Devices ({len(usb['unknown_devices'])}):")
                for device in usb['unknown_devices'][:5]:
                    print(f"  • {device}")
                if len(usb['unknown_devices']) > 5:
                    print(f"  • ... and {len(usb['unknown_devices']) - 5} more")
            return
            
        elif command == "interactive-mount":
            monitor._interactive_mount()
            return
            
        elif command == "interactive-unmount":
            monitor._interactive_unmount()
            return

        elif command == "interactive-hidraw-chmod":
            monitor._interactive_hidraw_chmod()
            return

        elif command == "list-mounted-devices":
            monitor._list_mounted_devices()
            return

        elif command == "list-unmounted-devices":
            monitor._list_unmounted_devices()
            return

        elif command == "list-hidraw-devices":
            monitor._list_hidraw_devices()
            return

        elif command == "chmod-hidraw" and len(sys.argv) > 2:
            hidraw_path = sys.argv[2]
            monitor._chmod_hidraw_device(hidraw_path)
            return

    # Default: return status
    status = monitor.get_status()
    output = monitor.format_output(status)
    print(json.dumps(output))

if __name__ == "__main__":
    main()
