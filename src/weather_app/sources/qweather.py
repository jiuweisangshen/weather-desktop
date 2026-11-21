# -*- coding: utf-8 -*-
"""和风天气 QWeather（可选）：需在 config.json 填入免费 Key
文档：https://dev.qweather.com/docs/api/"""
from .base import http_get

_GEO = "https://geoapi.qweather.com/v2/city/lookup"
_NOW = "https://devapi.qweather.com/v7/weather/now"
_DAILY = "https://devapi.qweather.com/v7/weather/7d"

# 天气文本关键词 → 图标键（按《地面气象观测规范》用语维护）
_ICON_RULES = [
    ("冰雹", "thunder_hail"), ("雷", "thunder"), ("暴雪", "heavy_snow"),
    ("大雪", "heavy_snow"), ("中雪", "snow"), ("阵雪", "snow_showers"),
    ("小雪", "snow"), ("雪", "snow"),
    ("暴雨", "heavy_rain"), ("大雨", "heavy_rain"),
    ("中雨", "rain"), ("小雨", "rain"), ("阵雨", "showers"),
    # 「冻」须排在「雨」之前，否则「冻雨」会被「雨」抢先命中判成普通降雨
    ("冻", "freezing"), ("雨", "rain"),
    ("雾", "fog"), ("沙", "fog"),
    ("晴", "clear"), ("多云", "partly"), ("阴", "cloudy"),
]


def icon_from_text(text: str) -> str:
    for kw, ic in _ICON_RULES:
        if kw in (text or ""):
            return ic
    return "cloudy"


def location_id(city: str, key: str, timeout: float = 10):
    data = http_get(_GEO, {"location": city, "key": key, "number": 1}, timeout)
    if data.get("code") != "200" or not data.get("location"):
        return None
    loc = data["location"][0]
    return {"id": loc["id"], "name": loc["name"]}


def fetch_all(city: str, key: str, timeout: float = 12) -> dict:
    """返回 {now: {...}, daily: [...]} 或抛异常"""
    loc = location_id(city, key)
    if not loc:
        raise RuntimeError("和风天气：城市匹配失败")
    now = http_get(_NOW, {"location": loc["id"], "key": key}, timeout)
    daily = http_get(_DAILY, {"location": loc["id"], "key": key}, timeout)
    if now.get("code") != "200" or daily.get("code") != "200":
        raise RuntimeError("和风天气：接口返回异常")
    return {"now": now.get("now", {}), "daily": daily.get("daily", [])}
