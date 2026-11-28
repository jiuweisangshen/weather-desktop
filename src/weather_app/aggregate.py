# -*- coding: utf-8 -*-
"""多源数据聚合：加权平均当前温度、逐日高低温、逐小时合并 UV/能见度"""
import datetime as _dt

from . import aqi_cn, wmo
from .sources import qweather as _qweather
from .sources import wttrin as _wttrin


def _f(v):
    """安全转 float"""
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _r(v, nd=1):
    if v is None:
        return None
    return round(float(v), nd)


def _weighted(items, weights):
    """items: [(value, key)]；返回 (加权均值, 参与源列表)"""
    pairs = [(v, k) for v, k in items if v is not None]
    if not pairs:
        return None, []
    wsum = sum(weights.get(k, 0.0) for _v, k in pairs)
    if wsum <= 0:
        return None, []
    avg = sum(v * weights.get(k, 0.0) for v, k in pairs) / wsum
    return avg, [k for _v, k in pairs]


def _weighted_robust(items, weights, max_dev=2.0):
    """加权平均 + 离群剔除：源数>2 且某源偏离当前加权均值超过 max_dev°C 时，
    剔除最远源后重算（实测：模式源 GFS/ECMWF 更分散，避免拖偏综合温度；
    阈值 2.0°C：地面实测源互差通常 <0.5°C，2°C 外基本可判定为模式源偏差或错位数据）"""
    pairs = [(v, k) for v, k in items if v is not None]
    if len(pairs) <= 2:
        return _weighted(pairs, weights)
    avg, used = _weighted(pairs, weights)
    if avg is None:
        return None, []
    while len(pairs) > 2:
        worst = max(pairs, key=lambda p: abs(p[0] - avg))
        if abs(worst[0] - avg) <= max_dev:
            break
        pairs = [p for p in pairs if p is not worst]
        avg, used = _weighted(pairs, weights)
    return avg, used


def _h2m(iso: str) -> str:
    """'2026-10-24T06:34' → '06:34'"""
    if not iso:
        return ""
    s = str(iso)
    return s[11:16] if len(s) >= 16 else s


def _weekday(dstr: str, idx: int) -> str:
    try:
        d = _dt.date.fromisoformat(dstr[:10])
        if idx == 0:
            return "今天"
        if idx == 1:
            return "明天"
        return "周" + "一二三四五六日"[d.weekday()]
    except Exception:
        return ""


