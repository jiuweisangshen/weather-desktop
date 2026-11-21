# -*- coding: utf-8 -*-
"""地理编码：Open-Meteo Geocoding（别名 + 可信度排序）→ Nominatim 兜底 → IP 自动定位
合入 team/deepseek/patches/geo_patch.py 的排序算法：中文常见外国城市别名表、
中英文双查、按首都/人口/国家码命中排序，避免"伦敦→加拿大"这类错误。"""
from __future__ import annotations

import math
import os
import re
import time

import requests

_GEO_URL = "https://geocoding-api.open-meteo.com/v1/search"
_UA = {"User-Agent": "WeatherAggregate/1.0"}

# 中文 -> (英文查询名, 期望国家码)
ALIASES = {
    "伦敦": ("London", "GB"), "纽约": ("New York", "US"), "东京": ("Tokyo", "JP"),
    "巴黎": ("Paris", "FR"), "柏林": ("Berlin", "DE"), "罗马": ("Rome", "IT"),
    "米兰": ("Milan", "IT"), "马德里": ("Madrid", "ES"), "巴塞罗那": ("Barcelona", "ES"),
    "阿姆斯特丹": ("Amsterdam", "NL"), "维也纳": ("Vienna", "AT"),
    "苏黎世": ("Zurich", "CH"), "日内瓦": ("Geneva", "CH"),
    "慕尼黑": ("Munich", "DE"), "法兰克福": ("Frankfurt", "DE"),
    "莫斯科": ("Moscow", "RU"), "首尔": ("Seoul", "KR"), "釜山": ("Busan", "KR"),
    "新加坡": ("Singapore", "SG"), "曼谷": ("Bangkok", "TH"),
    "吉隆坡": ("Kuala Lumpur", "MY"), "雅加达": ("Jakarta", "ID"),
    "马尼拉": ("Manila", "PH"), "河内": ("Hanoi", "VN"),
    "悉尼": ("Sydney", "AU"), "墨尔本": ("Melbourne", "AU"),
    "奥克兰": ("Auckland", "NZ"), "多伦多": ("Toronto", "CA"),
    "温哥华": ("Vancouver", "CA"), "洛杉矶": ("Los Angeles", "US"),
    "旧金山": ("San Francisco", "US"), "华盛顿": ("Washington", "US"),
    "芝加哥": ("Chicago", "US"), "西雅图": ("Seattle", "US"),
    "波士顿": ("Boston", "US"), "迪拜": ("Dubai", "AE"),
    "开普敦": ("Cape Town", "ZA"), "圣保罗": ("Sao Paulo", "BR"),
    "墨西哥城": ("Mexico City", "MX"), "布宜诺斯艾利斯": ("Buenos Aires", "AR"),
    "香港": ("Hong Kong", "HK"), "澳门": ("Macau", "MO"), "台北": ("Taipei", "TW"),
    "大阪": ("Osaka", "JP"), "京都": ("Kyoto", "JP"), "札幌": ("Sapporo", "JP"),
    "福冈": ("Fukuoka", "JP"), "名古屋": ("Nagoya", "JP"),
    "雷克雅未克": ("Reykjavik", "IS"), "斯德哥尔摩": ("Stockholm", "SE"),
    "哥本哈根": ("Copenhagen", "DK"), "赫尔辛基": ("Helsinki", "FI"),
    "奥斯陆": ("Oslo", "NO"), "华沙": ("Warsaw", "PL"), "布拉格": ("Prague", "CZ"),
    "布达佩斯": ("Budapest", "HU"), "伊斯坦布尔": ("Istanbul", "TR"),
    "雅典": ("Athens", "GR"), "里斯本": ("Lisbon", "PT"), "都柏林": ("Dublin", "IE"),
    "渥太华": ("Ottawa", "CA"), "休斯顿": ("Houston", "US"),
    "迈阿密": ("Miami", "US"), "夏威夷": ("Honolulu", "US"),
    "圣迭戈": ("San Diego", "US"), "费城": ("Philadelphia", "US"),
    "亚特兰大": ("Atlanta", "US"), "丹佛": ("Denver", "US"),
    "拉斯维加斯": ("Las Vegas", "US"), "凤凰城": ("Phoenix", "US"),
    "惠灵顿": ("Wellington", "NZ"), "孟买": ("Mumbai", "IN"),
    "德里": ("Delhi", "IN"), "班加罗尔": ("Bangalore", "IN"),
    "开罗": ("Cairo", "EG"), "内罗毕": ("Nairobi", "KE"),
    "约翰内斯堡": ("Johannesburg", "ZA"), "卡拉奇": ("Karachi", "PK"),
    "达卡": ("Dhaka", "BD"), "科伦坡": ("Colombo", "LK"),
    "安卡拉": ("Ankara", "TR"), "基辅": ("Kyiv", "UA"),
    "布加勒斯特": ("Bucharest", "RO"), "贝尔格莱德": ("Belgrade", "RS"),
}

