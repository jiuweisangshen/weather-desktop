# -*- coding: utf-8 -*-
"""气象预警信号源。

主源：中国天气网（weather.com.cn）全国预警列表
  http://product.weather.com.cn/alarm/grepalarm_cn.php
  返回 var alarminfo={"count":...,"data":[[区域全名, url, lon, lat, id, id2, 标题], ...]}
  每条都带完整行政区路径，能精确判断"是不是本地这一级"，避免把通州/凌源的
  预警显示到朝阳区。

备用：中央气象台（nmc.cn）分页列表
  http://www.nmc.cn/rest/findAlarm?pageNo=N&pageSize=50
  只按标题里的发布主体过滤；主源不可用时兜底。

仅中国大陆城市；国外城市返回 None。
"""
import json
import re

import requests

_UA = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "zh-CN,zh;q=0.9",
    "Referer": "http://www.weather.com.cn/",
}
_CN_URL = "http://product.weather.com.cn/alarm/grepalarm_cn.php"

_NMC_UA = dict(_UA)
_NMC_UA["Referer"] = "http://www.nmc.cn/publish/alarm.html"
_NMC_UA["X-Requested-With"] = "XMLHttpRequest"
_NMC_URL = "http://www.nmc.cn/rest/findAlarm"
_NMC_PAGES = 6  # 兜底时多翻几页，200 条会漏掉不少省份

# 预警等级 → 序号（数字越大越紧急）
_LEVEL_MAP = {"蓝色": 1, "黄色": 2, "橙色": 3, "红色": 4}
# 稳定 code：界面按 code 取色，切到繁体/英文后不会因为文字被翻译而失效
_LEVEL_CODE = {"蓝色": "blue", "黄色": "yellow", "橙色": "orange", "红色": "red"}

_DIST_SUFFIXES = ("自治县", "新区", "区", "县", "市", "旗")
# 行政区划后缀：用于判断"发布主体是不是本地的最后一级"
_ADMIN_SUFFIXES = ("自治区", "新区", "自治县", "省", "市", "区", "县", "旗")

_LEVEL_RE = re.compile(r"(蓝色|黄色|橙色|红色)预警")
_TYPE_RE = re.compile(r"发布(.+?)(?:蓝色|黄色|橙色|红色)预警")


def _norm_prov(admin: str) -> str:
    """省名归一：北京市→北京、内蒙古自治区→内蒙古"""
    prov = (admin or "").strip().replace("市", "").replace("省", "").replace("自治区", "")
    for short in ("内蒙古", "广西", "西藏", "宁夏", "新疆"):
        if prov.startswith(short):
            return short
    return prov


def _norm_district(name: str) -> str:
    """区县名归一：东城区→东城、浦东新区→浦东，便于在预警标题里匹配"""
    s = (name or "").strip()
    if not s or s in ("当前位置", "南极洲"):
        return ""
    if s.endswith("新区"):
        return s[:-2]
    for suf in _DIST_SUFFIXES:
        if s.endswith(suf) and len(s) > len(suf):
            return s[:-len(suf)]
    return s


def _norm_area(area: str) -> str:
    return (area or "").strip()


def _is_local_issuer(head: str, locality: str) -> bool:
    """发布主体是否就是本地这一级。

    head='浙江省杭州市建德市'，locality='杭州' → 后面还挂着一级"建德市"，
    属于下面县市的预警，不是杭州市区的，返回 False。
    head='北京市东城区'，locality='东城' → 去掉"区"后无残留，返回 True。
    head='北京市'，locality='北京' → 返回 True（市级/全市性预警）。
    """
    if not head or not locality:
        return False
    i = head.find(locality)
    if i < 0:
        return False
    rest = head[i + len(locality):]
    changed = True
    while changed and rest:
        changed = False
        for suf in _ADMIN_SUFFIXES:
            if rest.startswith(suf):
                rest = rest[len(suf):]
                changed = True
                break
    return rest == ""


def _level_of(title: str) -> str:
    m = _LEVEL_RE.search(title or "")
    return m.group(1) if m else ""


def _type_of(title: str) -> str:
    m = _TYPE_RE.search(title or "")
    return m.group(1) if m else "预警"


def _entry(area: str, title: str, time_str: str) -> dict:
    lv = _level_of(title)
    return {
        "title": title,
        "level": lv,
        "level_code": _LEVEL_CODE.get(lv, ""),
        "type": _type_of(title),
        "time": time_str,
        "area": _norm_area(area),
    }