def build(loc: dict, res: dict, cfg: dict, fallback_used: str = None,
          timed_out: list | None = None) -> dict:
    """res: {main, uv, aq, gfs, ecmwf, wttr, qw, cc}（失败项为 None）
    fallback_used: 主源失败时使用的备用源（wttr/chinacom），None表示主源正常
    timed_out: 本轮超时的数据源名列表（仅用于诊断/说明，不影响聚合）"""
    timed_out = timed_out or []
    weights = cfg.get("weights", {})
    main = res.get("main") or {}
    uvdata = res.get("uv") or {}
    aq = res.get("aq") or {}
    gfs = res.get("gfs")
    ecm = res.get("ecmwf")
    wtr = res.get("wttr")
    qw = res.get("qw")
    cc = res.get("cc")
    cc_now = (cc.get("now") if cc else {}) or {}
    alarm = res.get("alarm")

    now_t = None
    if main.get("current"):
        now_t = main["current"].get("time")

    # ---------- 当前温度：多源加权 + 离群剔除 ----------
    temp_items = [(_f(main.get("current", {}).get("temperature_2m")), "open-meteo")]
    if cc_now.get("temp") is not None:
        temp_items.append((_f(cc_now.get("temp")), "chinacom"))
    if gfs and gfs.get("current"):
        temp_items.append((_f(gfs["current"].get("temperature_2m")), "gfs"))
    if ecm and ecm.get("current"):
        temp_items.append((_f(ecm["current"].get("temperature_2m")), "ecmwf"))
    if wtr and wtr.get("current_condition"):
        temp_items.append((_f(wtr["current_condition"][0].get("temp_C")), "wttr.in"))
    if qw and qw.get("now"):
        temp_items.append((_f(qw["now"].get("temp")), "qweather"))

    combined, used = _weighted_robust(temp_items, weights)
    temps = {k: v for v, k in temp_items if v is not None}
    spread = (max(temps.values()) - min(temps.values())) if len(temps) >= 2 else 0.0

    cur_main = main.get("current", {}) if main else {}
    cur_w = (wtr["current_condition"][0] if wtr and wtr.get("current_condition") else {})

    feels_items = [(_f(cur_main.get("apparent_temperature")), "open-meteo")]
    if qw and qw.get("now"):
        feels_items.append((_f(qw["now"].get("feelsLike")), "qweather"))
    # 主源缺失时用 wttr.in 的实况补全体感，避免备用模式下整卡只有温度
    if not cur_main and cur_w:
        feels_items.append((_f(cur_w.get("FeelsLikeC")), "wttr.in"))
    feels, _u2 = _weighted(feels_items, weights) if feels_items else (None, [])

    # 湿度 / 气压 / 能见度 / 风速：Open-Meteo 与中国天气网交叉加权
    hum_items = [(_f(cur_main.get("relative_humidity_2m")), "open-meteo")]
    if cc_now.get("humidity") is not None:
        hum_items.append((_f(cc_now.get("humidity")), "chinacom"))
    if not cur_main and cur_w.get("humidity") is not None:
        hum_items.append((_f(cur_w.get("humidity")), "wttr.in"))
    hum_v, _ = _weighted(hum_items, weights) if hum_items else (None, [])

    pres_items = [(_f(cur_main.get("pressure_msl")), "open-meteo")]
    if cc_now.get("pressure") is not None:
        pres_items.append((_f(cc_now.get("pressure")), "chinacom"))
    if not cur_main and cur_w.get("pressure") is not None:
        pres_items.append((_f(cur_w.get("pressure")), "wttr.in"))
    pres_v, _ = _weighted(pres_items, weights) if pres_items else (None, [])

    wind_items = [(_f(cur_main.get("wind_speed_10m")), "open-meteo")]
    if cc_now.get("wind_kmh") is not None:
        wind_items.append((_f(cc_now.get("wind_kmh")), "chinacom"))
    if not cur_main and cur_w.get("windspeedKmph") is not None:
        wind_items.append((_f(cur_w.get("windspeedKmph")), "wttr.in"))
    wind_v, _ = _weighted(wind_items, weights) if wind_items else (None, [])

    # 天气现象：主源优先；主源缺失时用 wttr.in / 中国天气网补全，避免备用模式误显示“晴”
    if cur_main:
        code = cur_main.get("weather_code") or 0
        is_day = cur_main.get("is_day", 1) == 1
        desc_now, icon_now = wmo.describe(code, is_day), wmo.icon_key(code, is_day)
    else:
        is_day = 6 <= _dt.datetime.now().hour < 18
        if cur_w:
            code = int(_f(cur_w.get("weatherCode")) or 0)
            desc_now, icon_now = _wttrin.wwo_info(code)
        elif cc_now.get("weather"):
            code = 0
            desc_now = str(cc_now.get("weather"))
            icon_now = _qweather.icon_from_text(desc_now)
        else:
            code = 0
            desc_now, icon_now = wmo.describe(0, is_day), wmo.icon_key(0, is_day)

    # UV / 能见度：从 7 天扩展数据取当前槽位
    uv_now, vis_now = None, None
    uv_series = (uvdata.get("hourly", {}).get("uv_index") if uvdata.get("hourly") else None)
    vis_series = (uvdata.get("hourly", {}).get("visibility") if uvdata.get("hourly") else None)
    uv_time = (uvdata.get("hourly", {}).get("time") if uvdata.get("hourly") else None)
    if now_t and uv_time:
        for i, t in enumerate(uv_time):
            if t >= now_t:
                try:
                    uv_now = uv_series[i] if uv_series else None
                    vis_now = vis_series[i] if vis_series else None
                except IndexError:
                    pass
                break
    if uv_now is None and wtr:
        try:
            uv_now = _f(wtr["current_condition"][0].get("uvIndex"))
        except Exception:
            uv_now = None
    if vis_now is None and wtr:
        try:
            vis_now = _f(wtr["current_condition"][0].get("visibility"))
        except Exception:
            vis_now = None

    # 能见度：Open-Meteo（米）与中国天气网（km）交叉加权
    vis_items = [(vis_now / 1000.0, "open-meteo")] if vis_now is not None else []
    if cc_now.get("visibility_km") is not None:
        vis_items.append((_f(cc_now.get("visibility_km")), "chinacom"))
    vis_v, _ = _weighted(vis_items, weights) if vis_items else (None, [])

    aqi_us = _f(aq.get("current", {}).get("us_aqi")) if aq.get("current") else None
    pm25 = _f(aq.get("current", {}).get("pm2_5")) if aq.get("current") else None
    pm10 = _f(aq.get("current", {}).get("pm10")) if aq.get("current") else None
    cn_aqi, aqi_primary = aqi_cn.china_aqi(pm25, pm10)

    # 空气污染口径裁决：国内城市优先中国天气网官方国标；模型换算值仅作参考
    aqi_official = _f(cc_now.get("aqi"))
    if aqi_official is not None:
        cur_aqi = int(round(aqi_official))
        aqi_source, aqi_note = "chinacom", "国标（中国天气网官方实时监测）"
    elif cn_aqi is not None:
        cur_aqi, aqi_source, aqi_note = cn_aqi, "open-meteo", "HJ 633-2012 换算（Open-Meteo 浓度，小时值参考）"
    else:
        cur_aqi, aqi_source, aqi_note = None, None, "暂无数据"

    # 风向：中国天气网中文风向优先，缺失时用 Open-Meteo 换算（备用模式用 wttr.in）
    wind_dir_txt = (cc_now.get("wind_dir")
                    or (cur_w.get("winddir16Point") if not cur_main else "")
                    or wmo.wind_dir_text(_f(cur_main.get("wind_direction_10m"))))
    gust_raw = cur_main.get("wind_gusts_10m")
    if gust_raw is None and not cur_main:
        gust_raw = cur_w.get("WindGustKmph")
    precip_raw = cur_main.get("precipitation")
    if precip_raw is None and not cur_main:
        precip_raw = cur_w.get("precipMM")
    wind_deg_raw = cur_main.get("wind_direction_10m")
    if wind_deg_raw is None and not cur_main:
        wind_deg_raw = cur_w.get("winddirDegree")

    current = {
        "temp": _r(combined, 1),
        "feels": _r(feels, 1),
        "code": code, "desc": desc_now, "icon": icon_now,
        "is_day": is_day,
        "humidity": int(round(hum_v)) if hum_v is not None else None,
        "pressure": _r(pres_v, 0),
        "visibility_km": _r(vis_v, 1),
        "wind_kmh": _r(wind_v, 1),
        "wind_gust": _r(gust_raw, 1),
        "wind_dir_deg": _r(wind_deg_raw, 0),
        "wind_dir": wind_dir_txt,
        "precip_mm": _r(precip_raw, 1),
        "uv": uv_now, "uv_info": wmo.uv_info(uv_now),
        "aqi": cur_aqi, "aqi_info": aqi_cn.aqi_info(cur_aqi),
        "aqi_source": aqi_source, "aqi_note": aqi_note,
        "aqi_us": aqi_us, "aqi_primary": aqi_primary,
        "pm25": _r(pm25, 1), "pm10": _r(pm10, 1),
        "sources": [{"key": k, "temp": _r(v, 1)} for v, k in temp_items if v is not None],
        "spread": round(spread, 1),
        "alarm": alarm,
    }

    # ---------- 今日 / 逐日 ----------
    daily_raw = (main.get("daily", {}) if main else {})
    d_codes = daily_raw.get("weather_code") or []
    d_tmax = daily_raw.get("temperature_2m_max") or []
    d_tmin = daily_raw.get("temperature_2m_min") or []
    d_sunrise = daily_raw.get("sunrise") or []
    d_sunset = daily_raw.get("sunset") or []
    d_prob = daily_raw.get("precipitation_probability_max") or []
    d_rain = daily_raw.get("precipitation_sum") or []
    d_snow = daily_raw.get("snowfall_sum") or []
    d_rain_sum = daily_raw.get("rain_sum") or []
    d_dates = daily_raw.get("time") or []

    wttr_days = wtr.get("weather") if wtr else []
    qw_days = qw.get("daily") if qw else []

    daily = []
    for i, d in enumerate(d_dates):
        tmax_items = [(_f(d_tmax[i]), "open-meteo")]
        tmin_items = [(_f(d_tmin[i]), "open-meteo")]
        if ecm and ecm.get("daily"):
            e_max = ecm["daily"].get("temperature_2m_max") or []
            e_min = ecm["daily"].get("temperature_2m_min") or []
            if i < len(e_max):
                tmax_items.append((_f(e_max[i]), "ecmwf"))
            if i < len(e_min):
                tmin_items.append((_f(e_min[i]), "ecmwf"))
        if i < 3 and wttr_days:
            wd = wttr_days[i]
            tmax_items.append((_f(wd.get("maxtempC")), "wttr.in"))
            tmin_items.append((_f(wd.get("mintempC")), "wttr.in"))
        if i < 7 and qw_days:
            qd = qw_days[i]
            tmax_items.append((_f(qd.get("tempMax")), "qweather"))
            tmin_items.append((_f(qd.get("tempMin")), "qweather"))
        tx, _x = _weighted(tmax_items, weights)
        tn, _n = _weighted(tmin_items, weights)
        code_d = d_codes[i] if i < len(d_codes) and d_codes[i] is not None else 0
        prob = int(d_prob[i]) if i < len(d_prob) and d_prob[i] is not None else 0
        rain = _r(d_rain[i], 1) if i < len(d_rain) else 0
        snow_cm = _r(d_snow[i], 1) if i < len(d_snow) and d_snow[i] is not None else None
        rain_sum = _r(d_rain_sum[i], 1) if i < len(d_rain_sum) and d_rain_sum[i] is not None else None
        desc_d, icon_d = wmo.precip_desc(code_d, rain_sum, snow_cm, tx, True)
        try:
            date_cn = _dt.date.fromisoformat(d[:10]).strftime("%m月%d日")
        except Exception:
            date_cn = d[:10]
        daily.append({
            "date": d[:10], "date_cn": date_cn,
            "weekday": _weekday(d, i), "code": code_d,
            "desc": desc_d, "icon": icon_d,
            "tmax": _r(tx, 1), "tmin": _r(tn, 1),
            "prob": prob, "rain": rain, "snow": snow_cm,
            "sunrise": _h2m(d_sunrise[i]) if i < len(d_sunrise) else "",
            "sunset": _h2m(d_sunset[i]) if i < len(d_sunset) else "",
        })

    # 主源缺失时用 wttr.in 的 3 天预报补全逐日，至少保证 15 天卡片不是空白
    if not daily and wttr_days:
        for i, wd in enumerate(wttr_days[:3]):
            dstr = str(wd.get("date") or "")
            hrs = wd.get("hourly") or []
            code_d = 0
            if hrs:
                midday = hrs[min(len(hrs) - 1, len(hrs) // 2)]
                code_d = int(_f(midday.get("weatherCode")) or 0)
            desc_d, icon_d = _wttrin.wwo_info(code_d)
            prob, rain = 0, 0.0
            for it in hrs:
                prob = max(prob, int(_f(it.get("chanceofrain")) or 0))
                rain += _f(it.get("precipMM")) or 0.0
            astro = (wd.get("astronomy") or [{}])[0]
            try:
                date_cn = _dt.date.fromisoformat(dstr[:10]).strftime("%m月%d日")
            except Exception:
                date_cn = dstr[:10]
            daily.append({
                "date": dstr[:10], "date_cn": date_cn,
                "weekday": _weekday(dstr, i), "code": code_d,
                "desc": desc_d, "icon": icon_d,
                "tmax": _r(_f(wd.get("maxtempC")), 1),
                "tmin": _r(_f(wd.get("mintempC")), 1),
                "prob": prob, "rain": _r(rain, 1), "snow": None,
                "sunrise": str(astro.get("sunrise") or ""),
                "sunset": str(astro.get("sunset") or ""),
            })

    today = daily[0] if daily else {}
    if not today and current.get("temp") is not None:
        # 只有实况（如中国天气网备用源）时，用当前温度填一个最小“今天”，避免首屏高低温全空
        today = {
            "date": _dt.date.today().isoformat(),
            "date_cn": _dt.date.today().strftime("%m月%d日"),
            "weekday": "今天", "code": code, "desc": desc_now, "icon": icon_now,
            "tmax": current.get("temp"), "tmin": current.get("temp"),
            "prob": 0, "rain": current.get("precip_mm") or 0, "snow": None,
            "sunrise": "", "sunset": "",
        }

    # ---------- 逐小时 ----------
    h = main.get("hourly", {}) if main else {}
    h_times = h.get("time") or []
    h_keys = {
        "temperature_2m": h.get("temperature_2m") or [],
        "relative_humidity_2m": h.get("relative_humidity_2m") or [],
        "apparent_temperature": h.get("apparent_temperature") or [],
        "precipitation": h.get("precipitation") or [],
        "precipitation_probability": h.get("precipitation_probability") or [],
        "weather_code": h.get("weather_code") or [],
        "wind_speed_10m": h.get("wind_speed_10m") or [],
        "wind_direction_10m": h.get("wind_direction_10m") or [],
        "wind_gusts_10m": h.get("wind_gusts_10m") or [],
        "pressure_msl": h.get("pressure_msl") or [],
        "is_day": h.get("is_day") or [],
    }
    start = 0
    if now_t:
        for i, t in enumerate(h_times):
            if t >= now_t:
                start = i
                break
    uv_map = {}
    if uv_time and uv_series:
        for i, t in enumerate(uv_time):
            uv_map[t] = (uv_series[i] if i < len(uv_series) else None,
                         vis_series[i] if vis_series else None)

    hourly = []
    for i in range(start, min(start + 48, len(h_times))):
        t = h_times[i]
        uv_v, vis_v = uv_map.get(t, (None, None))
        hc = h_keys["weather_code"][i] if i < len(h_keys["weather_code"]) and h_keys["weather_code"][i] is not None else 0
        hd = h_keys["is_day"][i] if i < len(h_keys["is_day"]) else 1
        is_day_h = hd == 1
        wind_deg = h_keys["wind_direction_10m"][i] if i < len(h_keys["wind_direction_10m"]) else None
        hourly.append({
            "datetime": t, "date": t[:10], "time": _h2m(t),
            "code": hc, "desc": wmo.describe(hc, is_day_h),
            "icon": wmo.icon_key(hc, is_day_h), "is_day": is_day_h,
            "temp": _r(h_keys["temperature_2m"][i], 1) if i < len(h_keys["temperature_2m"]) else None,
            "feels": _r(h_keys["apparent_temperature"][i], 1) if i < len(h_keys["apparent_temperature"]) else None,
            "humidity": int(h_keys["relative_humidity_2m"][i]) if i < len(h_keys["relative_humidity_2m"]) and h_keys["relative_humidity_2m"][i] is not None else None,
            "pressure": _r(h_keys["pressure_msl"][i], 0) if i < len(h_keys["pressure_msl"]) else None,
            "wind": _r(h_keys["wind_speed_10m"][i], 1) if i < len(h_keys["wind_speed_10m"]) else None,
            "gust": _r(h_keys["wind_gusts_10m"][i], 1) if i < len(h_keys["wind_gusts_10m"]) else None,
            "wind_dir": wmo.wind_dir_text(_f(wind_deg)),
            "wind_dir_deg": _r(wind_deg, 0),
            "precip": _r(h_keys["precipitation"][i], 1) if i < len(h_keys["precipitation"]) else None,
            "prob": int(h_keys["precipitation_probability"][i]) if i < len(h_keys["precipitation_probability"]) and h_keys["precipitation_probability"][i] is not None else 0,
            "uv": _r(uv_v, 1), "vis": _r(vis_v / 1000.0 if vis_v is not None else None, 1),
        })

    # 主源缺失时用 wttr.in 的 3 小时粒度补全逐小时（最多 48 条，跳过今天已过去的时段）
    if not hourly and wtr:
        now_hour = _dt.datetime.now().hour
        for di, wd in enumerate(wttr_days[:3]):
            dstr = str(wd.get("date") or "")[:10]
            for it in (wd.get("hourly") or []):
                hh = int(_f(it.get("time")) or 0) // 100
                if di == 0 and hh < now_hour:
                    continue
                code_h = int(_f(it.get("weatherCode")) or 0)
                day_flag = it.get("isDayTime")
                is_day_h = (str(day_flag).lower() in ("yes", "true", "1")) if day_flag is not None \
                    else (6 <= hh < 18)
                desc_h, icon_h = _wttrin.wwo_info(code_h)
                hourly.append({
                    "datetime": f"{dstr}T{hh:02d}:00", "date": dstr,
                    "time": f"{hh:02d}:00", "code": code_h,
                    "desc": desc_h, "icon": icon_h, "is_day": is_day_h,
                    "temp": _r(_f(it.get("tempC")), 1),
                    "feels": _r(_f(it.get("FeelsLikeC")), 1),
                    "humidity": int(_f(it.get("humidity"))) if _f(it.get("humidity")) is not None else None,
                    "pressure": _r(_f(it.get("pressure")), 0),
                    "wind": _r(_f(it.get("windspeedKmph")), 1),
                    "gust": _r(_f(it.get("WindGustKmph")), 1),
                    "wind_dir": str(it.get("winddir16Point") or ""),
                    "wind_dir_deg": _r(_f(it.get("winddirDegree")), 0),
                    "precip": _r(_f(it.get("precipMM")), 1),
                    "prob": int(_f(it.get("chanceofrain")) or 0),
                    "uv": _r(_f(it.get("uvIndex")), 1),
                    "vis": _r(_f(it.get("visibility")), 1),
                })
                if len(hourly) >= 48:
                    break
            if len(hourly) >= 48:
                break

    # ---------- 数据源清单 ----------
    qw_key = bool(cfg.get("qweather_key"))
    links = [
        {"name": "Open-Meteo", "url": "https://open-meteo.com/",
         "desc": "主数据源：实时 · 逐小时 · 15 天 · 无密钥免费",
         "enabled": True, "used": True},
        {"name": "中国天气网", "url": "http://www.weather.com.cn/",
         "desc": "国内官方实测：国标 AQI · 实况温度",
         "enabled": True, "used": cc is not None},
        {"name": "Open-Meteo 空气质量", "url": "https://open-meteo.com/en/docs/air-quality-api",
         "desc": "空气污染参考（模型浓度，仅当官方缺失时使用）",
         "enabled": True, "used": aq is not None},
        {"name": "Open-Meteo 地理编码", "url": "https://open-meteo.com/en/docs/geocoding-api",
         "desc": "城市坐标解析",
         "enabled": True, "used": True},
        {"name": "wttr.in", "url": "https://wttr.in/",
         "desc": "交叉校验源（WorldWeatherOnline 派生数据）",
         "enabled": True, "used": wtr is not None},
        {"name": "和风天气", "url": "https://dev.qweather.com/",
         "desc": "可选：config.json 填入免费 Key 后启用",
         "enabled": qw_key, "used": qw is not None},
        {"name": "墨迹天气", "url": "https://www.moji.com/",
         "desc": "参考站点（无公开 API，仅展示参考）",
         "enabled": False, "used": False},
        {"name": "ip-api.com", "url": "https://ip-api.com/",
         "desc": "IP 自动定位",
         "enabled": True, "used": bool(loc.get("auto"))},
    ]

    # 提示语：同时给出“已拼好的简体串”和“模板 + 参数”。
    # 模板保留到缓存里，切到繁体/英文后重新渲染，不会把旧语言的句子带出来。
    note = ""
    note_tpl = []
    if fallback_used:
        fallback_names = {"wttr": "wttr.in", "chinacom": "中国天气网"}
        src = fallback_names.get(fallback_used, fallback_used)
        tpl = "⚠ Open-Meteo 主数据源连接失败，当前使用 {src} 备用源（数据可能不完整）"
        note = tpl.format(src=src)
        note_tpl.append([tpl, {"src": src}])
    elif combined is None:
        note = "所有数据源均不可用，请检查网络"
        note_tpl.append(["所有数据源均不可用，请检查网络", {}])
    elif spread > 2.5:
        tpl = "多源温差 {spread}°C，已按加权平均+离群剔除（数据差异较大，仅供参考）"
        note = tpl.format(spread=f"{spread:.1f}")
        note_tpl.append([tpl, {"spread": f"{spread:.1f}"}])
    if timed_out:
        src_names = {
            "main": "Open-Meteo", "uv": "UV/能见度", "aq": "空气质量",
            "gfs": "GFS", "ecmwf": "ECMWF", "wttr": "wttr.in",
            "cc": "中国天气网", "qw": "和风天气", "alarm": "预警",
        }
        srcs = [src_names.get(k, k) for k in timed_out]
        tpl = "部分数据源响应超时（{srcs}），已用其余数据继续显示"
        tnote = tpl.format(srcs="、".join(srcs))
        note = (note + "；" if note else "") + tnote
        note_tpl.append([tpl, {"srcs": srcs}])

    # 更新时间：优先用主数据源返回的城市当地时间
    main_now = (main.get("current") or {}).get("time")
    if main_now and "T" in str(main_now):
        _upd = str(main_now)
        updated, updated_full, updated_tz, updated_source = _upd[11:16], _upd.replace("T", " "), loc.get("timezone", "auto"), "location"
    else:
        updated = _dt.datetime.now().strftime("%H:%M")
        updated_full = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        updated_tz, updated_source = "", "local"

    labels = {"open-meteo": "Open-Meteo", "chinacom": "中国天气网", "gfs": "GFS",
              "ecmwf": "ECMWF", "wttr.in": "wttr.in", "qweather": "和风天气"}
    used_temps = [(_v, k) for _v, k in temp_items if _v is not None]
    wsum = sum(weights.get(k, 0.0) for _v, k in used_temps)
    method_parts = []
    if used_temps and wsum > 0:
        method_parts = [[labels.get(k, k), f"{weights.get(k, 0.0) / wsum:.0%}"] for _v, k in used_temps]
        parts_text = " / ".join(f"{n} {p}" for n, p in method_parts)
        method = "当前温度 = " + parts_text + " 加权平均（缺失源自动归一化）；逐日高低温同法。"
        method_tpl = "当前温度 = {parts} 加权平均（缺失源自动归一化）；逐日高低温同法。"
    else:
        method = "当前温度：无可用数据源"
        method_tpl = "当前温度：无可用数据源"

    return {
        "meta": {
            "updated": updated,
            "updated_full": updated_full,
            "updated_tz": updated_tz,
            "updated_source": updated_source,
            "fetched_at": _dt.datetime.now().strftime("%m-%d %H:%M"),
            "fetched_ts": _dt.datetime.now().timestamp(),
            "query": loc.get("name", ""),
            "auto": loc.get("auto", False),
            "method": method,
            "_method_tpl": method_tpl,
            "_method_parts": method_parts,
            "note": note,
            "_note_tpl": note_tpl,
            "partial": bool(fallback_used or timed_out or main is None),
            "fallback": fallback_used,
            "timed_out": timed_out,
        },
        "location": {
            "name": loc.get("name", ""), "admin": loc.get("admin", ""),
            "country": loc.get("country", ""), "country_code": loc.get("country_code", ""),
            "lat": loc.get("lat"), "lon": loc.get("lon"),
            "timezone": loc.get("timezone", "auto"),
            "loc_source": loc.get("loc_source", ""),
            "accuracy_m": loc.get("accuracy_m"),
        },
        "current": current,
        "today": today,
        "daily": daily[:16],
        "hourly": hourly,
        "source_links": links,
    }