_FEATURE_SCORE = {"PPLC": 250, "PPLA": 120, "PPLA2": 60, "PPL": 0}

# 常用中国区县本地兜底（Open-Meteo 中文对"市/区/县"后缀覆盖差且缺区县库）：
# core名 -> (所属市, 纬度, 经度)。匹配时优先于网络查询，保证区县级编译确定性。
LOCAL_DISTRICTS = {
    # 北京
    "海淀": ("北京市", 39.95933, 116.29821), "朝阳": ("北京市", 39.92149, 116.44327),
    "东城": ("北京市", 39.92835, 116.41618), "西城": ("北京市", 39.91220, 116.36591),
    "丰台": ("北京市", 39.85840, 116.28704), "石景山": ("北京市", 39.90660, 116.22296),
    "通州": ("北京市", 39.90968, 116.65716), "大兴": ("北京市", 39.72675, 116.34097),
    "顺义": ("北京市", 40.13054, 116.65460), "房山": ("北京市", 39.74797, 116.14326),
    "昌平": ("北京市", 40.22076, 116.23120), "门头沟": ("北京市", 39.94065, 116.10143),
    "怀柔": ("北京市", 40.31612, 116.63195), "密云": ("北京市", 40.37687, 116.84301),
    "平谷": ("北京市", 40.14066, 117.12138), "延庆": ("北京市", 40.45678, 115.97464),
    # 上海
    "浦东": ("上海市", 31.22134, 121.54472), "徐汇": ("上海市", 31.18844, 121.43629),
    "静安": ("上海市", 31.22764, 121.44737), "黄浦": ("上海市", 31.23158, 121.48452),
    "长宁": ("上海市", 31.22041, 121.42440), "普陀": ("上海市", 31.24969, 121.39696),
    "虹口": ("上海市", 31.26476, 121.50497), "杨浦": ("上海市", 31.25945, 121.52614),
    "闵行": ("上海市", 31.11257, 121.38160), "宝山": ("上海市", 31.40490, 121.48957),
    "嘉定": ("上海市", 31.37587, 121.26533), "松江": ("上海市", 31.00584, 121.22695),
    "青浦": ("上海市", 31.15074, 121.12418), "奉贤": ("上海市", 30.91770, 121.47403),
    "崇明": ("上海市", 31.62314, 121.39739), "金山": ("上海市", 30.74221, 121.34151),
    # 广州
    "白云": ("广州市", 23.15758, 113.27325), "天河": ("广州市", 23.12467, 113.36120),
    "越秀": ("广州市", 23.12894, 113.26658), "海珠": ("广州市", 23.08380, 113.31717),
    "荔湾": ("广州市", 23.12585, 113.24385), "黄埔": ("广州市", 23.18153, 113.48078),
    "番禺": ("广州市", 22.93724, 113.38435), "花都": ("广州市", 23.40300, 113.22014),
    "南沙": ("广州市", 22.80161, 113.52509), "从化": ("广州市", 23.54850, 113.58661),
    "增城": ("广州市", 23.26135, 113.81057),
    # 深圳
    "福田": ("深圳市", 22.54104, 114.05534), "南山": ("深圳市", 22.53340, 113.93057),
    "罗湖": ("深圳市", 22.56231, 114.13159), "宝安": ("深圳市", 22.55474, 113.88309),
    "龙岗": ("深圳市", 22.72166, 114.24684), "龙华": ("深圳市", 22.69656, 114.03617),
    "盐田": ("深圳市", 22.55712, 114.23568), "光明": ("深圳市", 22.74853, 113.93593),
    "坪山": ("深圳市", 22.70891, 114.34619), "大鹏": ("深圳市", 22.59628, 114.47985),
    # 其他主要城市核心区
    "天府": ("成都市", 30.50845, 104.06615), "武侯": ("成都市", 30.64266, 104.04316),
    "锦江": ("成都市", 30.65735, 104.08354), "青羊": ("成都市", 30.67435, 104.06215),
    "成华": ("成都市", 30.66027, 104.10100), "金牛": ("成都市", 30.69153, 104.05210),
    "西湖": ("杭州市", 30.25947, 120.13022), "上城": ("杭州市", 30.24251, 120.16914),
    "拱墅": ("杭州市", 30.31887, 120.14187), "滨江": ("杭州市", 30.20856, 120.21196),
    "余杭": ("杭州市", 30.41906, 120.30059), "萧山": ("杭州市", 30.18376, 120.26425),
    "江宁": ("南京市", 31.95257, 118.83969), "鼓楼": ("南京市", 32.06638, 118.76996),
    "玄武": ("南京市", 32.04848, 118.79823), "秦淮": ("南京市", 32.01900, 118.79478),
    "建邺": ("南京市", 32.00302, 118.73182), "栖霞": ("南京市", 32.09634, 118.90930),
    "武昌": ("武汉市", 30.55443, 114.31592), "汉口": ("武汉市", 30.58750, 114.27330),
    "汉阳": ("武汉市", 30.54968, 114.21868), "洪山": ("武汉市", 30.49979, 114.34341),
    "青山": ("武汉市", 30.64067, 114.38507), "江岸": ("武汉市", 30.60051, 114.30939),
    "雁塔": ("西安市", 34.22256, 108.94895), "碑林": ("西安市", 34.23040, 108.93418),
    "莲湖": ("西安市", 34.26538, 108.94133), "未央": ("西安市", 34.29335, 108.94679),
    "新城": ("西安市", 34.26704, 108.96086), "灞桥": ("西安市", 34.27284, 109.06467),
    "渝中": ("重庆市", 29.55274, 106.56893), "渝北": ("重庆市", 29.71831, 106.63120),
    "江北": ("重庆市", 29.60621, 106.57462), "南岸": ("重庆市", 29.52142, 106.56046),
    "沙坪坝": ("重庆市", 29.54107, 106.45775), "九龙坡": ("重庆市", 29.50220, 106.51068),
    "思明": ("厦门市", 24.44580, 118.08253), "湖里": ("厦门市", 24.51265, 118.14677),
    "集美": ("厦门市", 24.57590, 118.10086), "海沧": ("厦门市", 24.48468, 118.03269),
    "岳麓": ("长沙市", 28.23507, 112.93076), "芙蓉": ("长沙市", 28.19580, 113.03227),
    "天心": ("长沙市", 28.11435, 112.98971), "开福": ("长沙市", 28.25586, 112.98548),
    "历下": ("济南市", 36.66653, 117.07660), "市中": ("济南市", 36.65119, 116.99773),
    "槐荫": ("济南市", 36.65124, 116.90100), "天桥": ("济南市", 36.67848, 116.98719),
    "金水": ("郑州市", 34.80002, 113.66034), "二七": ("郑州市", 34.72415, 113.64435),
    "中原": ("郑州市", 34.74813, 113.61298), "管城": ("郑州市", 34.75413, 113.67733),
    "姑苏": ("苏州市", 31.30408, 120.61724), "园区": ("苏州市", 31.31680, 120.67230),
    "虎丘": ("苏州市", 31.29737, 120.57208), "吴中": ("苏州市", 31.26225, 120.63224),
    "湘江": ("长沙市", 28.11562, 112.94560), "开福": ("长沙市", 28.25586, 112.98548),
    "鼓楼": ("南京市", 32.06638, 118.76996), "玄武": ("南京市", 32.04848, 118.79823),
    # 常见县级市/县（网络常搜不到带"县"后缀的）
    "昆山": ("苏州市", 31.38560, 120.98070), "张家港": ("苏州市", 31.86529, 120.55317),
    "常熟": ("苏州市", 31.65408, 120.75235), "太仓": ("苏州市", 31.44928, 121.12874),
    "慈溪": ("宁波市", 30.16966, 121.26658), "余姚": ("宁波市", 30.03703, 121.15435),
    "江阴": ("无锡市", 31.92113, 120.28493), "宜兴": ("无锡市", 31.34020, 119.82322),
    "浏阳": ("长沙市", 28.13900, 113.63320), "宁乡": ("长沙市", 28.27755, 112.55160),
    "晋江": ("泉州市", 24.78164, 118.55235), "石狮": ("泉州市", 24.73197, 118.64804),
    "瑞安": ("温州市", 27.77836, 120.65514), "乐清": ("温州市", 28.11300, 120.95800),
    "义乌": ("金华市", 29.31506, 120.07676), "永康": ("金华市", 28.88853, 120.04730),
    "诸暨": ("绍兴市", 29.70870, 120.23658), "嵊州": ("绍兴市", 29.59130, 120.82100),
    "海宁": ("嘉兴市", 30.50994, 120.68800), "桐乡": ("嘉兴市", 30.63260, 120.56500),
}


