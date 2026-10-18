import json
from datetime import datetime

from .http import REQUEST_TIMEOUT_SECONDS, requests_client
from .location import geocode, parse_coordinates

MILES_PER_KM = 0.621371
ISO_HOUR_LENGTH = len("YYYY-MM-DDTHH")
ISO_DATE_LENGTH = len("YYYY-MM-DD")
UNKNOWN_WTTR_CODE = "119"
FORECAST_DAYS = 7

# Open-Meteo reports WMO codes; the shared icon table is keyed by the WWO codes
# wttr.in uses, so each entry carries the nearest WWO equivalent and its text.
WMO_CONDITIONS = {
    0: ("113", "Clear"),
    1: ("116", "Partly cloudy"),
    2: ("116", "Partly cloudy"),
    3: ("119", "Overcast"),
    45: ("143", "Fog"),
    48: ("260", "Freezing fog"),
    51: ("266", "Light drizzle"),
    53: ("266", "Drizzle"),
    55: ("293", "Heavy drizzle"),
    56: ("281", "Freezing drizzle"),
    57: ("284", "Heavy freezing drizzle"),
    61: ("293", "Light rain"),
    63: ("296", "Rain"),
    65: ("308", "Heavy rain"),
    66: ("311", "Freezing rain"),
    67: ("314", "Heavy freezing rain"),
    71: ("323", "Light snow"),
    73: ("332", "Snow"),
    75: ("338", "Heavy snow"),
    77: ("350", "Snow grains"),
    80: ("353", "Light showers"),
    81: ("356", "Showers"),
    82: ("359", "Heavy showers"),
    85: ("368", "Light snow showers"),
    86: ("371", "Heavy snow showers"),
    95: ("386", "Thunderstorm"),
    96: ("392", "Thunderstorm with hail"),
    99: ("395", "Heavy thunderstorm with hail"),
}


OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"


def temperature_celsius_fahrenheit(celsius):
    return str(round(celsius)), str(round(celsius * 9 / 5 + 32))


def wind_kilometres_miles(kmph):
    return str(round(kmph)), str(round(kmph * MILES_PER_KM))


def clock_12h(stamp):
    try:
        return datetime.fromisoformat(stamp).strftime("%I:%M %p")
    except (TypeError, ValueError):
        return ""


def current_hour_index(current, hourly):
    now = str(current.get("time", ""))[:ISO_HOUR_LENGTH]
    stamps = hourly.get("time", [])
    return next((i for i, stamp in enumerate(stamps) if stamp[:ISO_HOUR_LENGTH] == now), 0)


def normalize_current_condition(current, hourly):
    code, description = WMO_CONDITIONS.get(
        current.get("weather_code"), (UNKNOWN_WTTR_CODE, "Unknown")
    )
    temp_c, temp_f = temperature_celsius_fahrenheit(current["temperature_2m"])
    feels_c, feels_f = temperature_celsius_fahrenheit(current["apparent_temperature"])
    wind_kmph, wind_miles = wind_kilometres_miles(current["wind_speed_10m"])

    # dew point and visibility only come per hour; take the one covering "now"
    hour_index = current_hour_index(current, hourly)

    def at_hour(key):
        series = hourly.get(key) or []
        return series[hour_index] if hour_index < len(series) else None

    dew_c, dew_f = temperature_celsius_fahrenheit(at_hour("dew_point_2m") or 0)
    metres = at_hour("visibility")
    return {
        "temp_C": temp_c,
        "temp_F": temp_f,
        "FeelsLikeC": feels_c,
        "FeelsLikeF": feels_f,
        "windspeedKmph": wind_kmph,
        "windspeedMiles": wind_miles,
        "humidity": str(current.get("relative_humidity_2m", "")),
        "uvIndex": str(round(current.get("uv_index") or 0)),
        "cloudcover": str(round(current.get("cloud_cover") or 0)),
        "pressure": str(round(current.get("surface_pressure") or 0)),
        "DewPointC": dew_c,
        "DewPointF": dew_f,
        "visibility": "" if metres is None else str(round(metres / 1000)),
        "is_day": current["is_day"],
        "weatherCode": code,
        "weatherDesc": [{"value": description}],
    }


def normalize_hours_by_date(hourly):
    hours_by_date = {}
    for index, stamp in enumerate(hourly.get("time", [])):
        hour_c, hour_f = temperature_celsius_fahrenheit(hourly["temperature_2m"][index])
        hour_code, _ = WMO_CONDITIONS.get(hourly["weather_code"][index], (UNKNOWN_WTTR_CODE, ""))
        hours_by_date.setdefault(stamp[:ISO_DATE_LENGTH], []).append({
            "time": stamp,
            "tempC": hour_c,
            "tempF": hour_f,
            "weatherCode": hour_code,
            "is_day": hourly["is_day"][index],
            "chanceofrain": str(hourly["precipitation_probability"][index] or 0),
        })
    return hours_by_date


def normalize_daily_forecast(daily, hours_by_date):
    days = []
    for index, date in enumerate(daily["time"]):
        high_c, high_f = temperature_celsius_fahrenheit(daily["temperature_2m_max"][index])
        low_c, low_f = temperature_celsius_fahrenheit(daily["temperature_2m_min"][index])
        day_code, _ = WMO_CONDITIONS.get(
            (daily.get("weather_code") or [None] * (index + 1))[index], (UNKNOWN_WTTR_CODE, "")
        )
        hours = hours_by_date.get(date, [])
        days.append(
            {
                "date": date,
                "weatherCode": day_code,
                "maxtempC": high_c,
                "maxtempF": high_f,
                "mintempC": low_c,
                "mintempF": low_f,
                "astronomy": [
                    {
                        "sunrise": clock_12h(daily["sunrise"][index]),
                        "sunset": clock_12h(daily["sunset"][index]),
                    }
                ],
                "hourly": hours,
                "chanceofrain": str(max((int(hour["chanceofrain"]) for hour in hours), default=0)),
            }
        )
    return days


def normalize_open_meteo_forecast(payload, city, country):
    """Rewrite an Open-Meteo response into the j1 layout the getters expect."""
    hourly = payload.get("hourly", {})
    current_condition = normalize_current_condition(payload["current"], hourly)
    return {
        "current_condition": [current_condition],
        "weather": normalize_daily_forecast(payload["daily"], normalize_hours_by_date(hourly)),
        "nearest_area": [
            {
                "areaName": [{"value": city}],
                "country": [{"value": country}],
            }
        ],
    }


def fetch_open_meteo_forecast(location, city, country):
    requests = requests_client()
    if requests is None:
        return None
    point = parse_coordinates(location)
    if point is None:
        resolved = geocode(location)
        if resolved is None:
            return None
        latitude, longitude, city, country = resolved
    else:
        latitude, longitude = point

    try:
        response = requests.get(
            OPEN_METEO_URL,
            params={
                "latitude": latitude,
                "longitude": longitude,
                "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,uv_index,cloud_cover,surface_pressure,is_day",
                "daily": "temperature_2m_max,temperature_2m_min,sunrise,sunset,weather_code",
                "hourly": "temperature_2m,weather_code,precipitation_probability,dew_point_2m,visibility,is_day",
                "timezone": "auto",
                "forecast_days": FORECAST_DAYS,
            },
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return normalize_open_meteo_forecast(response.json(), city, country)
    except (requests.RequestException, json.JSONDecodeError, KeyError, TypeError):
        return None