def _time_from_url(url: str) -> str:
    """从 101010300-20261120192905-1402.html 提取发布时间。"""
    m = re.search(r"-(\d{14})-", url or "")
    if not m:
        return ""
    s = m.group(1)
    return f"{s[0:4]}/{s[4:6]}/{s[6:8]} {s[8:10]}:{s[10:12]}"


def _keep_area(area: str, admin: str, locality: str) -> bool:
    """只保留本地这一级，或本地所属市/省的全市全省性预警。"""
    if not area:
        return False
    prov = _norm_prov(admin)
    if prov and prov not in area:
        return False
    # 1) 发布主体就是本区县 / 本市 / 本省
    if locality and _is_local_issuer(area, locality):
        return True
    # 2) 行政区全名归一后正好等于省/直辖市名：北京市、浙江省等全市全省预警
    if prov and _norm_prov(area) == prov:
        return True
    return False


def _fetch_cn(admin: str, district: str, timeout: float):
    """中国天气网全国列表（主源）。异常时返回 None 交给兜底源。"""
    try:
        r = requests.get(_CN_URL, headers=_UA, timeout=timeout)
        r.raise_for_status()
        text = r.content.decode("utf-8", errors="replace")
        i, j = text.find("{"), text.rfind("}")
        if i < 0 or j <= i:
            return None
        data = json.loads(text[i:j + 1])
    except Exception:
        return None

    locality = _norm_district(district)
    out = []
    for row in (data.get("data") or []):
        if not isinstance(row, list) or len(row) < 7:
            continue
        area, url, title = row[0], row[1], row[6]
        if not _keep_area(area, admin, locality):
            continue
        level = _level_of(title)
        if not level:
            continue
        out.append(_entry(area, title, _time_from_url(url)))
    return out


def _fetch_nmc(admin: str, district: str, timeout: float):
    """中央气象台兜底。标题里的发布主体不如区域全名精确，但胜在稳定。"""
    prov = _norm_prov(admin)
    locality = _norm_district(district)
    all_items = []
    try:
        for page in range(1, _NMC_PAGES + 1):
            r = requests.get(_NMC_URL, params={"pageNo": page, "pageSize": 50},
                             headers=_NMC_UA, timeout=timeout)
            r.raise_for_status()
            lst = (r.json().get("data") or {}).get("page", {}).get("list") or []
            if not lst:
                break
            all_items.extend(lst)
    except Exception:
        return None

    local_items, city_items = [], []
    for it in all_items:
        title = it.get("title", "")
        if not title or _level_of(title) == "":
            continue
        if prov and prov not in title:
            continue
        head = re.match(r"^(.*?)(?:气象台|气象局|发布|继续发布|升级发布|变更发布)",
                        title)
        head = (head.group(1) if head else "").strip()
        entry = _entry(head, title, it.get("issuetime", ""))
        if locality and _is_local_issuer(head, locality):
            local_items.append(entry)
        elif prov and _norm_prov(head) == prov:
            city_items.append(entry)
    return local_items + city_items


def fetch(admin: str = "", district: str = "", timeout: float = 8.0):
    """查询指定省份（并收敛到本地）的当前预警列表。

    返回 dict:
      { "count": int, "max_level": str, "max_type": str,
        "items": [{"title", "level", "type", "time", "area"}] }
    无预警或失败时返回 None。
    """
    admin = (admin or "").strip()
    if not admin:
        return None

    entries = _fetch_cn(admin, district, timeout)
    if entries is None:
        entries = _fetch_nmc(admin, district, timeout)
    if not entries:
        return None

    # 按等级排序；同等级保留原始时间顺序
    entries.sort(key=lambda x: _LEVEL_MAP.get(x.get("level", ""), 0), reverse=True)
    # 去重（同区域 + 同等级 + 同类型），避免主源和兜底叠加时重复计数
    uniq, seen = [], set()
    for e in entries:
        key = (e.get("area", ""), e.get("level", ""), e.get("type", ""))
        if key in seen:
            continue
        seen.add(key)
        uniq.append(e)

    max_item = uniq[0]
    return {
        "count": len(uniq),
        "max_level": max_item["level"],
        "max_level_code": max_item.get("level_code", ""),
        "max_type": max_item["type"],
        "items": uniq[:8],
    }


if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    for q in [("北京市", "朝阳区"), ("北京市", "通州区"), ("浙江省", "杭州市")]:
        r = fetch(q[0], q[1], timeout=10)
        print(q, "->", r and [(i["area"], i["level"], i["type"]) for i in r["items"]])