class GeoError(RuntimeError):
    pass


def _has_cjk(s: str) -> bool:
    return bool(re.search(r"[\u4e00-\u9fff]", s or ""))


def _search(name: str, lang: str, count: int, timeout: float):
    # 轻量重试：Open-Meteo 偶发限流/超时返回空，延迟一次即可恢复
    for attempt in (0, 1):
        try:
            r = requests.get(_GEO_URL, params={"name": name, "count": count,
                                               "language": lang, "format": "json"},
                             timeout=timeout, headers=_UA)
            r.raise_for_status()
            results = r.json().get("results") or []
            if results:
                return results
        except Exception:
            pass
        if attempt == 0:
            time.sleep(0.6)
    return []


def _score(x: dict, query: str, alias: tuple | None) -> float:
    """人口对数为主，首府加成次之，别名国家码仅作同级微调。"""
    pop = x.get("population") or 0
    if pop > 0:
        score = min(400.0, math.log10(pop) * 60.0)  # 1 万≈240，100 万≈360，1000 万≈400
    else:
        score = 0.0
    score += _FEATURE_SCORE.get(x.get("feature_code") or "", 0)
    nm = (x.get("name") or "").lower()
    if nm == (query or "").lower() or (alias and nm == alias[0].lower()):
        score += 150
    if alias and x.get("country_code") == alias[1] and nm == alias[0].lower():
        score += 300
    return score


