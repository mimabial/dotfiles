#!/usr/bin/env python3
"""
Audio/Video Privacy Module for Waybar
Monitors webcam, microphone, and screen sharing activity
Enhanced with comprehensive device detection (internal, USB, wireless)
"""

import json
import subprocess
import sys
import os
import glob
import time
import re
from typing import Dict, List, Set, Optional, Tuple
from password_prompt import run_sudo_command as run_sudo_with_prompt

class ComprehensiveDeviceDetector:
    """Detects all types of audio/video devices: internal, USB, wireless"""
    
    def __init__(self):
        self._cache = {}
        self._cache_timeout = 30.0
        self._device_names_cache = {}
    
    def get_usb_devices(self) -> Dict[str, Dict]:
        """Get USB audio/video devices"""
        if 'usb_devices' in self._cache:
            data, timestamp = self._cache['usb_devices']
            if time.time() - timestamp < self._cache_timeout:
                return data
        
        devices = {}
        try:
            result = subprocess.run(['usb-devices'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                devices = self._parse_usb_devices(result.stdout)
        except (subprocess.TimeoutExpired, FileNotFoundError):
            # Fallback to lsusb
            try:
                result = subprocess.run(['lsusb', '-v'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    devices = self._parse_lsusb_verbose(result.stdout)
            except:
                pass
        
        self._cache['usb_devices'] = (devices, time.time())
        return devices
    
    def get_pci_devices(self) -> Dict[str, Dict]:
        """Get PCI audio/video devices (internal devices)"""
        if 'pci_devices' in self._cache:
            data, timestamp = self._cache['pci_devices']
            if time.time() - timestamp < self._cache_timeout:
                return data
        
        devices = {}
        try:
            result = subprocess.run(['lspci', '-v'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                devices = self._parse_pci_devices(result.stdout)
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        self._cache['pci_devices'] = (devices, time.time())
        return devices
    
    def get_bluetooth_devices(self) -> Dict[str, Dict]:
        """Get Bluetooth audio devices"""
        if 'bluetooth_devices' in self._cache:
            data, timestamp = self._cache['bluetooth_devices']
            if time.time() - timestamp < self._cache_timeout:
                return data
        
        devices = {}
        try:
            result = subprocess.run(['bluetoothctl', 'devices'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                devices = self._parse_bluetooth_devices(result.stdout)
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        self._cache['bluetooth_devices'] = (devices, time.time())
        return devices
    
    def get_audio_cards(self) -> Dict[str, Dict]:
        """Get all audio cards from ALSA"""
        devices = {}
        try:
            # Method 1: /proc/asound/cards
            if os.path.exists('/proc/asound/cards'):
                with open('/proc/asound/cards', 'r') as f:
                    content = f.read()
                    devices.update(self._parse_asound_cards(content))
            
            # Method 2: arecord -l for capture devices
            try:
                result = subprocess.run(['arecord', '-l'], 
                                      capture_output=True, text=True, timeout=3)
                if result.returncode == 0:
                    devices.update(self._parse_arecord_output(result.stdout))
            except:
                pass
                
        except Exception:
            pass
        
        return devices
    
    def _parse_usb_devices(self, output: str) -> Dict[str, Dict]:
        """Parse usb-devices output"""
        devices = {}
        current_device = {}
        
        for line in output.split('\n'):
            line = line.strip()
            if not line:
                if current_device and self._is_av_device(current_device):
                    key = f"{current_device.get('vendor_id', '')}:{current_device.get('product_id', '')}"
                    devices[key] = current_device.copy()
                current_device = {}
                continue
            
            if line.startswith('P:'):
                if 'Vendor=' in line and 'ProdID=' in line:
                    vendor_match = re.search(r'Vendor=([0-9a-fA-F]{4})', line)
                    product_match = re.search(r'ProdID=([0-9a-fA-F]{4})', line)
                    if vendor_match and product_match:
                        current_device['vendor_id'] = vendor_match.group(1).lower()
                        current_device['product_id'] = product_match.group(1).lower()
                        current_device['connection_type'] = 'USB'
            elif line.startswith('S:'):
                if 'Manufacturer=' in line:
                    current_device['manufacturer'] = line.split('Manufacturer=', 1)[1]
                elif 'Product=' in line:
                    current_device['product'] = line.split('Product=', 1)[1]
                elif 'SerialNumber=' in line:
                    current_device['serial'] = line.split('SerialNumber=', 1)[1]
        
        if current_device and self._is_av_device(current_device):
            key = f"{current_device.get('vendor_id', '')}:{current_device.get('product_id', '')}"
            devices[key] = current_device.copy()
        
        return devices
    
    def _parse_lsusb_verbose(self, output: str) -> Dict[str, Dict]:
        """Parse lsusb -v output as fallback"""
        devices = {}
        current_device = {}
        
        for line in output.split('\n'):
            line = line.strip()
            
            if line.startswith('Bus ') and 'ID ' in line:
                if current_device and self._is_av_device(current_device):
                    key = f"{current_device.get('vendor_id', '')}:{current_device.get('product_id', '')}"
                    devices[key] = current_device.copy()
                
                current_device = {}
                id_match = re.search(r'ID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})', line)
                if id_match:
                    current_device['vendor_id'] = id_match.group(1).lower()
                    current_device['product_id'] = id_match.group(2).lower()
                    current_device['connection_type'] = 'USB'
            
            elif line.startswith('iManufacturer') and current_device:
                match = re.search(r'iManufacturer\s+\d+\s+(.+)', line)
                if match:
                    current_device['manufacturer'] = match.group(1)
            
            elif line.startswith('iProduct') and current_device:
                match = re.search(r'iProduct\s+\d+\s+(.+)', line)
                if match:
                    current_device['product'] = match.group(1)
        
        if current_device and self._is_av_device(current_device):
            key = f"{current_device.get('vendor_id', '')}:{current_device.get('product_id', '')}"
            devices[key] = current_device.copy()
        
        return devices
    
    def _parse_pci_devices(self, output: str) -> Dict[str, Dict]:
        """Parse lspci output for internal audio/video devices"""
        devices = {}
        current_device = {}
        
        lines = output.split('\n')
        for i, line in enumerate(lines):
            if re.match(r'^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]', line):
                if current_device and self._is_av_device(current_device):
                    bus_id = current_device.get('bus_id', '')
                    devices[f"pci_{bus_id}"] = current_device.copy()
                
                current_device = {}
                parts = line.split(' ', 1)
                if len(parts) > 1:
                    current_device['bus_id'] = parts[0]
                    current_device['description'] = parts[1]
                    current_device['connection_type'] = 'Internal'
                    
                    desc_lower = parts[1].lower()
                    if any(keyword in desc_lower for keyword in ['audio', 'sound', 'multimedia']):
                        current_device['device_type'] = 'audio'
                    elif any(keyword in desc_lower for keyword in ['vga', 'display', 'video']):
                        current_device['device_type'] = 'video'
            
            elif line.startswith('\t') and current_device:
                if 'Subsystem:' in line:
                    current_device['subsystem'] = line.split('Subsystem:', 1)[1].strip()
                elif 'Kernel driver in use:' in line:
                    current_device['driver'] = line.split('Kernel driver in use:', 1)[1].strip()
        
        if current_device and self._is_av_device(current_device):
            bus_id = current_device.get('bus_id', '')
            devices[f"pci_{bus_id}"] = current_device.copy()
        
        return devices
    
    def _parse_bluetooth_devices(self, output: str) -> Dict[str, Dict]:
        """Parse bluetoothctl devices output"""
        devices = {}
        
        for line in output.split('\n'):
            line = line.strip()
            if line.startswith('Device '):
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    mac_addr = parts[1]
                    device_name = parts[2]
                    
                    name_lower = device_name.lower()
                    if any(keyword in name_lower for keyword in 
                          ['headphone', 'headset', 'speaker', 'buds', 'airpods', 'audio', 'mic']):
                        devices[f"bt_{mac_addr}"] = {
                            'mac_address': mac_addr,
                            'name': device_name,
                            'product': device_name,
                            'connection_type': 'Bluetooth',
                            'device_type': 'audio'
                        }
        
        return devices
    
    def _parse_asound_cards(self, content: str) -> Dict[str, Dict]:
        """Parse /proc/asound/cards"""
        devices = {}
        
        for line in content.split('\n'):
            line = line.strip()
            if re.match(r'^\s*\d+', line):
                parts = line.split(':', 1)
                if len(parts) > 1:
                    card_num = parts[0].strip()
                    description = parts[1].strip()
                    
                    if '[' in description:
                        description = description.split('[')[0].strip()
                    
                    devices[f"alsa_card_{card_num}"] = {
                        'card_number': card_num,
                        'description': description,
                        'product': description,
                        'connection_type': 'Internal',
                        'device_type': 'audio'
                    }
        
        return devices
    
    def _parse_arecord_output(self, output: str) -> Dict[str, Dict]:
        """Parse arecord -l output for capture devices"""
        devices = {}
        
        for line in output.split('\n'):
            if 'card ' in line and 'device ' in line:
                match = re.search(r'card (\d+): ([^,]+), device (\d+): (.+)', line)
                if match:
                    card_num = match.group(1)
                    card_name = match.group(2).strip()
                    device_num = match.group(3)
                    device_name = match.group(4).strip()
                    
                    key = f"capture_{card_num}_{device_num}"
                    devices[key] = {
                        'card_number': card_num,
                        'device_number': device_num,
                        'card_name': card_name,
                        'device_name': device_name,
                        'product': device_name,
                        'connection_type': 'Internal',
                        'device_type': 'audio_capture'
                    }
        
        return devices
    
    def _is_av_device(self, device: Dict) -> bool:
        """Check if device is audio/video related"""
        product = device.get('product', '').lower()
        description = device.get('description', '').lower()
        
        av_keywords = [
            'audio', 'sound', 'microphone', 'mic', 'headset', 'speaker', 
            'headphone', 'earphone', 'codec', 'dac', 'amplifier',
            'camera', 'webcam', 'video', 'capture', 'imaging', 'usb video class',
            'multimedia', 'uvc', 'v4l2'
        ]
        
        text_to_check = f"{product} {description}"
        return any(keyword in text_to_check for keyword in av_keywords)
    
    def get_device_friendly_name(self, device_path: str, fallback_name: str = None) -> str:
        """Get friendly name for a device using comprehensive detection"""
        # Check cache first
        cache_key = f"name_{device_path}"
        if cache_key in self._device_names_cache:
            cached_name, timestamp = self._device_names_cache[cache_key]
            if time.time() - timestamp < self._cache_timeout:
                return cached_name
        
        friendly_name = None
        
        # Try to get USB info first
        usb_info = self._get_device_usb_info(device_path)
        if usb_info:
            manufacturer = usb_info.get('manufacturer', '').strip()
            product = usb_info.get('product', '').strip()
            
            if manufacturer and product:
                if manufacturer.lower() in product.lower():
                    friendly_name = product
                else:
                    friendly_name = f"{manufacturer} {product}"
            elif product:
                friendly_name = product
            elif manufacturer:
                friendly_name = f"{manufacturer} Device"
        
        # Try PCI devices for internal hardware
        if not friendly_name:
            pci_devices = self.get_pci_devices()
            for device_id, device in pci_devices.items():
                if device.get('device_type') in ['audio', 'video']:
                    description = device.get('description', '')
                    subsystem = device.get('subsystem', '')
                    if description:
                        friendly_name = description
                        break
        
        # Try ALSA cards for audio devices
        if not friendly_name and ('audio' in device_path or 'snd' in device_path):
            audio_cards = self.get_audio_cards()
            for device_id, device in audio_cards.items():
                description = device.get('description', '')
                if description and description not in ['Unknown', '']:
                    friendly_name = description
                    break
        
        # Use fallback or create generic name
        if not friendly_name:
            if fallback_name:
                friendly_name = fallback_name
            else:
                friendly_name = f"Device {os.path.basename(device_path)}"
        
        # Cache the result
        self._device_names_cache[cache_key] = (friendly_name, time.time())
        return friendly_name
    
    def _get_device_usb_info(self, device_path: str) -> Optional[Dict]:
        """Get USB information for a specific device path"""
        try:
            result = subprocess.run(['udevadm', 'info', '--name', device_path], 
                                  capture_output=True, text=True, timeout=3)
            if result.returncode != 0:
                return None
            
            vendor_id = None
            product_id = None
            
            for line in result.stdout.split('\n'):
                if 'ID_VENDOR_ID=' in line:
                    vendor_id = line.split('ID_VENDOR_ID=')[1].strip().lower()
                elif 'ID_MODEL_ID=' in line:
                    product_id = line.split('ID_MODEL_ID=')[1].strip().lower()
            
            if vendor_id and product_id:
                usb_devices = self.get_usb_devices()
                device_key = f"{vendor_id}:{product_id}"
                return usb_devices.get(device_key)
                
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        return None
    
    def get_all_microphone_info(self) -> Dict[str, str]:
        """Get comprehensive microphone information"""
        microphones = {}
        
        # USB microphones
        usb_devices = self.get_usb_devices()
        for device_key, device in usb_devices.items():
            product = device.get('product', '').lower()
            if any(keyword in product for keyword in ['mic', 'microphone', 'headset', 'audio']):
                name = self._get_device_display_name(device)
                microphones[f"usb_{device_key}"] = f"{name} (USB)"
        
        # Internal microphones
        audio_cards = self.get_audio_cards()
        for device_key, device in audio_cards.items():
            if 'capture' in device.get('device_type', ''):
                name = self._get_device_display_name(device)
                microphones[f"internal_{device_key}"] = f"{name} (Internal)"
        
        # Bluetooth microphones
        bt_devices = self.get_bluetooth_devices()
        for device_key, device in bt_devices.items():
            name = self._get_device_display_name(device)
            microphones[f"bluetooth_{device_key}"] = f"{name} (Bluetooth)"
        
        return microphones
    
    def _get_device_display_name(self, device: Dict) -> str:
        """Get a user-friendly display name for a device"""
        if device.get('product'):
            return device['product']
        elif device.get('name'):
            return device['name']
        elif device.get('description'):
            return device['description']
        elif device.get('device_name'):
            return device['device_name']
        else:
            return f"Unknown Device ({device.get('connection_type', 'Unknown')})"


class ModuleManager:
    """Manages kernel modules for audio/video devices"""
    
    def __init__(self):
        self.camera_modules = {
            'uvcvideo': 'USB Video Class driver (webcams)',
            'gspca_main': 'GSPCA webcam driver',
            'v4l2loopback': 'Video4Linux loopback device',
            'ov534': 'OmniVision OV534 webcam',
            'stkwebcam': 'Syntek webcam driver'
        }
        
        self.audio_modules = {
            'snd_usb_audio': 'USB audio devices',
            'snd_hda_intel': 'Intel HDA audio',
            'snd_hda_codec_realtek': 'Realtek HDA codec',
            'snd_hda_codec_hdmi': 'HDMI audio codec',
            'snd_ac97_codec': 'AC97 audio codec',
            'btusb': 'Bluetooth USB devices',
            'snd_bluetooth': 'Bluetooth audio'
        }
        
        self.all_modules = {**self.camera_modules, **self.audio_modules}

    def get_loaded_modules(self) -> Set[str]:
        """Get list of currently loaded modules"""
        loaded = set()
        try:
            with open('/proc/modules', 'r') as f:
                for line in f:
                    module_name = line.split()[0]
                    if module_name in self.all_modules:
                        loaded.add(module_name)
        except:
            pass
        return loaded

    def is_module_loaded(self, module_name: str) -> bool:
        """Check if a specific module is loaded"""
        return module_name in self.get_loaded_modules()

    def run_sudo_command(self, command: List[str], action: str) -> bool:
        """Run a sudo command with context-aware interface"""
        return run_sudo_with_prompt(command, action, f"Execute {action}")

    def unload_module(self, module_name: str, force: bool = False) -> bool:
        """Unload a kernel module using modprobe"""
        if not self.is_module_loaded(module_name):
            return True
        
        if module_name in self.camera_modules:
            force = True
        
        cmd = ['sudo', 'modprobe', '-r', module_name]
        if force:
            cmd.insert(2, '-f')
        return self.run_sudo_command(cmd, f"Unload {module_name} module")

    def load_module(self, module_name: str) -> bool:
        """Load a kernel module using modprobe"""
        if self.is_module_loaded(module_name):
            return True
        
        cmd = ['sudo', 'modprobe', module_name]
        return self.run_sudo_command(cmd, f"Load {module_name} module")

    def unload_camera_modules(self, force: bool = False) -> Dict[str, bool]:
        """Unload all camera-related modules"""
        results = {}
        loaded_camera_modules = [m for m in self.camera_modules.keys() if self.is_module_loaded(m)]
        
        for module in loaded_camera_modules:
            results[module] = self.unload_module(module, force)
        
        return results

    def load_camera_modules(self) -> Dict[str, bool]:
        """Load common camera modules"""
        results = {}
        common_modules = ['uvcvideo']
        
        for module in common_modules:
            if not self.is_module_loaded(module):
                results[module] = self.load_module(module)
        
        return results

    def get_module_status(self) -> Dict:
        """Get comprehensive module status"""
        loaded = self.get_loaded_modules()
        
        return {
            'camera_modules': {
                name: {
                    'loaded': name in loaded,
                    'description': desc
                } for name, desc in self.camera_modules.items()
            },
            'audio_modules': {
                name: {
                    'loaded': name in loaded,
                    'description': desc
                } for name, desc in self.audio_modules.items()
            },
            'summary': {
                'camera_modules_loaded': len([m for m in self.camera_modules.keys() if m in loaded]),
                'audio_modules_loaded': len([m for m in self.audio_modules.keys() if m in loaded]),
                'total_av_modules': len(loaded.intersection(self.all_modules.keys()))
            }
        }


class AudioVideoPrivacy:
    def __init__(self):
        self.icons = {
            'webcam_active': '🔹',
            'webcam_available': '📷',
            'webcam_disabled': '🔵',
            'microphone_active': '🎤',
            'microphone_available': '🎙️',
            'microphone_muted': '🔇',
            'screenshare_active': '🖥️',
            'screenshare_ready': '💻'
        }
        self._cache = {}
        self._cache_timeout = 1.0
        self.modules = ModuleManager()
        self.device_detector = ComprehensiveDeviceDetector()

    def get_camera_module_name(self) -> str:
        """Detect which camera module is providing video devices"""
        try:
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
            
            result = subprocess.run(['lsmod'], capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                camera_modules = ['uvcvideo', 'gspca_main', 'gspca_pac7302']
                for line in result.stdout.split('\n'):
                    module_name = line.split()[0] if line.split() else ''
                    if module_name in camera_modules:
                        return module_name
                    if module_name.startswith('gspca_'):
                        return 'gspca_main'
                        
        except Exception:
            pass
            
        return 'uvcvideo'

    def get_camera_friendly_name(self, device_path: str) -> str:
        """Get friendly camera name using comprehensive detection"""
        # Use comprehensive detector first
        friendly_name = self.device_detector.get_device_friendly_name(device_path)
        if friendly_name and not friendly_name.startswith('Device /dev/'):
            return friendly_name
        
        # Fallback to v4l2-ctl
        try:
            result = subprocess.run(['v4l2-ctl', '--device', device_path, '--info'], 
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'Card type' in line:
                        camera_name = line.split(':')[-1].strip()
                        if camera_name and camera_name != device_path:
                            return camera_name
        except:
            pass
            
        return f"Camera {device_path}"

    def _get_cached_or_run(self, key: str, func, *args, **kwargs):
        now = time.time()
        if key in self._cache:
            result, timestamp = self._cache[key]
            if now - timestamp < self._cache_timeout:
                return result
        
        result = func(*args, **kwargs)
        self._cache[key] = (result, now)
        return result

    def check_webcam_status(self) -> Dict:
        return self._get_cached_or_run('webcam', self._check_webcam_impl)

    def _check_webcam_impl(self) -> Dict:
        status = {
            'active_streams': [],
            'devices_in_use': [],
            'available_devices': [],
            'has_webcam': False,
            'hardware_disabled': False,
            'camera_module': None,
            'modules_loaded': []
        }

        camera_module = self.get_camera_module_name()
        status['camera_module'] = camera_module

        loaded_modules = self.modules.get_loaded_modules()
        status['modules_loaded'] = [m for m in self.modules.camera_modules.keys() if m in loaded_modules]
        
        if not status['modules_loaded']:
            status['hardware_disabled'] = True
            return status

        video_devices = glob.glob('/dev/video*')
        if not video_devices:
            status['hardware_disabled'] = True
            return status

        status['has_webcam'] = True

        # Filter to only capture-capable devices
        main_capture_devices = []
        all_functional_devices = []
        
        for device in video_devices:
            device_info = {
                'device': device,
                'name': self.get_camera_friendly_name(device),
                'in_use': False,
                'is_capture': False,
                'is_main': False
            }
            
            try:
                result = subprocess.run(['v4l2-ctl', '--device', device, '--info'], 
                                      capture_output=True, text=True, timeout=2)
                if result.returncode == 0:
                    info_text = result.stdout
                    
                    # Check if this is a capture device
                    if 'Video Capture' in info_text:
                        device_info['is_capture'] = True
                        
                        # Check for standard video formats (main capture devices)
                        caps_result = subprocess.run(['v4l2-ctl', '--device', device, '--list-formats-ext'], 
                                                   capture_output=True, text=True, timeout=2)
                        
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
                            lines = lsof_result.stdout.strip().split('\n')[1:]
                            for line in lines:
                                parts = line.split()
                                if len(parts) > 1:
                                    process_name = parts[0]
                                    pid = parts[1]
                                    # Only count main capture devices as "in use" for privacy
                                    if device_info['is_main'] or device_info['is_capture']:
                                        status['devices_in_use'].append({
                                            'device': device,
                                            'name': device_info['name'],
                                            'process': process_name,
                                            'pid': pid
                                        })
                                        device_info['in_use'] = True
                                
            except (subprocess.TimeoutExpired, FileNotFoundError):
                if os.path.exists(device):
                    try:
                        with open(device, 'rb') as f:
                            pass
                        device_info['name'] = self.get_camera_friendly_name(device)
                        device_info['is_capture'] = True
                        all_functional_devices.append(device_info)
                    except:
                        pass
        
        # Use main capture devices, fallback to all functional if none found
        if main_capture_devices:
            status['available_devices'] = main_capture_devices
        else:
            status['available_devices'] = all_functional_devices

        # Check PipeWire streams
        try:
            result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for item in data:
                    if item.get('type') == 'PipeWire:Interface:Node':
                        props = item.get('info', {}).get('props', {})
                        media_class = props.get('media.class', '')
                        
                        if 'Stream/Input/Video' in media_class:
                            app_name = props.get('application.name', '')
                            app_process = props.get('application.process.binary', '')
                            app_pid = props.get('application.process.id', '')
                            
                            real_app = False
                            display_name = None
                            
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
                                    real_app = True
                                    display_name = app_process
                            
                            elif (app_name and app_name not in ['Unknown', '', 'pipewire'] and 
                                  not app_name.startswith('v4l2_') and
                                  'input' not in app_name.lower()):
                                real_app = True
                                display_name = app_name
                            
                            if real_app and display_name:
                                status['active_streams'].append(display_name)
                            
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            pass

        return status

    def check_microphone_status(self) -> Dict:
        return self._get_cached_or_run('microphone', self._check_microphone_impl)

    def _check_microphone_impl(self) -> Dict:
        status = {
            'active_streams': [],
            'is_muted': None,
            'has_microphone': False,
            'default_source': None,
            'device_name': None,
            'available_devices': []
        }

        # Get comprehensive microphone information
        microphone_info = self.device_detector.get_all_microphone_info()
        status['available_devices'] = list(microphone_info.values())

        try:
            result = subprocess.run(['pactl', 'get-default-source'], 
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                status['default_source'] = result.stdout.strip()
                status['has_microphone'] = True
                
                # Try to get a friendly name for the default source
                try:
                    info_result = subprocess.run(['pactl', 'list', 'sources'], 
                                                capture_output=True, text=True, timeout=3)
                    if info_result.returncode == 0:
                        # Parse pactl output to find device name
                        current_source = None
                        for line in info_result.stdout.split('\n'):
                            if line.startswith('Source #'):
                                current_source = None
                            elif 'Name:' in line and status['default_source'] in line:
                                current_source = 'found'
                            elif current_source and 'device.description' in line:
                                device_desc = line.split('=', 1)[1].strip().strip('"')
                                status['device_name'] = device_desc
                                break
                            elif current_source and 'Description:' in line:
                                status['device_name'] = line.split(':', 1)[1].strip()
                                break
                
                        # Fallback: try to match with detected devices
                        if not status['device_name'] and microphone_info:
                            # Use the first available microphone as fallback
                            status['device_name'] = list(microphone_info.values())[0]
                
                except:
                    pass
                
                # Check mute status
                mute_result = subprocess.run(['pactl', 'get-source-mute', '@DEFAULT_SOURCE@'], 
                                           capture_output=True, text=True, timeout=2)
                if mute_result.returncode == 0:
                    status['is_muted'] = 'yes' in mute_result.stdout.lower()
        except:
            pass

        # Check PipeWire streams
        try:
            result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=3)
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
                                status['active_streams'].append(app_name)
                            elif app_process and app_process != 'Unknown':
                                status['active_streams'].append(app_process)
        except:
            pass

        return status

    def check_screenshare_status(self) -> Dict:
        return self._get_cached_or_run('screenshare', self._check_screenshare_impl)

    def _check_screenshare_impl(self) -> Dict:
        status = {
            'active_sessions': [],
            'ready_apps': [],
            'is_sharing': False
        }

        sharing_apps = ['obs', 'zoom', 'teams', 'discord', 'chrome', 'firefox']
        
        for app in sharing_apps:
            try:
                result = subprocess.run(['pgrep', '-f', app], capture_output=True, timeout=1)
                if result.returncode == 0:
                    if self._is_actually_sharing(app):
                        status['active_sessions'].append(app)
                        status['is_sharing'] = True
                    else:
                        status['ready_apps'].append(app)
            except:
                continue

        return status

    def _is_actually_sharing(self, process_name: str) -> bool:
        """Check if process is actually sharing screen"""
        try:
            result = subprocess.run(['pw-dump'], capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for item in data:
                    if item.get('type') == 'PipeWire:Interface:Node':
                        props = item.get('info', {}).get('props', {})
                        media_class = props.get('media.class', '')
                        app_name = props.get('application.name', '').lower()
                        
                        if 'Stream/Output/Video' in media_class:
                            if process_name.lower() in app_name:
                                return True
        except:
            pass
        return False

    def get_status(self) -> Dict:
        return {
            'webcam': self.check_webcam_status(),
            'microphone': self.check_microphone_status(),
            'screenshare': self.check_screenshare_status()
        }

    def format_output(self, status: Dict) -> Dict:
        active_indicators = []
        tooltip_lines = []
        css_classes = []

        # Webcam
        webcam = status['webcam']
        if webcam['active_streams'] or webcam['devices_in_use']:
            active_indicators.append(self.icons['webcam_active'])
            css_classes.append('webcam-active')
            tooltip_lines.append("🔹 WEBCAM ACTIVE:")
            for stream in webcam['active_streams']:
                tooltip_lines.append(f"  • {stream}")
            for device in webcam['devices_in_use']:
                tooltip_lines.append(f"  • {device['name']}: {device['process']}")
        elif webcam['hardware_disabled']:
            active_indicators.append(self.icons['webcam_disabled'])
            css_classes.append('webcam-disabled')
            tooltip_lines.append("🔵 Camera disabled/unavailable")
        elif webcam['has_webcam']:
            active_indicators.append(self.icons['webcam_available'])
            css_classes.append('webcam-available')
            tooltip_lines.append("📷 Camera available:")
            for device in webcam['available_devices']:
                tooltip_lines.append(f"  • {device['name']}")

        # Microphone
        microphone = status['microphone']
        if microphone['has_microphone']:
            device_name = microphone.get('device_name', 'Microphone')
            if microphone['is_muted']:
                active_indicators.append(self.icons['microphone_muted'])
                css_classes.append('microphone-muted')
                tooltip_lines.append(f"🔇 MICROPHONE MUTED: {device_name}")
            elif microphone['active_streams']:
                active_indicators.append(self.icons['microphone_active'])
                css_classes.append('microphone-active')
                tooltip_lines.append(f"🎤 MICROPHONE ACTIVE: {device_name}")
                for stream in microphone['active_streams']:
                    tooltip_lines.append(f"  • {stream}")
            else:
                active_indicators.append(self.icons['microphone_available'])
                css_classes.append('microphone-available')
                tooltip_lines.append(f"🎙️ Microphone available:\n  • {device_name}")
                
                # Show all available microphones in tooltip
                if microphone.get('available_devices') and len(microphone['available_devices']) > 1:
                    tooltip_lines.append("  Available devices:")
                    for device in microphone['available_devices']:  # Limit to 3 for space
                        tooltip_lines.append(f"    • {device}")

        # Screen sharing
        screenshare = status['screenshare']
        if screenshare['is_sharing']:
            active_indicators.append(self.icons['screenshare_active'])
            css_classes.append('screenshare-active')
            tooltip_lines.append("🖥️ SCREEN SHARING:")
            for session in screenshare['active_sessions']:
                tooltip_lines.append(f"  • {session}")
        elif screenshare['ready_apps']:
            css_classes.append('screenshare-ready')

        tooltip_text = "\n".join(tooltip_lines) if tooltip_lines else "Audio/Video: Secure 🔒"
        
        return {
            "text": " ".join(active_indicators) if active_indicators else "🔒",
            "tooltip": tooltip_text,
            "class": " ".join(css_classes) if css_classes else "av-secure"
        }

def main():
    monitor = AudioVideoPrivacy()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "toggle-webcam":
            status = monitor.check_webcam_status()
            camera_module = status.get('camera_module', 'uvcvideo')
            
            if status['devices_in_use']:
                killed_processes = []
                for device_info in status['devices_in_use']:
                    try:
                        subprocess.run(['kill', device_info['pid']], capture_output=True)
                        killed_processes.append(device_info['process'])
                    except:
                        pass
                message = f"Stopped camera access: {', '.join(killed_processes)}" if killed_processes else "Camera access stopped"
                
            elif status['hardware_disabled']:
                results = monitor.modules.load_camera_modules()
                if any(results.values()):
                    message = "✅ Camera hardware enabled"
                else:
                    message = "ℹ️ Camera modules already loaded"
                    
            elif status['has_webcam']:
                results = monitor.modules.unload_camera_modules()
                if any(results.values()):
                    message = "✅ Camera hardware disabled"
                else:
                    message = "❌ Failed to disable camera hardware"
            else:
                message = "No camera detected"
            
            try:
                subprocess.run(['notify-send', 'Privacy Module', message], 
                             capture_output=True, timeout=2)
            except:
                pass
            print(f"Privacy Module: {message}")
            return
            
        elif command == "toggle-microphone":
            subprocess.run(['pactl', 'set-source-mute', '@DEFAULT_SOURCE@', 'toggle'])
            try:
                status_result = subprocess.run(['pactl', 'get-source-mute', '@DEFAULT_SOURCE@'], 
                                             capture_output=True, text=True)
                if status_result.returncode == 0:
                    is_muted = 'yes' in status_result.stdout.lower()
                    status_msg = "Microphone MUTED" if is_muted else "Microphone UNMUTED"
                    subprocess.run(['notify-send', 'Privacy Module', status_msg], 
                                 capture_output=True, timeout=2)
                    print(f"Privacy Module: {status_msg}")
            except:
                print("Privacy Module: Microphone toggled")
            return
            
        elif command == "kill-camera-apps":
            apps = ['zoom', 'teams', 'discord', 'obs']
            killed = []
            for app in apps:
                try:
                    result = subprocess.run(['pkill', '-f', app], capture_output=True)
                    if result.returncode == 0:
                        killed.append(app)
                except:
                    pass
            if killed:
                message = f"Killed: {', '.join(killed)}"
            else:
                message = "No camera apps found"
            
            try:
                subprocess.run(['notify-send', 'Privacy Module', message], 
                             capture_output=True, timeout=2)
            except:
                pass
            print(f"Privacy Module: {message}")
            return
            
        elif command == "status":
            status = monitor.get_status()
            print("=== Audio/Video Privacy Status ===")
            for category, data in status.items():
                print(f"\n{category.upper()}:")
                for key, value in data.items():
                    if isinstance(value, list) and value:
                        print(f"  {key}: {len(value)} items")
                        for item in value:
                            if isinstance(item, dict):
                                print(f"    • {item.get('name', item)}")
                            else:
                                print(f"    • {item}")
                    elif value:
                        print(f"  {key}: {value}")
            return
            
        elif command == "devices":
            print("=== COMPREHENSIVE DEVICE DETECTION ===")
            
            # Show categorized devices
            usb_devices = monitor.device_detector.get_usb_devices()
            pci_devices = monitor.device_detector.get_pci_devices()
            bt_devices = monitor.device_detector.get_bluetooth_devices()
            audio_cards = monitor.device_detector.get_audio_cards()
            microphone_info = monitor.device_detector.get_all_microphone_info()
            
            print("\n📷 CAMERAS:")
            webcam_status = monitor.check_webcam_status()
            for device in webcam_status.get('available_devices', []):
                print(f"  🔸 {device['name']} ({device['device']})")
            
            print("\n🎤 MICROPHONES:")
            for device_id, device_name in microphone_info.items():
                print(f"  🔸 {device_name}")
            
            print("\n🔌 USB A/V DEVICES:")
            for device_id, device in usb_devices.items():
                name = monitor.device_detector._get_device_display_name(device)
                print(f"  🔸 {name} (ID: {device_id})")
            
            print("\n💻 INTERNAL DEVICES:")
            for device_id, device in pci_devices.items():
                name = monitor.device_detector._get_device_display_name(device)
                print(f"  🔸 {name} ({device.get('device_type', 'unknown')})")
            
            print("\n📡 BLUETOOTH DEVICES:")
            for device_id, device in bt_devices.items():
                name = monitor.device_detector._get_device_display_name(device)
                print(f"  🔸 {name}")
            return
            
        elif command == "modules-status":
            module_status = monitor.modules.get_module_status()
            print("=== Kernel Module Status ===")
            
            print("\nCAMERA MODULES:")
            for name, info in module_status['camera_modules'].items():
                status_icon = "🟢" if info['loaded'] else "🔴"
                print(f"  {status_icon} {name}: {info['description']}")
            
            print("\nAUDIO MODULES:")
            for name, info in module_status['audio_modules'].items():
                status_icon = "🟢" if info['loaded'] else "🔴"
                print(f"  {status_icon} {name}: {info['description']}")
            
            summary = module_status['summary']
            print(f"\nSUMMARY:")
            print(f"  Camera modules loaded: {summary['camera_modules_loaded']}")
            print(f"  Audio modules loaded: {summary['audio_modules_loaded']}")
            print(f"  Total A/V modules: {summary['total_av_modules']}")
            return

    # Default: return status for Waybar
    status = monitor.get_status()
    output = monitor.format_output(status)
    print(json.dumps(output))

if __name__ == "__main__":
    main()
