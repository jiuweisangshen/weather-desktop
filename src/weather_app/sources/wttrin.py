# -*- coding: utf-8 -*-
"""wttr.in：免费、无需密钥的交叉校验源（基于 WorldWeatherOnline 派生数据）
文档：https://github.com/chubin/wttr.in"""
from .base import http_get

# wttr.in 使用的 WWO 天气码 → (中文描述, 图标键)；描述统一按气象规范用语
_WWO = {
    113: ("晴", "clear"), 116: ("少云", "partly"), 119: ("多云", "cloudy"),
    122: ("阴", "overcast"), 143: ("薄雾", "fog"), 248: ("雾", "fog"),
    260: ("雾凇", "fog"),
    176: ("阵雨", "showers"), 179: ("阵雪", "snow_showers"),
    182: ("雨夹雪", "freezing"), 185: ("冻雨", "freezing"),
    200: ("雷阵雨", "thunder"), 227: ("吹雪", "snow"), 230: ("暴风雪", "heavy_snow"),
    263: ("小雨", "drizzle"), 266: ("小雨", "drizzle"),
    281: ("冻雨", "freezing"), 284: ("冻雨", "freezing"),
    293: ("阵雨", "showers"), 296: ("小雨", "rain"), 299: ("小雨", "rain"),
    302: ("中雨", "rain"), 305: ("大雨", "heavy_rain"), 308: ("大雨", "heavy_rain"),
    311: ("冻雨", "freezing"), 314: ("冻雨", "freezing"),
    317: ("雨夹雪", "freezing"), 320: ("雨夹雪", "freezing"),
    323: ("阵雪", "snow_showers"), 326: ("小雪", "snow"), 329: ("阵雪", "snow_showers"),
    332: ("中雪", "snow"), 335: ("大雪", "heavy_snow"), 338: ("暴雪", "heavy_snow"),
    350: ("冰粒", "snow_grains"), 353: ("阵雨", "showers"),
    356: ("阵雨", "showers"), 359: ("大阵雨", "heavy_showers"),
    362: ("雨夹雪", "freezing"), 365: ("雨夹雪", "freezing"),
    368: ("阵雪", "snow_showers"), 371: ("阵雪", "snow_showers"),
    374: ("冰粒", "snow_grains"), 377: ("冰粒", "snow_grains"),
    386: ("雷阵雨", "thunder"), 389: ("雷阵雨", "thunder"),
    392: ("雷阵雨伴雪", "thunder"), 395: ("雷阵雨伴雪", "thunder"),
}


def wwo_info(code):
    try:
        c = int(code)
    except (TypeError, ValueError):
        return ("未知", "cloudy")
    return _WWO.get(c, ("未知", "cloudy"))


def fetch(lat: float, lon: float, timeout: float = 12):
    """返回 wttr.in JSON（含当前、逐小时、3 天预报）"""
    url = f"https://wttr.in/{lat:.3f},{lon:.3f}"
    return http_get(url, {"format": "j1", "lang": "zh"}, timeout)