def _strip_admin(q: str) -> list:
    """Open-Meteo 对带行政区划后缀的中文名覆盖差（"海淀区/北京市海淀区"搜不到，
    而"海淀"能搜到）。生成逐级剥离后的候选查询序列。"""
    cands = []
    s = q
    changed = True
    while changed and len(s) > 2:
        changed = False
        for suf in ("市", "区", "县", "旗", "盟", "州"):
            if s.endswith(suf) and len(s) > 2:
                s = s[: -len(suf)]
                changed = True
                break
    if s and s != q:
        cands.append(s)
    # 头部"X市"前缀剥离（通用化）："广州市白云" -> "白云"
    m = re.match(r"^(.{2,4}市)", s)
    if m and len(s) > len(m.group(1)):
        t = s[len(m.group(1)):]
        if t:
            cands.append(t)
    return cands


def local_lookup(query: str):
    """离线区县/县级市兜底：命中返回 loc，否则 None（不发起网络请求）。"""
    q = (query or "").strip()
    if not q:
        return None
    for v in [q] + _strip_admin(q):
        hit = LOCAL_DISTRICTS.get(v)
        if hit:
            return {"name": q, "admin": hit[0], "country": "中国",
                    "country_code": "CN", "lat": hit[1], "lon": hit[2],
                    "timezone": "Asia/Shanghai", "via": "local-district"}
    return None


def search_candidates(query: str, count: int = 8, timeout: float = 8) -> list:
    """按可信度排序的候选城市（经纬度去重）"""
    q = (query or "").strip()
    if not q:
        return []
    alias = ALIASES.get(q)
    pools = [(_search(q, "zh", count, timeout), None)]
    if alias:
        pools.append((_search(alias[0], "en", count, timeout), alias))
    elif not _has_cjk(q):
        pools.append((_search(q, "en", count, timeout), None))

    merged = {}
    for pool, al in pools:
        for x in pool:
            lat, lon = x.get("latitude"), x.get("longitude")
            if lat is None or lon is None:
                continue
            key = (round(float(lat), 2), round(float(lon), 2))
            item = dict(x)
            item["_score"] = _score(x, q, al)
            if key not in merged or item["_score"] > merged[key]["_score"]:
                merged[key] = item

    out = sorted(merged.values(), key=lambda z: z["_score"], reverse=True)[:count]
    for x in out:
        x.pop("_score", None)
    return out


