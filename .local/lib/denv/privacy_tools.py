#!/usr/bin/env python3
"""
Privacy Tools & Debug Module for Waybar
Provides debugging and analysis tools for privacy monitoring
"""

import json
import subprocess
import sys
import time
import glob
from typing import Dict, List

class PrivacyTools:
    def __init__(self):
        self.icons = {
            'debug_active': '🔧',
            'analysis': '📊',
            'warning': '⚠️',
            'info': 'ℹ️',
            'success': '✅',
            'error': '❌'
        }

    def _run_command_safe(self, cmd: List[str], timeout: float = 2.0) -> tuple:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return result.returncode, result.stdout, result.stderr
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return -1, "", "timeout/not found"

    def run_in_terminal(self, command: str, title: str = "Privacy Tools") -> bool:
        """Run a command in a terminal window"""
        terminals = [
            ['alacritty', '-t', title, '-e', 'sh', '-c'],
            ['kitty', '--title', title, 'sh', '-c'],
            ['foot', '--title', title, 'sh', '-c'],
            ['gnome-terminal', '--title', title, '--', 'sh', '-c'],
            ['konsole', '--title', title, '-e', 'sh', '-c'],
            ['xterm', '-T', title, '-e', 'sh', '-c']
        ]
        
        for terminal_cmd in terminals:
            try:
                if subprocess.run(['which', terminal_cmd[0]], capture_output=True).returncode == 0:
                    full_cmd = terminal_cmd + [f'{command}; echo "\nPress Enter to close..."; read']
                    subprocess.Popen(full_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    return True
            except:
                continue
        return False

    def debug_camera_system(self) -> Dict:
        """Debug camera detection and control"""
        debug_info = {
            'video_devices': [],
            'camera_modules': [],
            'v4l2_info': {},
            'processes_using_camera': [],
            'pipewire_nodes': []
        }

        # Check video devices
        video_devices = glob.glob('/dev/video*')
        debug_info['video_devices'] = video_devices

        # Check loaded camera modules
        returncode, stdout, _ = self._run_command_safe(['lsmod'], 2.0)
        if returncode == 0:
            camera_modules = []
            for line in stdout.split('\n'):
                module = line.split()[0] if line.split() else ''
                if any(cam in module.lower() for cam in ['uvc', 'gspca', 'camera', 'video']):
                    camera_modules.append(module)
            debug_info['camera_modules'] = camera_modules

        # Get v4l2 info for each device
        for device in video_devices[:3]:  # Limit to first 3
            try:
                returncode, stdout, _ = self._run_command_safe(['v4l2-ctl', '--device', device, '--info'], 1.0)
                if returncode == 0:
                    debug_info['v4l2_info'][device] = stdout[:200]  # Truncate for display
            except:
                pass

        # Check processes using video devices
        for device in video_devices:
            try:
                returncode, stdout, _ = self._run_command_safe(['lsof', device], 1.0)
                if returncode == 0 and stdout.strip():
                    lines = stdout.strip().split('\n')[1:]  # Skip header
                    for line in lines:
                        parts = line.split()
                        if len(parts) > 1:
                            debug_info['processes_using_camera'].append({
                                'device': device,
                                'process': parts[0],
                                'pid': parts[1]
                            })
            except:
                continue

        # Check PipeWire video nodes
        try:
            returncode, stdout, _ = self._run_command_safe(['pw-dump'], 3.0)
            if returncode == 0:
                data = json.loads(stdout)
                for item in data:
                    if item.get('type') == 'PipeWire:Interface:Node':
                        props = item.get('info', {}).get('props', {})
                        media_class = props.get('media.class', '')
                        if 'Video' in media_class:
                            node_info = {
                                'class': media_class,
                                'name': props.get('node.name', 'Unknown'),
                                'app': props.get('application.name', 'Unknown')
                            }
                            debug_info['pipewire_nodes'].append(node_info)
        except:
            pass

        return debug_info

    def debug_network_privacy(self) -> Dict:
        """Debug network privacy configuration"""
        debug_info = {
            'interfaces': [],
            'routes': [],
            'dns_config': {},
            'firewall_status': {},
            'vpn_indicators': [],
            'suspicious_connections': []
        }

        # Network interfaces
        returncode, stdout, _ = self._run_command_safe(['ip', 'addr', 'show'], 2.0)
        if returncode == 0:
            current_interface = None
            for line in stdout.split('\n'):
                if ': ' in line and not line.startswith(' '):
                    interface = line.split(':')[1].strip().split('@')[0]
                    current_interface = interface
                    debug_info['interfaces'].append(interface)

        # Routes
        returncode, stdout, _ = self._run_command_safe(['ip', 'route', 'show'], 1.0)
        if returncode == 0:
            routes = [line.strip() for line in stdout.split('\n')[:5] if line.strip()]
            debug_info['routes'] = routes

        # DNS configuration
        try:
            with open('/etc/resolv.conf', 'r') as f:
                content = f.read()
                debug_info['dns_config']['resolv_conf'] = content[:300]  # Truncate
        except:
            debug_info['dns_config']['resolv_conf'] = "Could not read"

        # Firewall status
        returncode, stdout, _ = self._run_command_safe(['ufw', 'status'], 1.0)
        if returncode == 0:
            debug_info['firewall_status']['ufw'] = stdout.strip()[:100]

        returncode, stdout, _ = self._run_command_safe(['iptables', '-L', '-n'], 1.0)
        if returncode == 0:
            rule_count = len([line for line in stdout.split('\n') if line.strip() and not line.startswith('Chain')])
            debug_info['firewall_status']['iptables_rules'] = rule_count

        return debug_info

    def analyze_privacy_exposure(self) -> Dict:
        """Analyze overall privacy exposure"""
        analysis = {
            'risk_level': 'low',
            'concerns': [],
            'recommendations': [],
            'score': 0
        }

        concerns = []
        score = 100  # Start with perfect score

        # Check for active cameras
        video_devices = glob.glob('/dev/video*')
        if video_devices:
            for device in video_devices:
                try:
                    returncode, stdout, _ = self._run_command_safe(['lsof', device], 0.5)
                    if returncode == 0 and stdout.strip():
                        concerns.append("Camera in active use")
                        score -= 15
                        break
                except:
                    pass

        # Check for VPN
        returncode, stdout, _ = self._run_command_safe(['ip', 'route', 'show'], 1.0)
        if returncode == 0:
            if not any(vpn in stdout.lower() for vpn in ['tun', 'tap', 'wg']):
                concerns.append("No VPN detected")
                score -= 20

        # Check for Bluetooth discoverability
        returncode, stdout, _ = self._run_command_safe(['bluetoothctl', 'show'], 1.0)
        if returncode == 0 and 'discoverable: yes' in stdout.lower():
            concerns.append("Bluetooth discoverable")
            score -= 10

        # Check for file sharing
        sharing_services = ['smbd', 'nfsd', 'vsftpd']
        for service in sharing_services:
            returncode, stdout, _ = self._run_command_safe(['pgrep', service], 0.5)
            if returncode == 0:
                concerns.append(f"File sharing active ({service})")
                score -= 15

        # Check external connections
        returncode, stdout, _ = self._run_command_safe(['ss', '-tn'], 1.0)
        if returncode == 0:
            external_count = 0
            for line in stdout.split('\n'):
                if 'ESTAB' in line and not any(local in line for local in ['127.0.0.1', '::1', '192.168.']):
                    external_count += 1
            
            if external_count > 10:
                concerns.append(f"Many external connections ({external_count})")
                score -= 10

        analysis['concerns'] = concerns
        analysis['score'] = max(0, score)

        # Determine risk level
        if score >= 80:
            analysis['risk_level'] = 'low'
        elif score >= 60:
            analysis['risk_level'] = 'medium'
        else:
            analysis['risk_level'] = 'high'

        # Generate recommendations
        recommendations = []
        if "No VPN detected" in concerns:
            recommendations.append("Consider using a VPN for network privacy")
        if "Bluetooth discoverable" in concerns:
            recommendations.append("Disable Bluetooth discoverability")
        if any("File sharing" in c for c in concerns):
            recommendations.append("Review file sharing services")
        if "Camera in active use" in concerns:
            recommendations.append("Verify camera usage is intentional")

        analysis['recommendations'] = recommendations

        return analysis

    def comprehensive_report(self) -> Dict:
        """Generate comprehensive privacy report"""
        report = {
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
            'camera_debug': self.debug_camera_system(),
            'network_debug': self.debug_network_privacy(),
            'privacy_analysis': self.analyze_privacy_exposure(),
            'system_info': {}
        }

        # Basic system info
        returncode, stdout, _ = self._run_command_safe(['uname', '-a'], 1.0)
        if returncode == 0:
            report['system_info']['kernel'] = stdout.strip()

        returncode, stdout, _ = self._run_command_safe(['whoami'], 0.5)
        if returncode == 0:
            report['system_info']['user'] = stdout.strip()

        return report

    def get_status(self) -> Dict:
        """Get current tools status"""
        return {
            'analysis_available': True,
            'debug_tools': ['camera', 'network', 'privacy'],
            'last_run': 'Never'
        }

    def format_output(self, status: Dict) -> Dict:
        """Format output for Waybar"""
        return {
            "text": self.icons['debug_active'],
            "tooltip": "Privacy Tools & Debug\nClick for analysis options",
            "class": "privacy-tools"
        }

def main():
    tools = PrivacyTools()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "debug-camera":
            print("=== Camera System Debug ===")
            debug_info = tools.debug_camera_system()
            
            print(f"\n📹 Video Devices: {len(debug_info['video_devices'])}")
            for device in debug_info['video_devices']:
                print(f"  • {device}")
                if device in debug_info['v4l2_info']:
                    print(f"    Info: {debug_info['v4l2_info'][device][:100]}...")
            
            print(f"\n🔧 Camera Modules: {len(debug_info['camera_modules'])}")
            for module in debug_info['camera_modules']:
                print(f"  • {module}")
            
            print(f"\n🎯 Processes Using Camera: {len(debug_info['processes_using_camera'])}")
            for proc in debug_info['processes_using_camera']:
                print(f"  • {proc['device']}: {proc['process']} (PID: {proc['pid']})")
            
            print(f"\n🎵 PipeWire Video Nodes: {len(debug_info['pipewire_nodes'])}")
            for node in debug_info['pipewire_nodes'][:5]:
                print(f"  • {node['name']} ({node['class']})")
            
            return
            
        elif command == "debug-network":
            print("=== Network Privacy Debug ===")
            debug_info = tools.debug_network_privacy()
            
            print(f"\n🌐 Network Interfaces: {len(debug_info['interfaces'])}")
            for interface in debug_info['interfaces']:
                print(f"  • {interface}")
            
            print(f"\n🛣️ Routes:")
            for route in debug_info['routes'][:3]:
                print(f"  • {route}")
            
            print(f"\n🔐 DNS Configuration:")
            if debug_info['dns_config'].get('resolv_conf'):
                lines = debug_info['dns_config']['resolv_conf'].split('\n')[:3]
                for line in lines:
                    if line.strip():
                        print(f"  • {line}")
            
            print(f"\n🛡️ Firewall Status:")
            if 'ufw' in debug_info['firewall_status']:
                print(f"  • UFW: {debug_info['firewall_status']['ufw'].split()[1] if debug_info['firewall_status']['ufw'].split() else 'unknown'}")
            if 'iptables_rules' in debug_info['firewall_status']:
                print(f"  • iptables: {debug_info['firewall_status']['iptables_rules']} rules")
            
            return
            
        elif command == "privacy-analysis":
            print("=== Privacy Exposure Analysis ===")
            analysis = tools.analyze_privacy_exposure()
            
            print(f"\n📊 Privacy Score: {analysis['score']}/100")
            print(f"🚦 Risk Level: {analysis['risk_level'].upper()}")
            
            if analysis['concerns']:
                print(f"\n⚠️ Privacy Concerns ({len(analysis['concerns'])}):")
                for concern in analysis['concerns']:
                    print(f"  • {concern}")
            else:
                print(f"\n✅ No privacy concerns detected")
            
            if analysis['recommendations']:
                print(f"\n💡 Recommendations:")
                for rec in analysis['recommendations']:
                    print(f"  • {rec}")
            
            return
            
        elif command == "comprehensive-report":
            print("=== Comprehensive Privacy Report ===")
            report = tools.comprehensive_report()
            
            print(f"\nGenerated: {report['timestamp']}")
            print(f"User: {report['system_info'].get('user', 'unknown')}")
            print(f"System: {report['system_info'].get('kernel', 'unknown')[:50]}...")
            
            # Summary stats
            camera = report['camera_debug']
            network = report['network_debug']
            analysis = report['privacy_analysis']
            
            print(f"\n📊 Summary:")
            print(f"  Video Devices: {len(camera['video_devices'])}")
            print(f"  Camera Modules: {len(camera['camera_modules'])}")
            print(f"  Network Interfaces: {len(network['interfaces'])}")
            print(f"  Privacy Score: {analysis['score']}/100")
            print(f"  Risk Level: {analysis['risk_level'].upper()}")
            print(f"  Concerns: {len(analysis['concerns'])}")
            
            return
            
        elif command == "open-settings":
            # Try to open various privacy-related settings
            settings_options = [
                ['gnome-control-center', 'privacy'],
                ['systemsettings5', 'privacy'],
                ['pavucontrol'],  # Audio settings
                ['nm-connection-editor'],  # Network settings
            ]
            
            for app_cmd in settings_options:
                try:
                    if subprocess.run(['which', app_cmd[0]], capture_output=True).returncode == 0:
                        subprocess.Popen(app_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        print(f"Opened {app_cmd[0]}")
                        return
                except:
                    continue
            
            print("No compatible settings application found")
            return

    # Default: return status
    status = tools.get_status()
    output = tools.format_output(status)
    print(json.dumps(output))

if __name__ == "__main__":
    main()
