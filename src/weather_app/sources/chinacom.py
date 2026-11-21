# -*- coding: utf-8 -*-
"""中国天气网（weather.com.cn）——国内城市官方实测源。

用途：
  1. 官方国标 AQI（国家环境监测数据，无需换算）；
  2. 实况温度/湿度/气压/能见度/风，作为国内城市的实测交叉源。

接口（免费、无密钥、需 Referer 头）：
  - 城市ID搜索: http://toy1.weather.com.cn/search?cityname=<名>
  - 实况:        http://d1.weather.com.cn/sk_2d/<cityid>.html
响应为 GBK 编码的 JS 变量赋值，需正则提取 JSON 段。

仅支持中国大陆城市（loc.name 为中文时尝试）；国外城市返回 None。
"""
import json
import re

import requests

_UA = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
    "Referer": "http://www.weather.com.cn/",
}
_SEARCH = "http://toy1.weather.com.cn/search"
_SK = "http://d1.weather.com.cn/sk_2d/{}.html"

# 省/直辖市中文名 -> 检索结果 ref 里的省份拼音段（用于同名区县消歧，如“朝阳区”）
_PROV_PINYIN = {
    "北京": "beijing", "天津": "tianjin", "上海": "shanghai", "重庆": "chongqing",
    "河北": "hebei", "山西": "shanxi", "内蒙古": "neimenggu", "辽宁": "liaoning",
    "吉林": "jilin", "黑龙江": "heilongjiang", "江苏": "jiangsu", "浙江": "zhejiang",
    "安徽": "anhui", "福建": "fujian", "江西": "jiangxi", "山东": "shandong",
    "河南": "henan", "湖北": "hubei", "湖南": "hunan", "广东": "guangdong",
    "广西": "guangxi", "海南": "hainan", "四川": "sichuan", "贵州": "guizhou",
    "云南": "yunnan", "西藏": "xizang", "陕西": "shaanxi", "甘肃": "gansu",
    "青海": "qinghai", "宁夏": "ningxia", "新疆": "xinjiang",
    "香港": "hongkong", "澳门": "macao",
}


def _norm(name: str) -> str:
    """去掉行政区后缀，便于“朝阳区”↔“朝阳”比对"""
    s = (name or "").strip()
    return re.sub(r"(特别行政区|自治区|自治州|新区|区|县|市|旗|盟|地区)$", "", s) or s


def _prov_pinyin(admin: str) -> str:
    a = (admin or "").strip()
    for k, v in _PROV_PINYIN.items():
        if a.startswith(k):
            return v
    return ""


def _get(url, params=None, timeout=6):
    r = requests.get(url, params=params, headers=_UA, timeout=timeout)
    r.raise_for_status()
    raw = r.content
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("gbk", errors="replace")


def _extract_js(tag: str, text: str):
    """提取 'var <tag> = {...}' 的 JSON 段（花括号配对，容忍无分号结尾）"""
    i = text.find(tag + "=")
    if i < 0:
        return None
    j = text.find("{", i)
    k = text.rfind("}")
    if j < 0 or k <= j:
        return None
    try:
        return json.loads(text[j:k + 1])
    except Exception:
        return None


def search_cityid(city: str, admin: str = "", timeout: float = 6):
    """按中文城市名查 cityid（返回 {'id','name'} 或 None）

    admin 用于同名区县消歧：如“朝阳区”在全国有多个同名项，只有带省份
    （北京市）时才稳定命中 101010300（北京朝阳），否则会落到黑龙江的
    “朝阳区办事处”而导致实况解析失败。
    """
    name = (city or "").strip()
    if not name or not re.search(r"[\u4e00-\u9fff]", name):
        return None  # 国外/非中文名城市不支持

    variants = []
    for v in (name, _norm(name)):
        v = (v or "").strip()
        if v and v not in variants:
            variants.append(v)
    prov = _prov_pinyin(admin)

    best = None  # (score, -order, id, name)
    for vi, var in enumerate(variants):
        try:
            text = _get(_SEARCH, {"cityname": var, "callback": "cb"}, timeout)
        except Exception:
            continue
        m = re.search(r"\((\[.*\])\)", text, re.S)
        if not m:
            continue
        try:
            arr = json.loads(m.group(1))
        except Exception:
            continue
        for ai, item in enumerate(arr[:20]):
            ref = item.get("ref") or ""
            parts = ref.split("~")
            cid = parts[0] if parts else ""
            if not (cid.isdigit() and len(cid) == 9):
                continue  # 过滤景点/办事处等非标准城市 ID
            iname = (item.get("name") or "").strip()
            if "办事处" in iname:
                continue
            prov_item = parts[1] if len(parts) > 1 else ""
            score = 0.0
            if _norm(iname) == _norm(name):
                score += 3
            if prov and prov_item == prov:
                score += 8
            if vi == 0:
                score += 1
            score -= ai * 0.1
            cand = (score, -ai, cid, iname)
            if best is None or cand > best:
                best = cand

    if best is None:
        return None
    return {"id": best[2], "name": best[3] or name}


def fetch(city: str, admin: str = "", timeout: float = 8) -> dict:
    """返回 {now:{...}} 或抛异常"""
    loc = search_cityid(city, admin, timeout)
    if not loc:
        raise RuntimeError("中国天气网：不支持该城市")
    text = _get(_SK.format(loc["id"]), timeout=timeout)
    d = _extract_js("dataSK", text)
    if not d:
        raise RuntimeError("中国天气网：实况解析失败")

    def _f(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    wse = d.get("wse") or ""  # 如 "3km/h"
    ws_kmh = _f(re.sub(r"[^0-9.]", "", wse)) if wse else None
    qy = d.get("qy")
    njd = d.get("njd")  # 能见度，单位 km（如 "1km"）
    vis_km = _f(re.sub(r"[^0-9.]", "", njd)) if njd else None
    hum_raw = d.get("SD") or d.get("sd") or ""
    hum = _f(re.sub(r"[^0-9.]", "", hum_raw)) if hum_raw else None

    return {"now": {
        "temp": _f(d.get("temp")),
        "humidity": hum,
        "pressure": _f(qy),
        "visibility_km": vis_km,
        "wind_dir": d.get("WD") or "",
        "wind_kmh": ws_kmh,
        "weather": d.get("weather") or "",
        "aqi": _f(d.get("aqi")),
        "time": d.get("time") or "",
        "city": loc["name"],
    }, "via": "chinacom"}


if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    for c in ["北京", "上海", "广州", "深圳", "杭州", "伦敦"]:
        try:
            r = fetch(c)
            n = r["now"]
            print(f"{c}: temp={n['temp']} 湿度={n['humidity']} 气压={n['pressure']} "
                  f"能见度={n['visibility_km']}km 风={n['wind_dir']}{n['wind_kmh']}km/h "
                  f"AQI(国标)={n['aqi']} 天气={n['weather']} @{n['time']}")
        except Exception as e:
            print(f"{c}: FAIL {e}")
