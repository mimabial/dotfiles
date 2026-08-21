#!/usr/bin/env python3
"""Mullvad relay locations as JSON, for the bar's VPN panel.

`mullvad relay list` is ~740 lines of country / city / relay indented by tabs.
The panel only needs somewhere to point the tunnel, so this collapses it to
countries and their cities with relay counts, plus whatever location is
currently pinned.
"""
import argparse
import json
import re
import subprocess
import sys

COUNTRY = re.compile(r"^(?P<name>.+) \((?P<code>[a-z]{2})\)\s*$")
CITY = re.compile(r"^\t(?P<name>.+) \((?P<code>[a-z]{3})\) @")
RELAY = re.compile(r"^\t\t(?P<host>\S+)")


def run(args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout if out.returncode == 0 else ""


def current_location():
    """Read the pinned location out of `mullvad relay get`.

    Four shapes, and the city one puts the city *before* its country:
        any
        country cz
        city prg, cz
        city prg, cz, hostname cz-prg-wg-101
    """
    text = run(["mullvad", "relay", "get"])
    match = re.search(r"^\s*Location:\s*(.+)$", text, re.M)
    if not match:
        return {}

    segments = [part.strip() for part in match.group(1).split(",")]
    if not segments or segments[0] == "any":
        return {"kind": "any"}

    here = {"kind": "", "country": "", "city": "", "hostname": ""}
    for index, segment in enumerate(segments):
        head, _, value = segment.partition(" ")
        if head == "country":
            here["kind"] = here["kind"] or "country"
            here["country"] = value
        elif head == "city":
            here["kind"] = "city"
            here["city"] = value
            # the bare segment that follows a city is its country code
            if index + 1 < len(segments) and " " not in segments[index + 1]:
                here["country"] = segments[index + 1]
        elif head == "hostname":
            here["kind"] = "hostname"
            here["hostname"] = value
    return here


def parse_relays(text):
    countries, country, city = [], None, None
    for line in text.splitlines():
        if not line.strip():
            continue
        relay = RELAY.match(line)
        if relay:
            if city is not None:
                city["relays"] += 1
            continue
        town = CITY.match(line)
        if town:
            if country is None:
                continue
            city = {"code": town["code"], "name": town["name"], "relays": 0}
            country["cities"].append(city)
            continue
        nation = COUNTRY.match(line)
        if nation:
            country = {"code": nation["code"], "name": nation["name"], "cities": []}
            countries.append(country)
            city = None
    return countries


def main():
    parser = argparse.ArgumentParser(description="Emit Mullvad relay locations as JSON.")
    parser.parse_args()

    text = run(["mullvad", "relay", "list"])
    if not text:
        json.dump({"current": {}, "countries": []}, sys.stdout)
        sys.stdout.write("\n")
        return

    countries = parse_relays(text)
    for country in countries:
        country["relays"] = sum(city["relays"] for city in country["cities"])
    json.dump({"current": current_location(), "countries": countries}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
