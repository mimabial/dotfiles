import argparse
import json
import os
import sys

from .cache import read_weather_cache, weather_cache_is_fresh, write_weather_cache
from .formatting import WeatherFormat, weather_status
from .http import requests_client
from .icons import annotate_day_icons
from .location import env_flag, geocode_candidates, load_weather_environment, resolve_weather_location
from .open_meteo import fetch_open_meteo_forecast
from .wttr import fetch_wttr_forecast


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--force", action="store_true", help="Force refresh cache (ignore cached data)")
    parser.add_argument("-A", "--alt", action="store_true", help="Join fields horizontally with a space instead of stacking with newlines")
    parser.add_argument("--search", metavar="QUERY", help="Print matching places as JSON and exit, for a location picker")
    args = parser.parse_args()
    if args.search:
        print(json.dumps([
            {
                "name": place.get("name", ""),
                "region": place.get("admin1", ""),
                "country": place.get("country", ""),
                "latitude": place.get("latitude"),
                "longitude": place.get("longitude"),
            }
            for place in geocode_candidates(args.search)
            if place.get("latitude") is not None
        ]))
        return 0

    load_weather_environment()
    formatting = WeatherFormat(
        os.getenv("WEATHER_TEMPERATURE_UNIT", "c").lower(),
        os.getenv("WEATHER_TIME_FORMAT", "12h").lower(),
        os.getenv("WEATHER_WINDSPEED_UNIT", "km/h").lower(),
    )
    weather = read_weather_cache() if not args.force and weather_cache_is_fresh() else None
    if weather is None:
        if requests_client() is None:
            print(
                "Error: Missing optional Python dependency 'requests'. "
                "Install it explicitly with `hyprshell pip install requests`.",
                file=sys.stderr,
            )
            return 1
        location, city, country = resolve_weather_location()
        # Open-Meteo first: wttr.in has served identical bogus readings for every
        # location at times, and it stays useful as a fallback.
        weather = fetch_open_meteo_forecast(location, city, country)
        if weather is None:
            weather = fetch_wttr_forecast(location)
        if weather is None:
            weather = read_weather_cache()
            if weather is None:
                print("Error: Failed to get weather data", file=sys.stderr)
                return 1
        else:
            write_weather_cache(annotate_day_icons(weather))

    print(json.dumps(weather_status(
        weather, formatting, " " if args.alt else "\n",
        env_flag("WEATHER_SHOW_ICON", True),
        env_flag("WEATHER_SHOW_LOCATION", False),
        env_flag("WEATHER_SHOW_TODAY_DETAILS", True),
    )))
    return 0
