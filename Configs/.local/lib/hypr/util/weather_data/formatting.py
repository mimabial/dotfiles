from datetime import datetime

from .icons import condition_is_day, weather_icon

MAX_RAIN_READOUT_PERCENT = 99


class WeatherFormat:
    def __init__(self, temperature_unit, time_format, wind_speed_unit):
        self.temperature_unit = temperature_unit if temperature_unit in ("c", "f") else "c"
        self.time_format = time_format if time_format in ("12h", "24h") else "12h"
        self.wind_speed_unit = wind_speed_unit if wind_speed_unit in ("km/h", "mph") else "km/h"

    def temperature(self, celsius, fahrenheit):
        return celsius + "°C" if self.temperature_unit == "c" else fahrenheit + "°F"

    def wind_value(self, condition):
        return condition["windspeedKmph" if self.wind_speed_unit == "km/h" else "windspeedMiles"]

    def wind_speed(self, condition):
        return self.wind_value(condition) + ("Km/h" if self.wind_speed_unit == "km/h" else "Mph")

    def timestamp(self, time_str, force_24h=False):
        if force_24h or self.time_format == "24h":
            return datetime.strptime(time_str, "%I:%M %p").strftime("%H:%M")
        return time_str


def readout(glyph, text):
    return {"text": " ".join(filter(None, [glyph, text])), "icon": glyph, "value": text}


def degrees(temp):
    return temp.split("°")[0] + "°"


def weather_status(weather, formatting, field_separator, show_icon, show_location, show_today_details):
    current = weather["current_condition"][0]
    today = weather["weather"][0]
    description = current["weatherDesc"][0]["value"]
    city = weather["nearest_area"][0]["areaName"][0]["value"]
    country = weather["nearest_area"][0]["country"][0]["value"]
    icon = weather_icon(current["weatherCode"], condition_is_day(current, today["astronomy"][0])) if show_icon else ""
    feels = formatting.temperature(current["FeelsLikeC"], current["FeelsLikeF"])
    temperature = formatting.temperature(current["temp_C"], current["temp_F"])
    high = formatting.temperature(today["maxtempC"], today["maxtempF"])
    low = formatting.temperature(today["mintempC"], today["mintempF"])
    sunrise = today["astronomy"][0]["sunrise"]
    sunset = today["astronomy"][0]["sunset"]
    text = field_separator.join(filter(None, [icon, feels]))
    if show_location:
        text += f" | {city}, {country}"
    rain = min(max((int(hour.get("chanceofrain", 0)) for hour in today["hourly"]), default=0), MAX_RAIN_READOUT_PERCENT)
    readouts = {
        "temp": readout(icon, feels),
        "current": readout(icon, temperature),
        "condition": readout("", description),
        "minmax": readout("", f"{degrees(high)}|{degrees(low)}"),
        "sunrise": readout("\ue34c", formatting.timestamp(sunrise, True)),
        "sunset": readout("\ue34d", formatting.timestamp(sunset, True)),
        "rain": readout("\U000f188b", f"{rain}%"),
        "wind": readout("\ue34b", f"{formatting.wind_value(current)} {formatting.wind_speed_unit}"),
        "humidity": readout("\ue373", f"{current['humidity']}%"),
    }
    tooltip = ""
    if show_today_details:
        tooltip = (
            f"<b>{description} {temperature}</b>\n"
            f"Location: {city}, {country}\n"
            f"Feels like: {feels}\n"
            f"Wind: {formatting.wind_speed(current)}\n"
            f"Humidity: {current['humidity']}%\n"
            f"Sunrise: {formatting.timestamp(sunrise)}\n"
            f"Sunset: {formatting.timestamp(sunset)}\n"
            f"Max|Min: {high} | {low}"
        )
    return {"text": text, "readouts": readouts, "tooltip": tooltip}
