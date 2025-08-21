#!/usr/bin/env python3
"""
Network Privacy Module for Waybar
Monitors VPN, Tor, connections, and DNS privacy
Enhanced with VPN control functionality
"""

import json
import subprocess
import sys
import time
import os
import glob
from typing import Dict, List

# Import password prompt helper
try:
    from password_prompt import run_sudo_command_with_output
except ImportError:
    # Fallback if password_prompt.py not available
    def run_sudo_command_with_output(command: List[str], title: str, description: str) -> tuple:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
            return result.returncode == 0, result.stdout, result.stderr
        except:
            return False, "", "Command failed"

class NetworkPrivacy:
    def __init__(self):
        self.icons = {
            'network_exposed': '🌐',
            'network_protected': '🔒',
            'network_vpn': '🛡️',
            'tor_active': '🧅',
            'dns_private': '🔐'
        }
        self._cache = {}
        self._cache_timeout = 2.0  # Network changes less frequently

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

    def get_wireguard_configs(self) -> List[str]:
        """Get list of available WireGuard configurations"""
        configs = []
        wg_dir = "/etc/wireguard"
        
        # Try direct access first
        if os.path.exists(wg_dir) and os.access(wg_dir, os.R_OK):
            try:
                config_files = glob.glob(os.path.join(wg_dir, "*.conf"))
                for config_file in config_files:
                    config_name = os.path.basename(config_file)[:-5]  # Remove .conf extension
                    configs.append(config_name)
                return sorted(configs)
            except PermissionError:
                pass
        
        # For background operations, don't prompt for password
        # User can explicitly list configs with 'vpn-list' command if needed
        return sorted(configs)

    def get_wireguard_configs_with_sudo(self) -> List[str]:
        """Get list of WireGuard configurations using sudo with output capture"""
        configs = []
        wg_dir = "/etc/wireguard"
        
        # First try without sudo
        configs = self.get_wireguard_configs()
        if configs:
            return configs
        
        # If no configs found and directory exists, use sudo with output capture
        if os.path.exists(wg_dir):
            cmd = ['find', wg_dir, '-name', '*.conf', '-type', 'f', '-exec', 'basename', '{}', '.conf', ';']
            success, stdout, stderr = run_sudo_command_with_output(cmd, 
                                     "List VPN Configurations", 
                                     "Reading WireGuard configurations from /etc/wireguard")
            
            if success and stdout:
                for line in stdout.strip().split('\n'):
                    config = line.strip()
                    if config:
                        configs.append(config)
        
        return sorted(configs)

    def get_active_wireguard_interfaces(self) -> List[str]:
        """Get list of currently active WireGuard interfaces"""
        active = []
        returncode, stdout, _ = self._run_command_fast(['wg', 'show'], 1.0)
        if returncode == 0 and stdout.strip():
            for line in stdout.strip().split('\n'):
                if ':' in line:
                    interface = line.split(':')[0].strip()
                    if interface:
                        active.append(interface)
        return active

    def vpn_up(self, config_name: str) -> tuple:
        """Bring up a WireGuard VPN connection using secure password prompt"""
        cmd = ['wg-quick', 'up', config_name]
        title = f"Connect VPN: {config_name}"
        description = f"Activating WireGuard configuration '{config_name}'"
        
        success = run_sudo_command(cmd, title, description)
        if success:
            return (0, f"VPN {config_name} activated", "")
        else:
            return (1, "", f"Failed to activate VPN {config_name}")

    def vpn_down(self, config_name: str) -> tuple:
        """Bring down a WireGuard VPN connection using secure password prompt"""
        cmd = ['wg-quick', 'down', config_name]
        title = f"Disconnect VPN: {config_name}"
        description = f"Deactivating WireGuard configuration '{config_name}'"
        
        success = run_sudo_command(cmd, title, description)
        if success:
            return (0, f"VPN {config_name} deactivated", "")
        else:
            return (1, "", f"Failed to deactivate VPN {config_name}")

    def show_vpn_rofi_menu(self) -> None:
        """Show rofi menu for VPN selection"""
        configs = self.get_wireguard_configs()
        
        # If no configs found with direct access, try sudo
        if not configs:
            configs = self.get_wireguard_configs_with_sudo()
        
        active = self.get_active_wireguard_interfaces()
        
        if not configs:
            subprocess.run(['notify-send', 'VPN Manager', 'No WireGuard configs found in /etc/wireguard'], 
                         capture_output=True)
            return

        # Build menu options
        menu_items = []
        for config in configs:
            if config in active:
                menu_items.append(f"🟢 {config} (ACTIVE) - Disconnect")
            else:
                menu_items.append(f"🔴 {config} (INACTIVE) - Connect")
        
        # Add disconnect all option if any VPNs are active
        if active:
            menu_items.append("❌ Disconnect All")

        menu_text = '\n'.join(menu_items)
        
        try:
            result = subprocess.run(
                ['rofi', '-dmenu', '-p', 'VPN Manager', '-theme-str', 
                 'listview { lines: 10; } window { width: 400px; }'],
                input=menu_text,
                text=True,
                capture_output=True
            )
            
            if result.returncode == 0 and result.stdout.strip():
                selection = result.stdout.strip()
                self._handle_vpn_selection(selection, active)
                
        except FileNotFoundError:
            subprocess.run(['notify-send', 'VPN Manager', 'Rofi not found. Install rofi for VPN menu.'], 
                         capture_output=True)

    def show_disconnect_menu(self) -> None:
        """Show rofi menu for disconnecting active VPNs"""
        active = self.get_active_wireguard_interfaces()
        
        if not active:
            subprocess.run(['notify-send', 'VPN Manager', 'No active VPN connections'], 
                         capture_output=True)
            return

        # Build disconnect menu
        menu_items = []
        for config in active:
            menu_items.append(f"🟢 {config} - Disconnect")
        
        menu_items.append("❌ Disconnect All")
        menu_text = '\n'.join(menu_items)
        
        try:
            result = subprocess.run(
                ['rofi', '-dmenu', '-p', 'Disconnect VPN', '-theme-str', 
                 'listview { lines: 8; } window { width: 350px; }'],
                input=menu_text,
                text=True,
                capture_output=True
            )
            
            if result.returncode == 0 and result.stdout.strip():
                selection = result.stdout.strip()
                
                if "Disconnect All" in selection:
                    for interface in active:
                        self.vpn_down(interface)
                    subprocess.run(['notify-send', 'VPN Manager', 'Disconnected all VPNs'], 
                                 capture_output=True)
                else:
                    # Extract config name
                    config_name = selection.split()[1]  # Get second word (config name)
                    returncode, stdout, stderr = self.vpn_down(config_name)
                    if returncode == 0:
                        subprocess.run(['notify-send', 'VPN Manager', f'Disconnected {config_name}'], 
                                     capture_output=True)
                    else:
                        subprocess.run(['notify-send', 'VPN Manager', f'Failed to disconnect {config_name}: {stderr}'], 
                                     capture_output=True)
                
        except FileNotFoundError:
            subprocess.run(['notify-send', 'VPN Manager', 'Rofi not found. Install rofi for VPN menu.'], 
                         capture_output=True)

    def _handle_vpn_selection(self, selection: str, active: List[str]) -> None:
        """Handle VPN selection from rofi menu"""
        if "Disconnect All" in selection:
            for interface in active:
                returncode, stdout, stderr = self.vpn_down(interface)
                if returncode == 0:
                    subprocess.run(['notify-send', 'VPN Manager', f'Disconnected {interface}'], 
                                 capture_output=True)
                else:
                    subprocess.run(['notify-send', 'VPN Manager', f'Failed to disconnect {interface}: {stderr}'], 
                                 capture_output=True)
        else:
            # Extract config name from selection
            config_name = None
            for line in selection.split():
                if line not in ['🟢', '🔴', '(ACTIVE)', '(INACTIVE)', '-', 'Connect', 'Disconnect']:
                    config_name = line
                    break
            
            if not config_name:
                return

            if "(ACTIVE)" in selection:
                # Disconnect
                returncode, stdout, stderr = self.vpn_down(config_name)
                if returncode == 0:
                    subprocess.run(['notify-send', 'VPN Manager', f'Disconnected {config_name}'], 
                                 capture_output=True)
                else:
                    subprocess.run(['notify-send', 'VPN Manager', f'Failed to disconnect {config_name}: {stderr}'], 
                                 capture_output=True)
            else:
                # Connect
                returncode, stdout, stderr = self.vpn_up(config_name)
                if returncode == 0:
                    subprocess.run(['notify-send', 'VPN Manager', f'Connected to {config_name}'], 
                                 capture_output=True)
                else:
                    subprocess.run(['notify-send', 'VPN Manager', f'Failed to connect {config_name}: {stderr}'], 
                                 capture_output=True)

    def check_vpn_status(self) -> Dict:
        return self._get_cached_or_run('vpn', self._check_vpn_impl)

    def _check_vpn_impl(self) -> Dict:
        status = {
            'active': False,
            'type': None,
            'interface': None,
            'active_configs': []
        }

        # Get active WireGuard interfaces
        active_interfaces = self.get_active_wireguard_interfaces()
        if active_interfaces:
            status['active'] = True
            status['type'] = 'WireGuard'
            status['interface'] = active_interfaces[0]  # Primary interface
            status['active_configs'] = active_interfaces

        if status['active']:
            return status

        # Check for WireGuard interfaces via ip command (fallback)
        returncode, stdout, _ = self._run_command_fast(['ip', 'link', 'show'], 1.0)
        if returncode == 0:
            for line in stdout.split('\n'):
                if 'wg' in line and ('state UP' in line or 'state UNKNOWN' in line):
                    if 'UP' in line and 'LOWER_UP' in line:
                        parts = line.split(':')
                        if len(parts) >= 2:
                            interface_name = parts[1].strip().split('@')[0]
                            if 'wg' in interface_name.lower():
                                status['active'] = True
                                status['type'] = 'WireGuard'
                                status['interface'] = interface_name
                                return status

        # Check for traditional VPN interfaces (TUN/TAP)
        returncode, stdout, _ = self._run_command_fast(['ip', 'route', 'show'], 2.0)
        if returncode == 0:
            routes = stdout.lower()
            if 'tun' in routes:
                status['active'] = True
                status['type'] = 'OpenVPN/TUN'
                for line in stdout.split('\n'):
                    if 'tun' in line and 'dev' in line:
                        parts = line.split()
                        for i, part in enumerate(parts):
                            if part == 'dev' and i + 1 < len(parts):
                                status['interface'] = parts[i + 1]
                                break
                        break

        # Check for VPN processes (fallback)
        if not status['active']:
            vpn_processes = ['openvpn', 'wireguard', 'nordvpn', 'expressvpn']
            for process in vpn_processes:
                returncode, stdout, _ = self._run_command_fast(['pgrep', '-c', process], 0.5)
                if returncode == 0 and stdout.strip() != '0':
                    status['active'] = True
                    if not status['type']:
                        status['type'] = process.title()

        return status

    def check_tor_status(self) -> Dict:
        return self._get_cached_or_run('tor', self._check_tor_impl)

    def _check_tor_impl(self) -> Dict:
        status = {
            'active': False,
            'connections': 0,
            'control_port': False
        }

        # Check for Tor process
        returncode, stdout, _ = self._run_command_fast(['pgrep', '-x', 'tor'], 0.5)
        
        if returncode == 0 and stdout.strip() != '0':
            status['active'] = True

        # Check for Tor connections
        returncode, stdout, _ = self._run_command_fast(['ss', '-tn'], 1.0)
        if returncode == 0:
            tor_ports = ['9050', '9051', '9150']  # Common Tor ports
            for line in stdout.split('\n'):
                if any(port in line for port in tor_ports):
                    status['connections'] += 1
                    if '9051' in line:  # Control port
                        status['control_port'] = True

        return status

    def check_connections(self) -> Dict:
        return self._get_cached_or_run('connections', self._check_connections_impl)

    def _check_connections_impl(self) -> Dict:
        status = {
            'external_count': 0,
            'local_count': 0,
            'suspicious': []
        }

        returncode, stdout, _ = self._run_command_fast(['ss', '-tn'], 1.5)
        if returncode == 0:
            lines = stdout.split('\n')[1:]  # Skip header
            for line in lines:
                if line.strip() and 'ESTAB' in line:
                    parts = line.split()
                    if len(parts) >= 5:
                        foreign_addr = parts[4] if len(parts) > 4 else ''
                        
                        # Check if external connection
                        if not any(local in foreign_addr for local in ['127.0.0.1', '::1', '0.0.0.0', '192.168.', '10.', '172.16.']):
                            status['external_count'] += 1
                            
                            # Check for suspicious ports
                            if any(port in foreign_addr for port in [':22', ':23', ':3389', ':5900']):
                                status['suspicious'].append(foreign_addr)
                        else:
                            status['local_count'] += 1

        return status

    def check_dns_privacy(self) -> Dict:
        return self._get_cached_or_run('dns', self._check_dns_impl)

    def _check_dns_impl(self) -> Dict:
        status = {
            'private_dns': False,
            'dns_servers': [],
            'dns_over_https': False
        }

        try:
            with open('/etc/resolv.conf', 'r') as f:
                content = f.read()
                
                for line in content.split('\n'):
                    if line.startswith('nameserver'):
                        dns = line.split()[1] if len(line.split()) > 1 else ''
                        status['dns_servers'].append(dns)
                        
                        # Check for privacy-focused DNS
                        privacy_dns = ['1.1.1.1', '9.9.9.9', '8.8.8.8', '1.0.0.1', '149.112.112.112']
                        if dns in privacy_dns:
                            status['private_dns'] = True
        except:
            pass

        # Check for DNS over HTTPS (DoH) processes
        doh_processes = ['systemd-resolved', 'unbound', 'pihole-FTL']
        for process in doh_processes:
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-c', process], 0.5)
            if returncode == 0 and stdout.strip() != '0':
                status['dns_over_https'] = True

        return status

    def get_status(self) -> Dict:
        return {
            'vpn': self.check_vpn_status(),
            'tor': self.check_tor_status(),
            'connections': self.check_connections(),
            'dns': self.check_dns_privacy()
        }

    def format_output(self, status: Dict) -> Dict:
        active_indicators = []
        tooltip_lines = []
        css_classes = []

        vpn = status['vpn']
        tor = status['tor']
        connections = status['connections']
        dns = status['dns']

        # Priority: Tor > VPN > Exposed
        if tor['active']:
            active_indicators.append(self.icons['tor_active'])
            css_classes.append('tor-active')
            tooltip_lines.append("🧅 TOR ACTIVE")
            if tor['connections'] > 0:
                tooltip_lines.append(f"  • {tor['connections']} Tor connections")
        elif vpn['active']:
            active_indicators.append(self.icons['network_vpn'])
            css_classes.append('vpn-active')
            tooltip_lines.append(f"🛡️ VPN ACTIVE: {vpn['type']}")
            if vpn['interface']:
                tooltip_lines.append(f"  • Interface: {vpn['interface']}")
            if vpn.get('active_configs'):
                tooltip_lines.append(f"  • Configs: {', '.join(vpn['active_configs'])}")
        elif connections['external_count'] > 5:
            active_indicators.append(self.icons['network_exposed'])
            css_classes.append('network-exposed')
            tooltip_lines.append(f"🌐 EXPOSED: {connections['external_count']} external connections")
        else:
            active_indicators.append(self.icons['network_protected'])
            css_classes.append('network-protected')

        # DNS Privacy indicator
        if dns['private_dns'] or dns['dns_over_https']:
            active_indicators.append(self.icons['dns_private'])
            css_classes.append('dns-private')
            tooltip_lines.append("🔐 DNS: Privacy enhanced")

        # Warnings
        if connections['suspicious']:
            tooltip_lines.append("⚠️ Suspicious connections:")
            for conn in connections['suspicious'][:3]:
                tooltip_lines.append(f"  • {conn}")

        tooltip_text = "\n".join(tooltip_lines) if tooltip_lines else "Network: Secure 🔒"
        
        return {
            "text": " ".join(active_indicators) if active_indicators else "🔒",
            "tooltip": tooltip_text,
            "class": " ".join(css_classes) if css_classes else "network-secure"
        }

