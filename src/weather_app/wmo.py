# -*- coding: utf-8 -*-
"""WMO 天气码 → 中文描述 / 图标；AQI、UV、风向等级工具"""
from typing import Optional

# 中文描述统一采用《地面气象观测规范》天气现象用语：
# 云量分级用 晴 / 少云 / 多云 / 阴，毛毛雨按降水量级并入小雨，
# 雪粒规范名为米雪，雷暴类统一表述为雷阵雨。
_WMO = {
    0: ("晴", "clear"), 1: ("少云", "clear"), 2: ("多云", "partly"),
    3: ("阴", "cloudy"), 45: ("雾", "fog"), 48: ("雾凇", "fog"),
    51: ("小雨", "drizzle"), 53: ("小雨", "drizzle"), 55: ("小雨", "drizzle"),
    56: ("冻雨", "freezing"), 57: ("冻雨", "freezing"),
    61: ("小雨", "rain"), 63: ("中雨", "rain"), 65: ("大雨", "heavy_rain"),
    66: ("冻雨", "freezing"), 67: ("冻雨", "freezing"),
    71: ("小雪", "snow"), 73: ("中雪", "snow"), 75: ("大雪", "heavy_snow"),
    77: ("米雪", "snow_grains"),
    80: ("阵雨", "showers"), 81: ("阵雨", "showers"), 82: ("大阵雨", "heavy_showers"),
    85: ("阵雪", "snow_showers"), 86: ("大阵雪", "heavy_snow_showers"),
    95: ("雷阵雨", "thunder"), 96: ("雷阵雨伴冰雹", "thunder"), 99: ("雷阵雨伴冰雹", "thunder_hail"),
}
_DEFAULT = ("未知", "cloudy")


def describe(code: int, is_day: bool = True) -> str:
    d, _k = _WMO.get(int(code), _DEFAULT)
    if int(code) in (0, 1, 2) and not is_day:
        return "夜间" + d
    return d


def icon_key(code: int, is_day: bool = True) -> str:
    _d, k = _WMO.get(int(code), _DEFAULT)
    if k == "clear" and not is_day:
        return "night_clear"
    if k == "partly" and not is_day:
        return "night_partly"
    return k


# ---------- 降水相态校正（雨 / 雨夹雪 / 雪分级） ----------
# WMO 雪类码；Open-Meteo 的 75 固定代表 "heavy snow fall"，常把雨夹雪误判为
# 大雪：降水里有明显降雨成分、雪量小、日最高温在 0℃ 以上时按实际组成降级。
_SNOW_CODES = {71, 73, 75, 77, 85, 86}


def _num(v) -> Optional[float]:
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def precip_desc(code: int, rain_mm=None, snow_cm=None, tmax=None, is_day: bool = True):
    """按实测/预报的雨量、雪量与最高温校正降水描述，返回 (描述, 图标key)。

    - 雨、雪同时存在且最高温 >= 1℃ → 雨夹雪
    - 只有雪量：按雪深分级（<1cm 小雪、<3cm 小到中雪、<8cm 中雪、>=8cm 大雪）
    - 无雪量数据但最高温明显高于 0℃ → 对 75 降级为中雪档，避免误报大雪
    """
    code = int(code or 0)
    d = describe(code, is_day)
    k = icon_key(code, is_day)
    if code not in _SNOW_CODES:
        return d, k
    rain = _num(rain_mm)
    snow = _num(snow_cm)
    tx = _num(tmax)

    # 明显的雨雪混合：有降雨量、也有雪量 → 统一表述为雨夹雪
    if rain is not None and snow is not None and rain >= 0.5 and snow > 0:
        return "雨夹雪", "freezing"
    # 有降雨成分但没有雪量记录、且最高温在 1℃ 以上：降水应以雨为主
    if rain is not None and rain >= 0.5 and (snow is None or snow <= 0) and tx is not None and tx >= 1.0:
        return "小雨", "rain"
    # 按雪量分级（snowfall_sum 单位为 cm）
    if snow is not None and snow > 0:
        if snow < 1.0:
            if rain is not None and rain > 0:
                return "雨夹雪", "freezing"
            return "小雪", "snow"
        if snow < 3.0:
            return "小到中雪", "snow"
        if snow < 8.0:
            return "中雪", "snow"
        return "大雪", "heavy_snow"
    # 无雪量数据：高温明显高于 0℃ 时，75 降级处理，避免误报大雪
    if tx is not None and tx >= 1.5 and code in (73, 75, 86):
        return "小雪到中雪", "snow"
    return d, k


# ---------- 空气污染（US AQI） ----------
_AQI_LEVELS = [
    (50, "优", "#3ED477"), (100, "良", "#FFD60A"), (150, "轻度污染", "#FF9F0A"),
    (200, "中度污染", "#FF3B30"), (300, "重度污染", "#BF5AF2"),
]


def aqi_info(v: Optional[float]) -> Optional[dict]:
    if v is None:
        return None
    for lim, label, color in _AQI_LEVELS:
        if v <= lim:
            return {"value": int(round(v)), "label": label, "color": color}
    return {"value": int(round(v)), "label": "严重污染", "color": "#9B2C2C"}


# ---------- 紫外线 ----------
_UV_LEVELS = [
    (2, "低", "#3ED477"), (5, "中等", "#FFD60A"), (7, "高", "#FF9F0A"),
    (10, "很高", "#FF3B30"),
]


def uv_info(v: Optional[float]) -> Optional[dict]:
    if v is None:
        return None
    for lim, label, color in _UV_LEVELS:
        if v <= lim:
            return {"value": round(v, 1), "label": label, "color": color}
    return {"value": round(v, 1), "label": "极高", "color": "#BF5AF2"}


# ---------- 风向（16 方位） ----------
_WINDS = ["北", "东北偏北", "东北", "东北偏东", "东", "东南偏东", "东南", "东南偏南",
          "南", "西南偏南", "西南", "西南偏西", "西", "西北偏西", "西北", "西北偏北"]


def wind_dir_text(deg: Optional[float]) -> str:
    if deg is None:
        return ""
    return _WINDS[int((deg % 360 + 11.25) // 22.5) % 16] + "风"
