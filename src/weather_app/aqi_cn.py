# -*- coding: utf-8 -*-
"""中国环境空气质量指数 AQI（HJ 633-2012）计算补丁。

用途：Open-Meteo 的 `us_aqi` 与 `pm2_5` 偶发不自洽，且现有 UI 使用的是
中国 AQI 的中文分级文案。本模块用 PM2.5 / PM10 小时浓度计算 IAQI，
取最大值作为 AQI，口径与中文分级一致。

说明：HJ 633-2012 正式评价使用 24h 平均浓度；天气 App 用当前小时浓度
计算属于“参考值”，应在界面标注。若需要严格 24h，可传入 24h 均值。
"""
from __future__ import annotations

# (浓度下限, 浓度上限, IAQI 下限, IAQI 上限) —— HJ 633-2012 表 1
_PM25 = [
    (0, 35, 0, 50), (35, 75, 50, 100), (75, 115, 100, 150),
    (115, 150, 150, 200), (150, 250, 200, 300),
    (250, 350, 300, 400), (350, 500, 400, 500),
]
_PM10 = [
    (0, 50, 0, 50), (50, 150, 50, 100), (150, 250, 100, 150),
    (250, 350, 150, 200), (350, 420, 200, 300),
    (420, 500, 300, 400), (500, 600, 400, 500),
]

_LEVELS = [
    (50, "优", "#3ED477"),
    (100, "良", "#FFD60A"),
    (150, "轻度污染", "#FF9F0A"),
    (200, "中度污染", "#FF3B30"),
    (300, "重度污染", "#BF5AF2"),
]
_LEVEL_MAX = ("严重污染", "#9B2C2C")


def _iaqi(conc: float | None, table: list[tuple[float, float, float, float]]):
    if conc is None:
        return None
    try:
        c = max(0.0, float(conc))
    except (TypeError, ValueError):
        return None
    for lo, hi, ilo, ihi in table:
        if c <= hi:
            return ilo + (ihi - ilo) * (c - lo) / (hi - lo)
    return 500.0


def china_aqi(pm25: float | None = None, pm10: float | None = None):
    """返回 (aqi:int|None, 首要污染物:'PM2.5'|'PM10'|None)"""
    v25 = _iaqi(pm25, _PM25)
    v10 = _iaqi(pm10, _PM10)
    pairs = [(v, n) for v, n in ((v25, "PM2.5"), (v10, "PM10")) if v is not None]
    if not pairs:
        return None, None
    val, name = max(pairs, key=lambda x: x[0])
    return int(round(val)), (name if val > 50 else None)


def aqi_info(aqi: int | None):
    if aqi is None:
        return None
    for lim, label, color in _LEVELS:
        if aqi <= lim:
            return {"value": int(aqi), "label": label, "color": color,
                    "standard": "CN", "method": "HJ 633-2012（PM2.5/PM10 小时值参考）"}
    label, color = _LEVEL_MAX
    return {"value": int(aqi), "label": label, "color": color,
            "standard": "CN", "method": "HJ 633-2012（PM2.5/PM10 小时值参考）"}


def us_aqi_from_pm25(pm25: float | None):
    """仅用于核对 Open-Meteo `us_aqi` 是否自洽（US EPA 2018 PM2.5 表）。"""
    table = [
        (0.0, 12.0, 0, 50), (12.1, 35.4, 51, 100), (35.5, 55.4, 101, 150),
        (55.5, 150.4, 151, 200), (150.5, 250.4, 201, 300),
        (250.5, 350.4, 301, 400), (350.5, 500.4, 401, 500),
    ]
    if pm25 is None:
        return None
    c = max(0.0, float(pm25))
    for lo, hi, ilo, ihi in table:
        if c <= hi:
            return int(round(ilo + (ihi - ilo) * (c - lo) / (hi - lo)))
    return 500


if __name__ == "__main__":
    for name, pm25, pm10, api_us in [
        ("北京", 301.7, 320.4, 255),
        ("上海", 11.7, 13.3, 52),
        ("伦敦", 3.5, 5.8, 25),
    ]:
        cn, primary = china_aqi(pm25, pm10)
        print(f"{name}: CN AQI={cn} ({aqi_info(cn)['label']}), 首要={primary}, "
              f"PM2.5 对应的 US AQI≈{us_aqi_from_pm25(pm25)}, API us_aqi={api_us}")
