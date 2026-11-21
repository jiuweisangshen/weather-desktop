# -*- coding: utf-8 -*-
"""取数编排：解析位置 → 并行拉取多源 → 聚合 → 缓存

所有网络请求都带超时；整批取数另设硬截止时间。某个数据源卡住时使用已返回
的数据继续聚合，避免界面一直转圈。后台线程全部为 daemon，不会在退出时等待
挂起的网络请求。
"""
import threading
import time

from . import aggregate, config as _cfg, geo, i18n
from .cache import Cache
from .sources import chinacom, open_meteo, qweather, wttrin, alarm_nmc


class FetchError(RuntimeError):
    pass


_DEFAULT_TIMEOUT = 20.0
# 自动定位失败/超时后的离线兜底（不依赖网络，避免定位阶段再次长时间等待）
_BEIJING_FALLBACK = {
    "name": "北京", "admin": "北京市", "country": "中国",
    "country_code": "CN", "lat": 39.9042, "lon": 116.4074,
    "timezone": "Asia/Shanghai", "via": "fallback",
}


def _timeout_sec(cfg: dict) -> float:
    try:
        t = float(cfg.get("timeout_sec", _DEFAULT_TIMEOUT) or _DEFAULT_TIMEOUT)
    except (TypeError, ValueError):
        t = _DEFAULT_TIMEOUT
    return max(5.0, min(60.0, t))


def _resolve_location(query: str, cfg: dict, timeout_sec: float) -> dict:
    """定位也放到 daemon 线程里限时等待；自动定位超时后走离线兜底。"""
    last_city = cfg.get("last_city", "")

    if query and query.strip():
        box, err = {}, {}

        def run_query():
            try:
                box["loc"] = geo.resolve(query, cfg.get("default_city", ""),
                                         timeout=min(timeout_sec, 20),
                                         last_city=last_city)
            except Exception as e:  # noqa: BLE001
                err["err"] = e

        th = threading.Thread(target=run_query, name="wx-geo", daemon=True)
        th.start()
        th.join(max(6.0, min(25.0, timeout_sec)))
        if box.get("loc"):
            return box["loc"]
        if "err" in err:
            raise err["err"]
        raise FetchError(i18n.tr("城市定位超时（{city}），请检查网络后重试").format(city=query))

    # 上次选择的区县：先用本地库离线命中，不再等网络地理编码。
    # 否则断网/接口超时后会自动退回系统定位，"上次选择"看起来就失效了。
    if last_city and str(last_city).strip() and not (cfg.get("default_city") or "").strip():
        local = geo.local_lookup(str(last_city).strip())
        if local:
            local.update(auto=True, loc_source="remembered")
            return local

    box, err = {}, {}

    def run_auto():
        try:
            box["loc"] = geo.resolve(None, cfg.get("default_city", ""),
                                     timeout=min(timeout_sec, 10),
                                     last_city=last_city)
        except Exception as e:  # noqa: BLE001
            err["err"] = e

    th = threading.Thread(target=run_auto, name="wx-geo", daemon=True)
    th.start()
    th.join(max(5.0, min(10.0, timeout_sec)))
    if box.get("loc"):
        return box["loc"]

    # 超时/失败：优先用配置里记住的区县做离线解析，最后才用北京
    for name in (last_city, cfg.get("default_city", "")):
        if name and str(name).strip():
            local = geo.local_lookup(str(name))
            if local:
                local.update(auto=True, loc_source="fallback")
                return local
    return dict(_BEIJING_FALLBACK, auto=True, loc_source="fallback")


def cache_key(query: str, cfg: dict) -> str:
    """缓存键：显式搜索按关键词；自动定位按"上次城市"分开存，
    避免换城市后仍命中上一个城市的 @auto 缓存（旧数据/旧预警串台）。"""
    q = (query or "").strip()
    if q:
        return q.lower()
    remember = (cfg.get("last_city") or "").strip()
    return ("@auto:" + remember).lower() if remember else "@auto"


