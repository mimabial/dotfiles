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


def nm(*args):
    return subprocess.run(["nmcli", "--escape", "no", *args], check=True, text=True, capture_output=True).stdout


def read(uuid, fields):
    return nm("--get-values", ",".join(fields), "connection", "show", "uuid", uuid).splitlines()


def band_for(frequency):
    return "2.4" if 2400 <= frequency < 2500 else "5" if 4900 <= frequency < 5925 else "6" if 5925 <= frequency < 7125 else ""


def status(uuid, iface):
    flags4, dns4, flags6, dns6 = read(uuid, DNS_FIELDS)
    servers = dns4.replace(",", " ").split() + dns6.replace(",", " ").split()
    mode = "DHCP" if flags4 == flags6 == "no" else next((name for name, preset in DNS_PROVIDERS.items() if sorted(servers) == sorted(preset)), "Custom")
    result = {"dnsMode": mode, "dnsServers": " ".join(servers), "bands": [], "selectedBand": "auto"}
    if nm("--get-values", "connection.type", "connection", "show", "uuid", uuid).strip() == "802-11-wireless":
        ssid, selected = read(uuid, ["802-11-wireless.ssid", "802-11-wireless.band"])
        frequencies = nm("--get-values", "FREQ,SSID", "device", "wifi", "list", "ifname", iface, "--rescan", "no")
        bands = set()
        for line in frequencies.splitlines():
            frequency, _, name = line.partition(":")
            if name == ssid:
                band = band_for(int(frequency.split()[0]))
                if band:
                    bands.add(band)
        result.update(bands=sorted(bands, key=float), selectedBand=next((key for key, value in BANDS.items() if value == selected), "auto"))
    return result


def modify(uuid, fields, values):
    nm("connection", "modify", "uuid", uuid, *[part for pair in zip(fields, values) for part in pair])


def apply(args):
    if args.action == "status":
        print(json.dumps(status(args.uuid, args.iface)))
        return
    if args.action == "dns":
        servers = [] if args.value == "DHCP" else DNS_PROVIDERS.get(args.value)
        if servers is None:
            servers = [str(ipaddress.ip_address(value)) for value in args.servers.replace(",", " ").split()]
            if not servers:
                raise ValueError("Enter at least one DNS server address.")
        fields = DNS_FIELDS
        values = ["no" if args.value == "DHCP" else "yes", " ".join(value for value in servers if ":" not in value), "no" if args.value == "DHCP" else "yes", " ".join(value for value in servers if ":" in value)]
        activate = ["device", "reapply", args.iface]
    else:
        fields = ["802-11-wireless.band"]
        values = [BANDS[args.value]]
        if args.value != "auto" and args.value not in status(args.uuid, args.iface)["bands"]:
            raise ValueError("That band is no longer available on this network.")
        activate = ["connection", "up", "uuid", args.uuid, "ifname", args.iface]
    previous = read(args.uuid, fields)
    modify(args.uuid, fields, values)
    try:
        nm(*activate)
    except subprocess.CalledProcessError as error:
        modify(args.uuid, fields, previous)
        try:
            nm(*activate)
        except subprocess.CalledProcessError:
            raise ValueError("Restored the previous profile settings, but could not reactivate the connection. " + error.stderr.strip())
        raise ValueError("Could not apply the change; restored the previous settings. " + error.stderr.strip())


parser = argparse.ArgumentParser()
parser.add_argument("action", choices=["status", "dns", "band"])
parser.add_argument("uuid")
parser.add_argument("iface")
parser.add_argument("value", nargs="?", default="")
parser.add_argument("servers", nargs="?", default="")
try:
    apply(parser.parse_args())
except (subprocess.CalledProcessError, ValueError, KeyError) as error:
    print(str(getattr(error, "stderr", None) or error).strip(), file=sys.stderr)
    sys.exit(1)
