#!/usr/bin/env python3
"""
System Privacy Module for Waybar
Monitors location services and system-level privacy
"""

import json
import subprocess
import sys
import time
from typing import Dict, List

class SystemPrivacy:
    def __init__(self):
        self.icons = {
            'location_active': '📍',
            'location_available': '🗺️',
            'location_off': '🚫',
            'process_monitor': '👁️',
            'system_secure': '🛡️',
            'privacy_warning': '⚠️'
        }
        self._cache = {}
        self._cache_timeout = 3.0  # System services change slowly

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

    def check_location_services(self) -> Dict:
        return self._get_cached_or_run('location', self._check_location_impl)

    def _check_location_impl(self) -> Dict:
        status = {
            'geoclue_active': False,
            'geoclue_clients': 0,
            'gps_services': [],
            'location_apps': [],
            'precision_level': 'unknown'
        }

        # Check Geoclue service
        returncode, stdout, _ = self._run_command_fast(['systemctl', '--user', 'is-active', 'geoclue'], 1.0)
        if returncode == 0 and 'active' in stdout:
            status['geoclue_active'] = True

            # Check for active clients
            returncode, stdout, _ = self._run_command_fast(['busctl', 'tree', 'org.freedesktop.GeoClue2'], 2.0)
            if returncode == 0:
                client_lines = [line for line in stdout.split('\n') 
                              if '/org/freedesktop/GeoClue2/Client' in line]
                status['geoclue_clients'] = len(client_lines)

        # Check for GPS-related processes
        gps_processes = ['gpsd', 'chronyd', 'networkmanager', 'ModemManager']
        for process in gps_processes:
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-c', process], 0.5)
            if returncode == 0 and stdout.strip() != '0':
                status['gps_services'].append(process)

        # Check for location-aware applications
        location_apps = ['firefox', 'chrome', 'gnome-maps', 'weather']
        for app in location_apps:
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-f', app], 0.5)
            if returncode == 0:
                status['location_apps'].append(app)

        return status

    def check_privacy_processes(self) -> Dict:
        return self._get_cached_or_run('processes', self._check_processes_impl)

    def _check_processes_impl(self) -> Dict:
        status = {
            'monitoring_tools': [],
            'keyloggers': [],
            'screen_capture': [],
            'network_monitoring': [],
            'suspicious_count': 0
        }

        # Check for monitoring tools
        monitoring_tools = {
            'strace': 'System call tracer',
            'tcpdump': 'Network packet capture',
            'wireshark': 'Network analyzer',
            'htop': 'Process monitor',
            'iotop': 'I/O monitor'
        }

        for tool, description in monitoring_tools.items():
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-c', tool], 0.5)
            if returncode == 0 and stdout.strip() != '0':
                status['monitoring_tools'].append(f"{tool} ({description})")

        # Check for potentially suspicious processes
        suspicious_processes = ['keylogger', 'logkeys', 'xev', 'xinput']
        for process in suspicious_processes:
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-f', process], 0.5)
            if returncode == 0:
                status['keyloggers'].append(process)
                status['suspicious_count'] += 1

        # Check for screen capture tools
        screen_tools = ['scrot', 'flameshot', 'spectacle', 'gnome-screenshot']
        for tool in screen_tools:
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-f', tool], 0.5)
            if returncode == 0:
                status['screen_capture'].append(tool)

        return status

    def check_system_permissions(self) -> Dict:
        return self._get_cached_or_run('permissions', self._check_permissions_impl)

    def _check_permissions_impl(self) -> Dict:
        status = {
            'user_groups': [],
            'sudo_access': False,
            'sensitive_groups': [],
            'file_permissions': {}
        }

        # Check user groups
        try:
            returncode, stdout, _ = self._run_command_fast(['groups'], 1.0)
            if returncode == 0:
                groups = stdout.strip().split()[1:]  # Skip username
                status['user_groups'] = groups
                
                # Check for sensitive groups
                sensitive = ['sudo', 'wheel', 'admin', 'root', 'docker', 'video', 'audio']
                status['sensitive_groups'] = [g for g in groups if g in sensitive]

        except:
            pass

        # Quick sudo check
        returncode, stdout, _ = self._run_command_fast(['sudo', '-n', 'true'], 0.5)
        if returncode == 0:
            status['sudo_access'] = True

        return status

    def get_status(self) -> Dict:
        return {
            'location': self.check_location_services(),
            'processes': self.check_privacy_processes(),
            'permissions': self.check_system_permissions()
        }

    def format_output(self, status: Dict) -> Dict:
        active_indicators = []
        tooltip_lines = []
        css_classes = []

        location = status['location']
        processes = status['processes']
        permissions = status['permissions']

        # Location services
        if location['geoclue_active'] and location['geoclue_clients'] > 0:
            active_indicators.append(self.icons['location_active'])
            css_classes.append('location-active')
            tooltip_lines.append(f"📍 LOCATION ACTIVE: {location['geoclue_clients']} clients")
        elif location['geoclue_active'] or location['gps_services']:
            active_indicators.append(self.icons['location_available'])
            css_classes.append('location-available')
            tooltip_lines.append("🗺️ Location services available")
            
            if location['gps_services']:
                for service in location['gps_services'][:2]:
                    tooltip_lines.append(f"  • {service}")
        else:
            # Don't show location off icon unless explicitly disabled
            pass

        # Privacy monitoring processes
        if processes['monitoring_tools']:
            active_indicators.append(self.icons['process_monitor'])
            css_classes.append('monitoring-active')
            tooltip_lines.append("👁️ MONITORING TOOLS:")
            
            for tool in processes['monitoring_tools'][:2]:
                tooltip_lines.append(f"  • {tool}")
            if len(processes['monitoring_tools']) > 2:
                tooltip_lines.append(f"  • +{len(processes['monitoring_tools']) - 2} more")

        # Suspicious processes (keyloggers, etc.)
        if processes['keyloggers'] or processes['suspicious_count'] > 0:
            active_indicators.append(self.icons['privacy_warning'])
            css_classes.append('privacy-warning')
            tooltip_lines.append("⚠️ SUSPICIOUS PROCESSES:")
            
            for keylogger in processes['keyloggers']:
                tooltip_lines.append(f"  • {keylogger}")

        # System permissions (show if user has elevated privileges)
        if permissions['sensitive_groups']:
            if any(group in permissions['sensitive_groups'] for group in ['sudo', 'wheel', 'admin', 'root']):
                # Don't show as warning - elevated privileges are often legitimate
                pass
            
            # Show if user is in video/audio groups (potential privacy access)
            privacy_groups = [g for g in permissions['sensitive_groups'] if g in ['video', 'audio']]
            if privacy_groups:
                tooltip_lines.append(f"🔑 System access: {', '.join(privacy_groups)}")

        # Security assessment
        security_issues = 0
        if location['geoclue_active'] and location['geoclue_clients'] > 0:
            security_issues += 1
        if processes['suspicious_count'] > 0:
            security_issues += 2  # More serious
        if len(processes['monitoring_tools']) > 2:
            security_issues += 1

        if security_issues == 0:
            css_class = "system-secure"
        elif security_issues <= 2:
            css_class = "system-monitored"
        else:
            css_class = "system-exposed"

        tooltip_text = "\n".join(tooltip_lines) if tooltip_lines else "System: Secure 🛡️"
        
        return {
            "text": " ".join(active_indicators) if active_indicators else "🛡️",
            "tooltip": tooltip_text,
            "class": css_class
        }