def _to_loc(r: dict, q: str, via: str) -> dict:
    return {"name": r.get("name", q), "admin": r.get("admin1", ""),
            "country": r.get("country", ""), "country_code": r.get("country_code", ""),
            "lat": float(r["latitude"]), "lon": float(r["longitude"]),
            "timezone": r.get("timezone", "auto"), "population": r.get("population"),
            "via": via}


def geocode(query: str, timeout: float = 8) -> dict:
    """解析城市名/经纬度，返回 {name, admin, country, country_code, lat, lon, timezone}"""
    q = (query or "").strip()
    if not q:
        raise GeoError("城市名为空")

    # 支持直接输入坐标 "39.9,116.4"
    try:
        parts = q.replace("，", ",").split(",")
        if len(parts) == 2:
            la, lo = float(parts[0].strip()), float(parts[1].strip())
            if -90 <= la <= 90 and -180 <= lo <= 180:
                return {"name": f"{la:.2f},{lo:.2f}", "admin": "", "country": "",
                        "country_code": "", "lat": la, "lon": lo,
                        "timezone": "auto", "via": "coords"}
    except (ValueError, TypeError):
        pass

    # 南极特判：避免地理编码把"南极"错配到国内同名村镇（如"辽宁·南极"）
    if q in ("南极", "南极洲", "南极点"):
        return {"name": "南极洲", "admin": "南极", "country": "南极洲",
                "country_code": "AQ", "lat": -90.0, "lon": 0.0,
                "timezone": "Antarctica/South_Pole", "via": "special"}

    # 中国区县本地兜底："海淀区/北京市海淀区/广州市白云区" -> 变体"海淀"/"白云"命中即返回
    hit = local_lookup(q)
    if hit:
        return hit

    # 后缀剥离变体优先搜索："上海市" -> "上海"（原词常被 Open-Meteo 错配到同名村镇）
    cands, used_v = [], None
    for v in (_strip_admin(q) or [q]):
        c2 = search_candidates(v, count=8, timeout=timeout)
        if not c2:
            continue
        cands = c2
        used_v = v
        # 原词或变体命中中国条目即采用（避免"上海市"错配美国伊利诺伊）
        if any(x.get("country_code") == "CN" for x in c2):
            break
    if cands:
        return _to_loc(cands[0], q, "open-meteo-ranked")

    # 兜底：Nominatim（限时 4s，避免拖慢）
    try:
        r = requests.get("https://nominatim.openstreetmap.org/search",
                         params={"q": q, "format": "json", "limit": 1, "addressdetails": 1},
                         timeout=min(timeout, 4), headers=_UA)
        data = r.json()
        if data:
            x = data[0]
            addr = x.get("address", {})
            return {"name": x.get("display_name", q).split(",")[0],
                    "admin": addr.get("state") or addr.get("region") or "",
                    "country": addr.get("country", ""),
                    "country_code": addr.get("country_code", "").upper() if addr.get("country_code") else "",
                    "lat": float(x["lat"]), "lon": float(x["lon"]),
                    "timezone": "auto", "via": "nominatim"}
    except Exception:
        pass

    raise GeoError(f"未找到城市：{q}")


