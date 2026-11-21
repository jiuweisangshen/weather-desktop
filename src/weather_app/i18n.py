# -*- coding: utf-8 -*-
"""轻量多语言（简体中文 / 繁體中文 / English）。

设计要点：
- 源语言固定为简体中文：代码里写的是原文，词典只维护 zh-TW 与 en 两份译文。
- QML 通过根组件的 tr() 调用本模块；语言切换后由 Python 重建 QML 引擎，
  因此不需要 Qt 的 retranslate 机制，也没有 .qm 编译步骤。
- 后端数据（天气描述、AQI/UV 等级、风向、预警级别与类型、数据源名、状态提示）
  在交给 QML 之前用 localize() 递归翻译；标识类字段（code/id/icon/unit…）跳过。
- 含动态数字的长句统一走 tr + str.format，词典里用 {spread} 这类占位符作键。
"""
import json
import os
import re

ZH_CN = "zh-CN"
ZH_TW = "zh-TW"
EN = "en"
LANGS = (ZH_CN, ZH_TW, EN)

# 设置面板里的语言名称：简体用简体写，繁体用繁体写，英文写 English
LABELS = {ZH_CN: "简体中文", ZH_TW: "繁體中文", EN: "English"}

_current = ZH_CN
_table = {}

# 这些字段是程序内部标识，翻译会破坏逻辑，localize 时原样保留
_SKIP_KEYS = frozenset({
    "code", "codes", "id", "ids", "key", "keys", "icon", "icons", "unit", "units",
    "lang", "language", "locale", "theme", "anim_level", "temp_unit", "backup_source",
    "source", "sources", "tz", "timezone", "fetched_ts", "updated_ts", "ts",
    "url", "link", "path", "file", "name_en", "lat", "lon", "level_code",
})


def dict_path() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "i18n", "strings.json")


def load() -> None:
    """读取词典（缺失或损坏时退化为“不翻译”，不影响程序运行）。"""
    global _table
    try:
        with open(dict_path(), "r", encoding="utf-8") as f:
            data = json.load(f)
        _table = {k: v for k, v in data.items() if isinstance(v, dict)}
    except Exception:
        _table = {}


def normalize(code) -> str:
    c = str(code or "").strip().lower().replace("_", "-")
    if c in ("zh-tw", "zh-hk", "zh-hant", "zh-mo", "tw", "hk", "traditional", "繁体中文", "繁體中文"):
        return ZH_TW
    if c in ("en", "en-us", "en-gb", "english", "英语"):
        return EN
    return ZH_CN


def set_language(code) -> str:
    global _current
    _current = normalize(code)
    return _current


def current_language() -> str:
    return _current


def is_zh_cn() -> bool:
    return _current == ZH_CN


def label(code) -> str:
    return LABELS.get(normalize(code), LABELS[ZH_CN])


def tr(text):
    """把一条简体原文译成当前语言；没有译文时原样返回。"""
    if not isinstance(text, str) or not text or _current == ZH_CN:
        return text
    return _table.get(_current, {}).get(text, text)


def _fmt(tpl, vals):
    try:
        return tpl.format(**vals)
    except Exception:
        return tpl


def _render_note(items):
    """把 [[模板, 参数], ...] 按当前语言拼成一句。"""
    parts = []
    for it in items or []:
        try:
            tpl = it[0]
            args = it[1] if len(it) > 1 else {}
        except Exception:
            continue
        vals = {}
        for k, v in (args or {}).items():
            if isinstance(v, list):
                vals[k] = tr("、").join(tr(str(x)) for x in v)
            else:
                vals[k] = tr(str(v))
        parts.append(_fmt(tr(tpl), vals))
    return tr("；").join(parts)


def _render_method(tpl, parts):
    """加权说明：源名与百分比按当前语言重排。"""
    if not parts:
        return tr(str(tpl))
    text = " / ".join(tr(str(n)) + " " + str(p) for n, p in parts)
    return _fmt(tr(str(tpl)), {"parts": text})


_MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
_DATE_CN = re.compile(r"(\d{1,2})月(\d{1,2})日")


def _date_cn(text):
    """"11月21日" 在英文界面写成 "Nov 21"；繁体同形，保持原样。"""
    if _current != EN or not isinstance(text, str):
        return text
    m = _DATE_CN.match(text)
    if not m:
        return text
    mon = int(m.group(1))
    if not 1 <= mon <= 12:
        return text
    return "%s %d" % (_MONTHS[mon - 1], int(m.group(2)))


def _desc(text):
    """天气描述：后端会把 “夜间” 拼在晴天类描述前（夜间晴），需要拆开分别翻译。"""
    if _current == ZH_CN or not isinstance(text, str):
        return text
    if text.startswith("夜间"):
        rest = tr(text[2:])
        if _current == EN:
            return tr("夜间") + " · " + rest
        return tr("夜间") + rest
    return tr(text)


def localize(obj, _depth=0):
    """递归翻译数据里的可读文本，标识字段与数字保持不变。"""
    if _current == ZH_CN or _depth > 8:
        return obj
    if isinstance(obj, str):
        return tr(obj)
    if isinstance(obj, list):
        return [localize(v, _depth + 1) for v in obj]
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if isinstance(k, str) and k in _SKIP_KEYS:
                out[k] = v
            elif k == "date_cn":
                out[k] = _date_cn(v)
            elif k == "desc":
                out[k] = _desc(v)
            else:
                out[k] = localize(v, _depth + 1)
        # 模板化长句：不管缓存里存的是哪种语言，都按当前语言重新渲染
        if "_note_tpl" in out:
            out["note"] = _render_note(out.pop("_note_tpl"))
        if "_method_tpl" in out:
            tpl = out.pop("_method_tpl")
            out["method"] = _render_method(tpl, out.pop("_method_parts", []))
        return out
    return obj