def main():
    monitor = SystemPrivacy()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "status":
            status = monitor.get_status()
            print("=== System Privacy Status ===")
            
            location = status['location']
            print(f"\n📍 Location Services:")
            print(f"  Geoclue Active: {'Yes' if location['geoclue_active'] else 'No'}")
            if location['geoclue_active']:
                print(f"  Active Clients: {location['geoclue_clients']}")
            
            if location['gps_services']:
                print("  GPS Services:")
                for service in location['gps_services']:
                    print(f"    • {service}")
                    
            if location['location_apps']:
                print("  Location-aware Apps:")
                for app in location['location_apps']:
                    print(f"    • {app}")
            
            processes = status['processes']
            print(f"\n👁️ Privacy Monitoring:")
            print(f"  Monitoring Tools: {len(processes['monitoring_tools'])}")
            if processes['monitoring_tools']:
                for tool in processes['monitoring_tools']:
                    print(f"    • {tool}")
                    
            print(f"  Keyloggers: {len(processes['keyloggers'])}")
            if processes['keyloggers']:
                for keylogger in processes['keyloggers']:
                    print(f"    • {keylogger}")
                    
            print(f"  Screen Capture: {len(processes['screen_capture'])}")
            if processes['screen_capture']:
                for tool in processes['screen_capture']:
                    print(f"    • {tool}")
            
            permissions = status['permissions']
            print(f"\n🔑 System Permissions:")
            print(f"  User Groups: {len(permissions['user_groups'])}")
            print(f"  Sensitive Groups: {', '.join(permissions['sensitive_groups']) if permissions['sensitive_groups'] else 'None'}")
            print(f"  Sudo Access: {'Yes' if permissions['sudo_access'] else 'No'}")
            
            return
            
        elif command == "location-toggle":
            location = monitor.check_location_services()
            if location['geoclue_active']:
                try:
                    subprocess.run(['systemctl', '--user', 'stop', 'geoclue'], capture_output=True, timeout=3)
                    print("Location services disabled")
                except Exception as e:
                    print(f"Failed to disable location: {e}")
            else:
                try:
                    subprocess.run(['systemctl', '--user', 'start', 'geoclue'], capture_output=True, timeout=3)
                    print("Location services enabled")
                except Exception as e:
                    print(f"Failed to enable location: {e}")
            return
            
        elif command == "processes":
            processes = monitor.check_privacy_processes()
            print("=== Privacy-Related Processes ===")
            
            if processes['monitoring_tools']:
                print(f"\n👁️ Monitoring Tools ({len(processes['monitoring_tools'])}):")
                for tool in processes['monitoring_tools']:
                    print(f"  • {tool}")
            
            if processes['keyloggers']:
                print(f"\n⚠️ Potential Keyloggers ({len(processes['keyloggers'])}):")
                for keylogger in processes['keyloggers']:
                    print(f"  • {keylogger}")
                    
            if processes['screen_capture']:
                print(f"\n📸 Screen Capture Tools ({len(processes['screen_capture'])}):")
                for tool in processes['screen_capture']:
                    print(f"  • {tool}")
                    
            if not any([processes['monitoring_tools'], processes['keyloggers'], processes['screen_capture']]):
                print("No privacy-related processes detected")
            
            return

    # Default: return status
    status = monitor.get_status()
    output = monitor.format_output(status)
    print(json.dumps(output))

if __name__ == "__main__":
    main()