def main():
    monitor = NetworkPrivacy()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "status":
            status = monitor.get_status()
            print("=== Network Privacy Status ===")
            
            vpn = status['vpn']
            print(f"\n🛡️ VPN: {'Active' if vpn['active'] else 'Inactive'}")
            if vpn['active']:
                print(f"  Type: {vpn['type']}")
                if vpn['interface']:
                    print(f"  Interface: {vpn['interface']}")
                if vpn.get('active_configs'):
                    print(f"  Active Configs: {', '.join(vpn['active_configs'])}")
            
            tor = status['tor']
            print(f"\n🧅 Tor: {'Active' if tor['active'] else 'Inactive'}")
            if tor['active']:
                print(f"  Connections: {tor['connections']}")
                print(f"  Control Port: {'Yes' if tor['control_port'] else 'No'}")
            
            connections = status['connections']
            print(f"\n🌐 Connections:")
            print(f"  External: {connections['external_count']}")
            print(f"  Local: {connections['local_count']}")
            if connections['suspicious']:
                print(f"  Suspicious: {len(connections['suspicious'])}")
            
            dns = status['dns']
            print(f"\n🔐 DNS Privacy:")
            print(f"  Private DNS: {'Yes' if dns['private_dns'] else 'No'}")
            print(f"  DNS over HTTPS: {'Yes' if dns['dns_over_https'] else 'No'}")
            print(f"  Servers: {', '.join(dns['dns_servers'])}")
            return
            
        elif command == "connections":
            connections = monitor.check_connections()
            print("=== Network Connections ===")
            print(f"External: {connections['external_count']}")
            print(f"Local: {connections['local_count']}")
            if connections['suspicious']:
                print("\nSuspicious connections:")
                for conn in connections['suspicious']:
                    print(f"  • {conn}")
            return
            
        elif command == "vpn-menu":
            monitor.show_vpn_rofi_menu()
            return
            
        elif command == "vpn-disconnect":
            monitor.show_disconnect_menu()
            return
            
        elif command == "vpn-list":
            configs = monitor.get_wireguard_configs_with_sudo()
            active = monitor.get_active_wireguard_interfaces()
            print("=== WireGuard Configurations ===")
            if not configs:
                print("No configurations found in /etc/wireguard")
                print("This may require sudo access to read /etc/wireguard")
            else:
                for config in configs:
                    status_str = "ACTIVE" if config in active else "inactive"
                    print(f"  • {config} ({status_str})")
            return
            
        elif command.startswith("vpn-up:"):
            config_name = command.split(":", 1)[1]
            success = monitor.vpn_up(config_name)
            if success:
                print(f"✅ Connected to {config_name}")
            else:
                print(f"❌ Failed to connect {config_name}")
            return
            
        elif command.startswith("vpn-down:"):
            config_name = command.split(":", 1)[1]
            success = monitor.vpn_down(config_name)
            if success:
                print(f"✅ Disconnected {config_name}")
            else:
                print(f"❌ Failed to disconnect {config_name}")
            return

        elif command == "toggle-vpn":
            print("VPN Control Options:")
            print("  • VPN Menu: denv-shell network_privacy vpn-menu")
            print("  • List VPNs: denv-shell network_privacy vpn-list")
            print("  • Connect: denv-shell network_privacy vpn-up:<config>")
            print("  • Disconnect: denv-shell network_privacy vpn-down:<config>")
            return

    # Default: return status
    status = monitor.get_status()
    output = monitor.format_output(status)
    print(json.dumps(output))

if __name__ == "__main__":
    main()