# 常用城市候选（搜索候选栏用；副标题=省份/直辖市）
COMMON_CITIES = [
    ("北京", "直辖市"), ("上海", "直辖市"), ("天津", "直辖市"), ("重庆", "直辖市"),
    ("广州", "广东"), ("深圳", "广东"), ("珠海", "广东"), ("佛山", "广东"),
    ("东莞", "广东"), ("中山", "广东"), ("惠州", "广东"), ("汕头", "广东"),
    ("成都", "四川"), ("绵阳", "四川"), ("乐山", "四川"), ("泸州", "四川"),
    ("宜宾", "四川"), ("南充", "四川"), ("自贡", "四川"), ("达州", "四川"),
    ("杭州", "浙江"), ("宁波", "浙江"), ("温州", "浙江"), ("嘉兴", "浙江"),
    ("绍兴", "浙江"), ("金华", "浙江"), ("台州", "浙江"), ("湖州", "浙江"),
    ("南京", "江苏"), ("苏州", "江苏"), ("无锡", "江苏"), ("常州", "江苏"),
    ("南通", "江苏"), ("徐州", "江苏"), ("扬州", "江苏"), ("盐城", "江苏"),
    ("武汉", "湖北"), ("宜昌", "湖北"), ("襄阳", "湖北"), ("荆州", "湖北"),
    ("西安", "陕西"), ("咸阳", "陕西"), ("宝鸡", "陕西"), ("延安", "陕西"),
    ("长沙", "湖南"), ("株洲", "湖南"), ("岳阳", "湖南"), ("常德", "湖南"),
    ("郑州", "河南"), ("洛阳", "河南"), ("开封", "河南"), ("新乡", "河南"),
    ("济南", "山东"), ("青岛", "山东"), ("烟台", "山东"), ("潍坊", "山东"),
    ("威海", "山东"), ("淄博", "山东"), ("临沂", "山东"),
    ("石家庄", "河北"), ("唐山", "河北"), ("保定", "河北"), ("廊坊", "河北"),
    ("秦皇岛", "河北"), ("承德", "河北"), ("张家口", "河北"), ("邯郸", "河北"),
    ("太原", "山西"), ("大同", "山西"), ("沈阳", "辽宁"), ("大连", "辽宁"),
    ("长春", "吉林"), ("吉林", "吉林"), ("哈尔滨", "黑龙江"), ("大庆", "黑龙江"),
    ("合肥", "安徽"), ("芜湖", "安徽"), ("安庆", "安徽"), ("黄山", "安徽"),
    ("福州", "福建"), ("厦门", "福建"), ("泉州", "福建"), ("漳州", "福建"),
    ("莆田", "福建"), ("宁德", "福建"), ("南昌", "江西"), ("九江", "江西"),
    ("赣州", "江西"), ("上饶", "江西"), ("昆明", "云南"), ("大理", "云南"),
    ("丽江", "云南"), ("贵阳", "贵州"), ("南宁", "广西"), ("桂林", "广西"),
    ("北海", "广西"), ("柳州", "广西"), ("海口", "海南"), ("三亚", "海南"),
    ("兰州", "甘肃"), ("西宁", "青海"), ("银川", "宁夏"), ("乌鲁木齐", "新疆"),
    ("拉萨", "西藏"), ("呼和浩特", "内蒙古"), ("包头", "内蒙古"), ("鄂尔多斯", "内蒙古"),
    ("台北", "台湾"), ("香港", "香港"), ("澳门", "澳门"),
]

_COUNTRY_ZH = {
    "IS": "冰岛", "SE": "瑞典", "DK": "丹麦", "FI": "芬兰", "NO": "挪威",
    "PL": "波兰", "CZ": "捷克", "HU": "匈牙利", "TR": "土耳其", "GR": "希腊",
    "PT": "葡萄牙", "IE": "爱尔兰", "CA": "加拿大", "US": "美国", "NZ": "新西兰",
    "IN": "印度", "EG": "埃及", "KE": "肯尼亚", "ZA": "南非", "PK": "巴基斯坦",
    "BD": "孟加拉", "LK": "斯里兰卡", "UA": "乌克兰", "RO": "罗马尼亚", "RS": "塞尔维亚",
    "JP": "日本", "KR": "韩国", "SG": "新加坡", "TH": "泰国", "MY": "马来西亚",
    "AU": "澳大利亚", "GB": "英国", "FR": "法国", "DE": "德国", "IT": "意大利",
    "ES": "西班牙", "NL": "荷兰", "RU": "俄罗斯", "CH": "瑞士", "MX": "墨西哥",
    "BR": "巴西", "AR": "阿根廷", "CH": "瑞士", "AT": "奥地利", "BE": "比利时",
}


