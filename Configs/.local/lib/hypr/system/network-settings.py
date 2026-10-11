#!/usr/bin/env python3
import argparse
import ipaddress
import json
import subprocess
import sys

DNS_PROVIDERS = {
    "Cloudflare": ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"],
    "Google": ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"],
}
BANDS = {"auto": "", "2.4": "bg", "5": "a", "6": "6GHz"}
DNS_FIELDS = ["ipv4.ignore-auto-dns", "ipv4.dns", "ipv6.ignore-auto-dns", "ipv6.dns"]


WIFI_BANDS_MHZ = {"2.4": (2400, 2500), "5": (4900, 5925), "6": (5925, 7125)}


def networkmanager_output(*args):
    return subprocess.run(["nmcli", "--escape", "no", *args], check=True, text=True, capture_output=True).stdout


def connection_fields(connection_uuid, fields):
    return networkmanager_output("--get-values", ",".join(fields), "connection", "show", "uuid", connection_uuid).splitlines()


def wifi_band_for_frequency(frequency):
    return next((band for band, (low, high) in WIFI_BANDS_MHZ.items() if low <= frequency < high), "")


def connection_status(connection_uuid, interface_name):
    flags4, dns4, flags6, dns6 = connection_fields(connection_uuid, DNS_FIELDS)
    servers = dns4.replace(",", " ").split() + dns6.replace(",", " ").split()
    mode = "DHCP" if flags4 == flags6 == "no" else next((name for name, preset in DNS_PROVIDERS.items() if sorted(servers) == sorted(preset)), "Custom")
    result = {"dnsMode": mode, "dnsServers": " ".join(servers), "bands": [], "selectedBand": "auto"}
    if networkmanager_output("--get-values", "connection.type", "connection", "show", "uuid", connection_uuid).strip() == "802-11-wireless":
        ssid, selected = connection_fields(connection_uuid, ["802-11-wireless.ssid", "802-11-wireless.band"])
        frequencies = networkmanager_output("--get-values", "FREQ,SSID", "device", "wifi", "list", "ifname", interface_name, "--rescan", "no")
        bands = set()
        for line in frequencies.splitlines():
            frequency, _, name = line.partition(":")
            if name == ssid:
                band = wifi_band_for_frequency(int(frequency.split()[0]))
                if band:
                    bands.add(band)
        result.update(bands=sorted(bands, key=float), selectedBand=next((key for key, value in BANDS.items() if value == selected), "auto"))
    return result


def modify_connection_fields(connection_uuid, fields, values):
    networkmanager_output("connection", "modify", "uuid", connection_uuid, *[part for pair in zip(fields, values) for part in pair])


def apply_connection_setting(args):
    if args.action == "status":
        print(json.dumps(connection_status(args.connection_uuid, args.interface_name)))
        return
    if args.action == "dns":
        servers = [] if args.value == "DHCP" else DNS_PROVIDERS.get(args.value)
        if servers is None:
            servers = [str(ipaddress.ip_address(value)) for value in args.servers.replace(",", " ").split()]
            if not servers:
                raise ValueError("Enter at least one DNS server address.")
        fields = DNS_FIELDS
        values = ["no" if args.value == "DHCP" else "yes", " ".join(value for value in servers if ":" not in value), "no" if args.value == "DHCP" else "yes", " ".join(value for value in servers if ":" in value)]
        activate = ["device", "reapply", args.interface_name]
    else:
        fields = ["802-11-wireless.band"]
        values = [BANDS[args.value]]
        if args.value != "auto" and args.value not in connection_status(args.connection_uuid, args.interface_name)["bands"]:
            raise ValueError("That band is no longer available on this network.")
        activate = ["connection", "up", "uuid", args.connection_uuid, "ifname", args.interface_name]
    previous = connection_fields(args.connection_uuid, fields)
    modify_connection_fields(args.connection_uuid, fields, values)
    try:
        networkmanager_output(*activate)
    except subprocess.CalledProcessError as error:
        modify_connection_fields(args.connection_uuid, fields, previous)
        try:
            networkmanager_output(*activate)
        except subprocess.CalledProcessError:
            raise ValueError("Restored the previous profile settings, but could not reactivate the connection. " + error.stderr.strip())
        raise ValueError("Could not apply the change; restored the previous settings. " + error.stderr.strip())


parser = argparse.ArgumentParser()
parser.add_argument("action", choices=["status", "dns", "band"])
parser.add_argument("connection_uuid")
parser.add_argument("interface_name")
parser.add_argument("value", nargs="?", default="")
parser.add_argument("servers", nargs="?", default="")
try:
    apply_connection_setting(parser.parse_args())
except (subprocess.CalledProcessError, ValueError, KeyError) as error:
    print(str(getattr(error, "stderr", None) or error).strip(), file=sys.stderr)
    sys.exit(1)