def fetch_weather(query: str = None, cfg: dict = None, use_cache: bool = True) -> dict:
    cfg = cfg or _cfg.load_config()
    key = cache_key(query or "", cfg)
    cache = Cache(cfg)

    if use_cache:
        hit = cache.get(key)
        if hit:
            return hit

    started = time.monotonic()
    timeout_sec = _timeout_sec(cfg)

    try:
        loc = _resolve_location(query, cfg, timeout_sec)
    except Exception:  # noqa: BLE001  定位失败不得阻塞首屏
        # 用户显式输入了城市但解析失败：如实报错，避免静默显示北京
        if query and query.strip():
            raise FetchError(i18n.tr("未找到城市「{q}」。请检查名称，或输入「城市,国家」/「纬度,经度」。").format(q=query))
        # 自动定位失败：优先用配置里记住的区县做离线解析，最后才用北京
        for name in (cfg.get("last_city"), cfg.get("default_city")):
            if name and str(name).strip():
                local = geo.local_lookup(str(name))
                if local:
                    local.update(auto=True, loc_source="fallback")
                    loc = local
                    break
        else:
            loc = dict(_BEIJING_FALLBACK, auto=True, loc_source="fallback")

    res = {"main": None, "uv": None, "aq": None, "gfs": None, "ecmwf": None,
           "wttr": None, "qw": None, "cc": None, "alarm": None}

    # 极地（|lat|>75°）无 wttr.in/中国天气网站点：跳过，避免拉到错误数据
    is_polar = abs(loc["lat"]) > 75
    # 国内城市才用中国天气网（官方国标 AQI + 实况）；国外一律走 Open-Meteo
    is_cn = (loc.get("country") or "").strip() in ("中国", "China")

    def _run(slot, fn):
        try:
            res[slot] = fn()
        except Exception:
            res[slot] = None

    threads = []

    def start(slot, fn):
        th = threading.Thread(target=_run, args=(slot, fn),
                              name=f"wx-{slot}", daemon=True)
        th.start()
        threads.append((slot, th))
        return th

    start("main", lambda: open_meteo.forecast(
        loc["lat"], loc["lon"], loc.get("timezone"), timeout=timeout_sec))
    start("uv", lambda: open_meteo.forecast_uv(
        loc["lat"], loc["lon"], loc.get("timezone"), timeout=timeout_sec))
    start("aq", lambda: open_meteo.air_quality(
        loc["lat"], loc["lon"], loc.get("timezone"), timeout=timeout_sec))
    start("gfs", lambda: open_meteo.model_temp(
        loc["lat"], loc["lon"], loc.get("timezone"), "gfs_seamless", timeout=timeout_sec))
    start("ecmwf", lambda: open_meteo.model_temp(
        loc["lat"], loc["lon"], loc.get("timezone"), "ecmwf_ifs025", timeout=timeout_sec))
    if not is_polar:
        start("wttr", lambda: wttrin.fetch(
            loc["lat"], loc["lon"], timeout=min(timeout_sec, 15)))
    if not is_polar and is_cn:
        start("cc", lambda: chinacom.fetch(
            loc.get("name", ""), loc.get("admin", ""), timeout=min(timeout_sec, 10)))
        alarm_thread = start("alarm", lambda: alarm_nmc.fetch(
            loc.get("admin", ""), loc.get("name", ""), timeout=min(timeout_sec, 5)))
    else:
        alarm_thread = None
    if cfg.get("qweather_key"):
        start("qw", lambda: qweather.fetch_all(
            f"{loc['lon']:.2f},{loc['lat']:.2f}", cfg["qweather_key"],
            timeout=timeout_sec))

    # 核心数据源硬截止：最多等 20 秒（受用户设置约束）。预警横幅不阻塞首屏，
    # 核心源结束后最多再给它 1.2 秒。
    deadline = time.monotonic() + max(8.0, min(timeout_sec, 20.0))
    for slot, th in threads:
        if slot == "alarm":
            continue
        left = deadline - time.monotonic()
        if left <= 0:
            break
        th.join(left)
    if alarm_thread is not None:
        alarm_thread.join(1.8)

    timed_out = [slot for slot, th in threads if th.is_alive()]

    # 备用源降级策略：Open-Meteo 主接口失败时，自动切换到备用源
    backup_source = cfg.get("backup_source", "auto")  # auto / wttr / chinacom
    main_failed = res["main"] is None
    fallback_used = None

    if main_failed:
        # 按优先级选择备用源
        if backup_source == "wttr" and res["wttr"] is not None:
            fallback_used = "wttr"
        elif backup_source == "chinacom" and res["cc"] is not None:
            fallback_used = "chinacom"
        elif backup_source == "auto":
            # 自动选择：国内优先中国天气网，国外优先 wttr.in
            if is_cn and res["cc"] is not None:
                fallback_used = "chinacom"
            elif res["wttr"] is not None:
                fallback_used = "wttr"
            elif res["cc"] is not None:
                fallback_used = "chinacom"

    if res["main"] is None and fallback_used is None:
        if timed_out:
            waited = time.monotonic() - started
            raise FetchError(
                i18n.tr("数据源连接超时（已等待 {sec} 秒：{srcs}），请检查网络或稍后重试")
                .format(sec=f"{waited:.0f}", srcs=", ".join(timed_out)))
        raise FetchError(i18n.tr("主数据源（Open-Meteo）及所有备用源均请求失败，请检查网络后重试"))

    payload = aggregate.build(loc, res, cfg, fallback_used=fallback_used,
                              timed_out=timed_out)
    cache.set(key, payload)

    # 同时按解析后的城市另存一份自动定位缓存：手动搜索后，下次启动
    # last_city 会变成该城市，用 @auto:<城市> 命中这份新缓存，不会读到旧城市。
    try:
        cache_name = (loc.get("name") or "").strip()
        if cache_name and cache_name not in ("当前位置", "南极洲"):
            cache.set("@auto:" + cache_name.lower(), payload)
            cache.remove("@auto")
    except Exception:  # noqa: BLE001
        pass

    # 自动定位成功后记住结果：下次启动直接按区县解析，跳过系统定位等待
    # （首次调用 Windows 定位可能需要数秒，缓存命中后启动可控制在 1 秒内）
    if not (query and query.strip()) and not (cfg.get("last_city") or "").strip():
        try:
            name = (loc.get("name") or "").strip()
            if name:
                _cfg.save_setting("last_city", name)
        except Exception:  # noqa: BLE001
            pass

    # 记住用户本次手动选择的城市：下次启动直接采用，不必再在搜索框输入
    # 只写原始 query 不够：搜索"朝阳"时解析结果是"朝阳区"，写回区县全名
    # 下次启动直接用区县解析，避免模糊名再次落到别的行政区
    if query and query.strip():
        try:
            name = (loc.get("name") or "").strip() or query.strip()
            _cfg.save_setting("last_city", name)
            cache.remove("@auto")
        except Exception:
            pass
    return payload
