import math
from typing import NamedTuple


class Unit(NamedTuple):
    symbol: str
    to_base: float


UNIT_CATEGORIES = {
    "Length": [
        Unit("m", 1), Unit("km", 1000), Unit("cm", .01), Unit("mm", .001), Unit("mi", 1609.344),
        Unit("ft", .3048), Unit("in", .0254), Unit("yd", .9144), Unit("nmi", 1852),
    ],
    "Mass": [
        Unit("kg", 1), Unit("lb", .45359237), Unit("g", .001), Unit("oz", .028349523125),
        Unit("mg", 1e-6), Unit("t", 1000), Unit("st", 6.35029318),
    ],
    "Area": [
        Unit("m²", 1), Unit("ft²", .09290304), Unit("km²", 1e6), Unit("cm²", 1e-4),
        Unit("acre", 4046.8564224), Unit("ha", 10000), Unit("yd²", .83612736),
        Unit("in²", .00064516), Unit("mi²", 2589988.110336),
    ],
    "Volume": [
        Unit("l", 1), Unit("gal", 3.785411784), Unit("ml", .001), Unit("cup", .2365882365),
        Unit("m³", 1000), Unit("cl", .01), Unit("floz", .0295735295625), Unit("pt", .473176473),
        Unit("qt", .946352946), Unit("tbsp", .01478676478125), Unit("tsp", .00492892159375),
    ],
    "Speed": [Unit("km/h", 1 / 3.6), Unit("mph", .44704), Unit("m/s", 1), Unit("kn", .514444444444), Unit("ft/s", .3048)],
    "Time": [
        Unit("min", 60), Unit("h", 3600), Unit("s", 1), Unit("day", 86400), Unit("week", 604800), Unit("ms", .001),
    ],
    "Data": [
        Unit("MB", 1e6), Unit("GB", 1e9), Unit("MiB", 1048576), Unit("GiB", 1073741824),
        Unit("KB", 1000), Unit("KiB", 1024), Unit("byte", 1), Unit("bit", .125), Unit("TB", 1e12),
    ],
    "Energy": [
        Unit("kWh", 3.6e6), Unit("kJ", 1000), Unit("J", 1), Unit("kcal", 4184),
        Unit("cal", 4.184), Unit("Wh", 3600), Unit("BTU", 1055.05585262),
    ],
    "Power": [Unit("W", 1), Unit("kW", 1000), Unit("hp", 745.699871582)],
    "Pressure": [
        Unit("bar", 100000), Unit("psi", 6894.75729317), Unit("kPa", 1000), Unit("Pa", 1),
        Unit("atm", 101325), Unit("mmHg", 133.322387415),
    ],
    "Angle": [Unit("deg", math.pi / 180), Unit("rad", 1)],
}


def unit_conversion_schema() -> dict:
    categories = []
    for name, entries in UNIT_CATEGORIES.items():
        categories.append({"label": name, "units": [{"label": symbol, "symbol": symbol, "scale": scale, "offset": 0} for symbol, scale in entries]})
    categories.insert(2, {"label": "Temperature", "units": [
        {"label": "°C", "symbol": "°C", "scale": 1, "offset": 0},
        {"label": "°F", "symbol": "°F", "scale": 5 / 9, "offset": -160 / 9},
        {"label": "K", "symbol": "K", "scale": 1, "offset": -273.15},
    ]})
    return {"categories": categories}
