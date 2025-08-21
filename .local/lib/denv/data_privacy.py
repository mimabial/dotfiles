#!/usr/bin/env python3
"""
Data Privacy Module for Waybar
Monitors clipboard access and file sharing
"""

import json
import subprocess
import sys
import time
from typing import Dict, List

class DataPrivacy:
    def __init__(self):
        self.icons = {
            'clipboard_active': '📋',
            'clipboard_sensitive': '🔐',
            'file_sharing': '📁',
            'file_access': '🗂️',
            'sandboxed': '📦',
            'data_warning': '⚠️'
        }
        self._cache = {}
        self._cache_timeout = 1.0  # Data changes frequently

    def _get_cached_or_run(self, key: str, func, *args, **kwargs):
        now = time.time()
        if key in self._cache:
            result, timestamp = self._cache[key]
            if now - timestamp < self._cache_timeout:
                return result
        
        result = func(*args, **kwargs)
        self._cache[key] = (result, now)
        return result

    def _run_command_fast(self, cmd: List[str], timeout: float = 0.5) -> tuple:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return result.returncode, result.stdout, result.stderr
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return -1, "", "timeout/not found"

    def check_clipboard_status(self) -> Dict:
        return self._get_cached_or_run('clipboard', self._check_clipboard_impl)

    def _check_clipboard_impl(self) -> Dict:
        status = {
            'managers_active': [],
            'content_types': [],
            'content_size': 0,
            'has_sensitive_content': False,
            'clipboard_accessible': False
        }

        # Check for clipboard managers
        clipboard_apps = ['clipman', 'copyq', 'parcellite', 'clipit', 'greenclip']
        for app in clipboard_apps:
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-c', app])
            if returncode == 0 and stdout.strip() != '0':
                count = stdout.strip()
                status['managers_active'].append(f"{app} ({count})")

        # Check clipboard content (Wayland)
        returncode, stdout, _ = self._run_command_fast(['wl-paste', '--list-types'], 0.5)
        if returncode == 0:
            status['clipboard_accessible'] = True
            types = [t.strip() for t in stdout.split('\n') if t.strip()]
            status['content_types'] = types
            status['content_size'] = len(types)
            
            # Check for sensitive content types
            sensitive_types = ['text/plain', 'text/html', 'image/png', 'image/jpeg']
            if any(t in types for t in sensitive_types):
                status['has_sensitive_content'] = True
                
                # Quick size check for text content
                if 'text/plain' in types:
                    returncode, stdout, _ = self._run_command_fast(['wl-paste', '-t', 'text/plain'], 0.3)
                    if returncode == 0 and len(stdout) > 50:  # Substantial text content
                        status['has_sensitive_content'] = True

        # Fallback to X11 if Wayland failed
        if not status['clipboard_accessible']:
            returncode, stdout, _ = self._run_command_fast(['xclip', '-selection', 'clipboard', '-o'], 0.5)
            if returncode == 0:
                status['clipboard_accessible'] = True
                content = stdout.strip()
                status['content_size'] = len(content)
                if content and len(content) > 20:
                    status['has_sensitive_content'] = True

        return status

    def check_file_sharing_status(self) -> Dict:
        return self._get_cached_or_run('filesharing', self._check_filesharing_impl)

    def _check_filesharing_impl(self) -> Dict:
        status = {
            'sharing_services': [],
            'network_shares': [],
            'ftp_active': False,
            'http_serving': False
        }

        # Check for file sharing services
        sharing_services = {
            'smbd': 'Samba/SMB',
            'nmbd': 'NetBIOS',
            'nfsd': 'NFS Server',
            'vsftpd': 'FTP Server',
            'proftpd': 'ProFTPD',
            'syncthing': 'Syncthing',
            'rsyncd': 'Rsync Daemon'
        }

        for process, name in sharing_services.items():
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-c', process])
            if returncode == 0 and stdout.strip() != '0':
                status['sharing_services'].append(name)

        # Check for HTTP servers that might be serving files
        http_servers = ['apache2', 'nginx', 'lighttpd', 'caddy', 'python3 -m http.server']
        for server in http_servers:
            returncode, stdout, _ = self._run_command_fast(['pgrep', '-f', server])
            if returncode == 0:
                status['http_serving'] = True
                break

        # Check for active network shares
        try:
            returncode, stdout, _ = self._run_command_fast(['mount', '-t', 'cifs,nfs'], 1.0)
            if returncode == 0:
                lines = [line for line in stdout.split('\n') if line.strip()]
                status['network_shares'] = lines[:3]  # Limit display
        except:
            pass

        return status

    def check_sandboxed_apps(self) -> Dict:
        return self._get_cached_or_run('sandbox', self._check_sandbox_impl)

    def _check_sandbox_impl(self) -> Dict:
        status = {
            'flatpak_count': 0,
            'snap_count': 0,
            'appimage_count': 0,
            'flatpak_apps': [],
            'snap_apps': []
        }

        # Check Flatpak apps
        returncode, stdout, _ = self._run_command_fast(['flatpak', 'list', '--columns=name'], 1.0)
        if returncode == 0:
            apps = [line.strip() for line in stdout.split('\n') if line.strip()]
            status['flatpak_count'] = len(apps)
            status['flatpak_apps'] = apps[:3]  # Show first 3

        # Check Snap apps
        returncode, stdout, _ = self._run_command_fast(['snap', 'list'], 1.0)
        if returncode == 0:
            lines = [line.strip() for line in stdout.split('\n')[1:] if line.strip()]  # Skip header
            status['snap_count'] = len(lines)
            # Extract app names (first column)
            for line in lines[:3]:
                app_name = line.split()[0] if line.split() else ''
                if app_name:
                    status['snap_apps'].append(app_name)

        # Quick AppImage check (running processes)
        returncode, stdout, _ = self._run_command_fast(['pgrep', '-f', '.AppImage'], 0.5)
        if returncode == 0:
            status['appimage_count'] = len(stdout.strip().split('\n'))

        return status

    def get_status(self) -> Dict:
        return {
            'clipboard': self.check_clipboard_status(),
            'filesharing': self.check_file_sharing_status(),
            'sandbox': self.check_sandboxed_apps()
        }

    def format_output(self, status: Dict) -> Dict:
        active_indicators = []
        tooltip_lines = []
        css_classes = []

        clipboard = status['clipboard']
        filesharing = status['filesharing']
        sandbox = status['sandbox']

        # Clipboard status
        if clipboard['managers_active'] or clipboard['has_sensitive_content']:
            active_indicators.append(self.icons['clipboard_active'])
            css_classes.append('clipboard-active')
            
            if clipboard['has_sensitive_content']:
                tooltip_lines.append("📋 CLIPBOARD: Sensitive content detected")
                css_classes.append('clipboard-sensitive')
            else:
                tooltip_lines.append("📋 CLIPBOARD: Active managers")
                
            if clipboard['managers_active']:
                for manager in clipboard['managers_active']:
                    tooltip_lines.append(f"  • {manager}")
                    
            if clipboard['content_size'] > 0:
                tooltip_lines.append(f"  • Content: {clipboard['content_size']} items")

        # File sharing status
        if filesharing['sharing_services'] or filesharing['http_serving']:
            active_indicators.append(self.icons['file_sharing'])
            css_classes.append('file-sharing-active')
            tooltip_lines.append("📁 FILE SHARING ACTIVE:")
            
            for service in filesharing['sharing_services']:
                tooltip_lines.append(f"  • {service}")
                
            if filesharing['http_serving']:
                tooltip_lines.append("  • HTTP Server")
                
            css_classes.append('security-warning')

        # Sandboxed apps (positive security indicator)
        total_sandboxed = sandbox['flatpak_count'] + sandbox['snap_count'] + sandbox['appimage_count']
        if total_sandboxed > 0:
            active_indicators.append(self.icons['sandboxed'])
            css_classes.append('apps-sandboxed')
            tooltip_lines.append(f"📦 SANDBOXED APPS: {total_sandboxed} total")
            
            if sandbox['flatpak_count'] > 0:
                tooltip_lines.append(f"  • Flatpak: {sandbox['flatpak_count']}")
            if sandbox['snap_count'] > 0:
                tooltip_lines.append(f"  • Snap: {sandbox['snap_count']}")
            if sandbox['appimage_count'] > 0:
                tooltip_lines.append(f"  • AppImage: {sandbox['appimage_count']}")

        # Security warnings
        if clipboard['has_sensitive_content'] and clipboard['managers_active']:
            tooltip_lines.append("")
            tooltip_lines.append("⚠️ Sensitive data + clipboard managers")
            
        if filesharing['sharing_services']:
            css_classes.append('data-exposed')

        tooltip_text = "\n".join(tooltip_lines) if tooltip_lines else "Data: Secure 🔒"
        
        return {
            "text": " ".join(active_indicators) if active_indicators else "🔒",
            "tooltip": tooltip_text,
            "class": " ".join(css_classes) if css_classes else "data-secure"
        }