def suggest_candidates(text: str, limit: int = 10) -> list:
    """搜索候选栏数据：本地区县 + 常用城市 + 国外别名，前缀/包含匹配"""
    q = (text or "").strip()
    if not q:
        return []
    pool = []

    def add(name, sub):
        pool.append({"label": name, "sub": sub})

    for k, (city, _la, _lo) in LOCAL_DISTRICTS.items():
        add(k, city)
    for name, prov in COMMON_CITIES:
        add(name, prov)
    for zh, (en, cc) in ALIASES.items():
        add(zh, _COUNTRY_ZH.get(cc, cc))

    def rank(it):
        n = it["label"]
        if n == q:
            return 0
        if n.startswith(q):
            return 1
        if q in n:
            return 2
        return 3

    matched = [x for x in pool if rank(x) < 3]
    matched.sort(key=lambda x: (rank(x), x["label"]))
    # 同名去重（区县与城市可能同名）
    seen, out = set(), []
    for x in matched:
        if x["label"] in seen:
            continue
        seen.add(x["label"])
        out.append(x)
        if len(out) >= limit:
            break
    return out


def locate_by_ip(timeout: float = 6) -> dict:
    """IP 自动定位，失败返回 None"""
    try:
        r = requests.get("http://ip-api.com/json/?lang=zh-CN", timeout=timeout)
        data = r.json()
        if data.get("status") == "success":
            return {"name": data.get("city") or "", "region": data.get("regionName") or "",
                    "lat": data["lat"], "lon": data["lon"]}
    except Exception:
        return None
    return None


# ---------------- 精确位置：Windows 系统定位（优于 IP 的城市级精度） ----------------

def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2)
    return 2 * r * math.asin(math.sqrt(a))


def windows_location(timeout: float = 10.0) -> dict | None:
    """Windows 定位服务（WinRT Geolocator）：WiFi/网络三角定位，精度通常 100m~1km。

    返回 {"lat","lon","accuracy","via"}；非 Windows、缺少 winrt 依赖、
    用户未授权定位或超时，均返回 None（不影响后续 IP 兜底）。
    """
    if os.name != "nt":
        return None
    try:
        import asyncio

        from winrt.windows.devices.geolocation import Geolocator, PositionAccuracy
    except Exception:
        return None

    async def _run():
        locator = Geolocator()
        try:
            locator.desired_accuracy = PositionAccuracy.HIGH
        except Exception:
            pass
        pos = await locator.get_geoposition_async()
        c = pos.coordinate
        return {"lat": float(c.latitude), "lon": float(c.longitude),
                "accuracy": float(c.accuracy or 0.0), "via": "windows"}

    try:
        return asyncio.run(asyncio.wait_for(_run(), timeout))
    except Exception:
        return None


def reverse_region(lat: float, lon: float, timeout: float = 3.5) -> dict | None:
    """把坐标反查为行政区名称（区县优先），坐标本身仍用实测值。

    首选 BigDataCloud 反查（免 Key、支持简体中文）；Nominatim 在国内网络常连不通，
    仅作次选并压短超时，避免拖慢启动。
    """
    try:
        r = requests.get("https://api.bigdatacloud.net/data/reverse-geocode-client",
                         params={"latitude": lat, "longitude": lon,
                                 "localityLanguage": "zh-Hans"},
                         timeout=timeout, headers=_UA)
        d = r.json() or {}
        name = (d.get("locality") or d.get("city") or "").strip()
        if name:
            return {"name": name,
                    "admin": (d.get("city") or d.get("principalSubdivision") or "").strip(),
                    "country": d.get("countryName") or "",
                    "country_code": d.get("countryCode") or "",
                    "lat": float(lat), "lon": float(lon),
                    "timezone": "auto", "via": "bigdatacloud"}
    except Exception:
        pass

    try:
        r = requests.get("https://nominatim.openstreetmap.org/reverse",
                         params={"lat": lat, "lon": lon, "format": "json", "zoom": 12,
                                 "addressdetails": 1, "accept-language": "zh-CN"},
                         timeout=min(timeout, 2.5), headers=_UA)
        x = r.json() or {}
        addr = x.get("address") or {}
        name = (addr.get("district") or addr.get("city_district") or addr.get("suburb")
                or addr.get("town") or addr.get("city") or addr.get("county")
                or addr.get("state") or "")
        if not name:
            return None
        cc = (addr.get("country_code") or "").upper()
        return {"name": name,
                "admin": addr.get("city") or addr.get("state") or "",
                "country": "中国" if cc == "CN" else (addr.get("country") or ""),
                "country_code": cc, "lat": float(lat), "lon": float(lon),
                "timezone": "auto", "via": "reverse"}
    except Exception:
        return None


