# -*- coding: utf-8 -*-
"""应用配置：路径、权重、用户可编辑的 config.json"""
import os
import sys
import json

APP_NAME = "天气"
APP_TITLE = "天气 · 多源天气分析"
APP_VERSION = "1.0.0"

# 各数据源对"当前温度"的加权（缺失源会重新归一化）
# 实测结论：地面实测源（中国天气网/wttr.in/和风）彼此差 <0.5°C 更可靠；
# 模式源（GFS/ECMWF）更分散，进一步降权；另有离群剔除兜底。
DEFAULT_WEIGHTS = {
    "open-meteo": 0.28,   # best_match（多模型择优混合）
    "chinacom": 0.24,     # 中国天气网（官方实测，仅大陆城市）
    "wttr.in": 0.22,      # wttr.in（WorldWeatherOnline 派生）
    "qweather": 0.12,     # 和风天气（需自行申请免费 Key，可选）
    "gfs": 0.07,          # GFS 无缝模式（模式源，已降权）
    "ecmwf": 0.07,        # ECMWF IFS 0.25（模式源，已降权）
}

CONFIG_TEMPLATE = {
    "qweather_key": "",       # 和风天气免费 Key（可选）：https://dev.qweather.com 注册
    "default_city": "",       # 留空则自动定位（系统定位/上次城市/IP）；填写如 "北京"
    "last_city": "",          # 上次手动搜索的城市，自动写入，下次启动直接采用
    "cache_minutes": 10,      # 本地缓存时长（分钟），与 10 分钟自动刷新对齐
    "theme": "dark",          # 界面主题：dark（深色）/ light（浅色）
    "refresh_minutes": 10,    # 天气自动刷新间隔（分钟）
    "alarm_minutes": 30,      # 预警刷新间隔（分钟，预留）
    "timeout_sec": 20,        # 单个网络请求超时（秒）
    "temp_unit": "C",         # 温度单位：C / F
    "anim_level": "full",     # 动画效果：full / simple / off
    "backup_source": "auto",  # 备用数据源：auto / wttr / chinacom
    "hover_brightness": 1.0,  # 鼠标跟随亮度：0.0 ~ 2.0（无极调节）
    "glass_float": True,      # 玻璃悬浮缩放开关
    "mouse_follow": True,     # 鼠标跟随高光开关
    "language": "zh-CN",      # 界面语言：zh-CN / zh-TW / en
    "glass_layout": {},       # 玻璃卡片拖动位置 {key: [dx, dy]}
    "weights": DEFAULT_WEIGHTS,
}

_BASE_DIR_CACHE = None


def _writable_dir(d: str) -> bool:
    try:
        probe = os.path.join(d, ".write_probe")
        with open(probe, "w", encoding="utf-8") as f:
            f.write("ok")
        os.remove(probe)
        return True
    except Exception:
        return False


def _read_json(path: str):
    """读取配置：兼容记事本另存为 GBK/带 BOM 的情况，避免整份配置静默失效。"""
    for enc in ("utf-8-sig", "utf-8", "gbk"):
        try:
            with open(path, "r", encoding=enc) as f:
                return json.load(f)
        except UnicodeDecodeError:
            continue
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return json.load(f)


def is_frozen() -> bool:
    return getattr(sys, "frozen", False)


def base_dir() -> str:
    """程序数据目录：打包后优先用 EXE 所在目录；若该目录不可写（例如安装到
    Program Files），自动回退到 %APPDATA%\\天气，保证设置/上次城市/缓存能落盘。"""
    global _BASE_DIR_CACHE
    if is_frozen():
        if _BASE_DIR_CACHE:
            return _BASE_DIR_CACHE
        d = os.path.dirname(os.path.abspath(sys.executable))
        if not _writable_dir(d):
            user = os.environ.get("APPDATA") or os.path.expanduser("~")
            d = os.path.join(user, APP_NAME)
            try:
                os.makedirs(d, exist_ok=True)
            except Exception:
                pass
        _BASE_DIR_CACHE = d
        return d
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def resource_dir() -> str:
    """内置资源根目录：打包后为 PyInstaller 解包目录；开发时为仓库根"""
    if is_frozen():
        return getattr(sys, "_MEIPASS", base_dir())
    return base_dir()


def ui_dir() -> str:
    if is_frozen():
        return os.path.join(resource_dir(), "weather_app", "ui")
    return os.path.join(resource_dir(), "src", "weather_app", "ui")


def assets_dir() -> str:
    return os.path.join(resource_dir(), "assets")


def cache_dir() -> str:
    d = os.path.join(base_dir(), ".cache")
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        pass
    return d


def load_config() -> dict:
    cfg = json.loads(json.dumps(CONFIG_TEMPLATE))
    path = os.path.join(base_dir(), "config.json")
    if os.path.exists(path):
        try:
            user = _read_json(path)
            # 读取用户保存的全部键（不只是模板中的键），否则设置面板保存的
            # theme / refresh_minutes / timeout_sec / temp_unit 等会在重启后被忽略。
            for k, v in user.items():
                if v is None:
                    continue
                if k == "weights" and isinstance(v, dict):
                    merged = dict(cfg.get("weights") or {})
                    merged.update(v)
                    cfg["weights"] = merged
                else:
                    cfg[k] = v
        except Exception:
            pass
    return cfg


def ensure_template_config() -> str:
    """首次运行生成 config.json 模板，返回路径"""
    path = os.path.join(base_dir(), "config.json")
    if not os.path.exists(path):
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(CONFIG_TEMPLATE, f, ensure_ascii=False, indent=2)
        except Exception:
            pass
    return path


def save_setting(key: str, value) -> bool:
    """把单个键写回 config.json（不存在则先建模板），失败返回 False"""
    try:
        path = os.path.join(base_dir(), "config.json")
        if not os.path.exists(path):
            ensure_template_config()
        data = {}
        if os.path.exists(path):
            data = _read_json(path) or {}
        data[key] = value
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
        return True
    except Exception:
        return False