def main():
    monitor = DataPrivacy()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "status":
            status = monitor.get_status()
            print("=== Data Privacy Status ===")
            
            clipboard = status['clipboard']
            print(f"\n📋 Clipboard:")
            print(f"  Accessible: {'Yes' if clipboard['clipboard_accessible'] else 'No'}")
            print(f"  Content Size: {clipboard['content_size']} items")
            print(f"  Sensitive Content: {'Yes' if clipboard['has_sensitive_content'] else 'No'}")
            
            if clipboard['managers_active']:
                print(f"  Active Managers:")
                for manager in clipboard['managers_active']:
                    print(f"    • {manager}")
                    
            if clipboard['content_types']:
                print(f"  Content Types: {', '.join(clipboard['content_types'][:3])}")
            
            filesharing = status['filesharing']
            print(f"\n📁 File Sharing:")
            print(f"  Active: {'Yes' if filesharing['sharing_services'] else 'No'}")
            
            if filesharing['sharing_services']:
                print("  Services:")
                for service in filesharing['sharing_services']:
                    print(f"    • {service}")
                    
            print(f"  HTTP Serving: {'Yes' if filesharing['http_serving'] else 'No'}")
            
            if filesharing['network_shares']:
                print("  Network Shares:")
                for share in filesharing['network_shares']:
                    print(f"    • {share}")
            
            sandbox = status['sandbox']
            total_sandboxed = sandbox['flatpak_count'] + sandbox['snap_count'] + sandbox['appimage_count']
            print(f"\n📦 Sandboxed Apps: {total_sandboxed} total")
            print(f"  Flatpak: {sandbox['flatpak_count']}")
            print(f"  Snap: {sandbox['snap_count']}")
            print(f"  AppImage: {sandbox['appimage_count']}")
            
            return
            
        elif command == "clear-clipboard":
            try:
                # Try Wayland first
                returncode, _, _ = subprocess.run(['wl-copy', '--clear'], 
                                                capture_output=True, timeout=2)
                if returncode == 0:
                    print("Clipboard cleared (Wayland)")
                else:
                    # Fallback to X11
                    subprocess.run(['xsel', '-bc'], capture_output=True, timeout=2)
                    print("Clipboard cleared (X11)")
            except Exception as e:
                print(f"Failed to clear clipboard: {e}")
            return
            
        elif command == "clipboard-content":
            clipboard = monitor.check_clipboard_status()
            print("=== Clipboard Content Analysis ===")
            
            if clipboard['clipboard_accessible']:
                print(f"Content Size: {clipboard['content_size']} items")
                print(f"Sensitive: {'Yes' if clipboard['has_sensitive_content'] else 'No'}")
                
                if clipboard['content_types']:
                    print("Content Types:")
                    for content_type in clipboard['content_types'][:5]:
                        print(f"  • {content_type}")
                    if len(clipboard['content_types']) > 5:
                        print(f"  • ... and {len(clipboard['content_types']) - 5} more")
            else:
                print("Clipboard not accessible")
            return

    # Default: return status
    status = monitor.get_status()
    output = monitor.format_output(status)
    print(json.dumps(output))

if __name__ == "__main__":
    main()