def nearest_district(lat: float, lon: float, max_km: float = 45.0):
    """离线最近邻区县，仅用于给实测坐标起名；找不到返回 None。"""
    best = None
    for key, (city, la, lo) in LOCAL_DISTRICTS.items():
        d = _haversine_km(lat, lon, la, lo)
        if best is None or d < best[0]:
            best = (d, key, city)
    if best and best[0] <= max_km:
        return best
    return None


_DIRECT_CITIES = ("北京市", "上海市", "天津市", "重庆市")


def _city_level_name(ip: dict) -> str:
    """IP 结果只取到城市级，避免把"金融街"这类街区名当成城市去编码。"""
    region = (ip.get("region") or "").strip()
    city = (ip.get("name") or "").strip()
    if region in _DIRECT_CITIES:
        return region
    if city and city in LOCAL_DISTRICTS:
        return city
    if city.endswith(("市", "区", "县", "旗")):
        return city
    # 形如"金融街""某某小区"的街区名不可靠，退到省名（省名靠核心城市兜底）
    return region or city


def resolve(query: str = None, default_city: str = "", timeout: float = 8,
            last_city: str = "", use_system: bool = True) -> dict:
    """定位优先级：显式查询 → 配置默认城市 → 上次记住的城市 → Windows 系统定位
    → IP（城市级）→ 北京。loc_source 记录本次命中的来源，便于界面与排查。"""
    if query and query.strip():
        return geocode(query, timeout)
    if default_city and default_city.strip():
        g = geocode(default_city, timeout)
        g["auto"] = True
        g["loc_source"] = "config"
        return g

    # 上次手动选择的城市：这是"不用每次启动都重新输入"的关键
    if last_city and last_city.strip():
        try:
            g = geocode(last_city, timeout)
            g["auto"] = True
            g["loc_source"] = "remembered"
            return g
        except Exception:
            pass

    # Windows 定位服务：WiFi 三角定位，通常精确到 100m~1km
    if use_system:
        wl = windows_location()
        if wl and -90 <= wl.get("lat", 999) <= 90:
            # 先用内置区县库离线匹配：国内坐标可立即得到区县名，
            # 避免反查接口（最长约 6 秒）拖慢冷启动；国外坐标才走网络反查
            nd = nearest_district(wl["lat"], wl["lon"])
            if nd:
                loc = {"name": nd[1], "admin": nd[2],
                       "country": "中国", "country_code": "CN",
                       "lat": wl["lat"], "lon": wl["lon"],
                       "timezone": "auto", "via": "windows-nearest"}
            else:
                loc = reverse_region(wl["lat"], wl["lon"])
                if loc is None:
                    loc = {"name": "当前位置", "admin": "",
                           "country": "中国", "country_code": "CN",
                           "lat": wl["lat"], "lon": wl["lon"],
                           "timezone": "auto", "via": "windows-nearest"}
                else:
                    loc["lat"], loc["lon"] = wl["lat"], wl["lon"]
            loc["auto"] = True
            loc["loc_source"] = "windows"
            loc["accuracy_m"] = wl.get("accuracy")
            return loc

    ip = locate_by_ip()
    if ip:
        city_name = _city_level_name(ip)
        if city_name:
            try:
                g = geocode(city_name, timeout)
                g["auto"] = True
                g["loc_source"] = "ip"
                g["ip_city"] = ip.get("name")
                return g
            except Exception:
                pass

    g = geocode("北京", timeout)
    g["auto"] = True
    g["loc_source"] = "fallback"
    return g


if __name__ == "__main__":
    for q in ["伦敦", "纽约", "东京", "巴黎", "北京", "上海", "杭州", "香港",
              "首尔", "悉尼", "洛杉矶", "莫斯科", "多伦多", "新加坡"]:
        try:
            r = geocode(q)
            print(f"{q:6s} -> {r['name']:12s} {r['admin']:10s} {r['country']:8s} "
                  f"{r['country_code']:3s} {r['lat']}")
        except GeoError as e:
            print(q, "-> ERROR", e)
