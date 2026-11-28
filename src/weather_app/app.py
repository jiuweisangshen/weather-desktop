# -*- coding: utf-8 -*-
"""应用入口：QApplication + QML 引擎 + 后端桥接"""
import json
import os
import sys
import threading
import time

from PySide6.QtCore import QObject, QTimer, Signal, Slot, QUrl
from PySide6.QtGui import QDesktopServices, QImage

from . import config, fetch, i18n
from .cache import Cache

AUTO_REFRESH_MS = 10 * 60 * 1000  # 每 10 分钟自动刷新

# 数据获取失败后的自动重试时刻（秒，相对"首次失败"那一刻计算，不是累加间隔）
# 三次都失败就放弃，等下一次自动刷新（refresh_minutes）
RETRY_DELAYS_S = (5.0, 15.0, 20.0)


class Backend(QObject):
    """QML 侧可调用的后端桥：请求数据 / 自动刷新 / 打开链接"""
    loadingChanged = Signal(bool)
    dataLoaded = Signal(dict)
    errorOccurred = Signal(str)
    languageChanged = Signal(str)
    # 内部信号：QTimer 只能在主线程起停，取数线程里的失败要先交回主线程
    _retryNeeded = Signal(int, str)     # (seq, 错误文案) —— 请求安排下一次重试
    _attemptDone = Signal(int)          # (seq) —— 一次取数尝试结束

    def __init__(self, cfg: dict):
        super().__init__()
        self._cfg = cfg
        self._busy = False
        self._last_query = ""
        self._seq = 0  # 请求序号：新请求覆盖旧请求，旧线程返回后不得再改状态
        refresh_min = cfg.get("refresh_minutes", 10)
        self._timer = QTimer(self)
        self._timer.setInterval(refresh_min * 60 * 1000)
        self._timer.timeout.connect(self._auto_refresh)
        self._timer.start()

        # 兜底看门狗：即使 fetch 内部出现未预期阻塞，也必须在有限时间内结束加载态
        self._watchdog = QTimer(self)
        self._watchdog.setSingleShot(True)
        self._watchdog.timeout.connect(self._on_watchdog)

        # 失败自动重试：5s / 15s / 20s（相对首次失败时刻），用完就等自动刷新
        self._retry_timer = QTimer(self)
        self._retry_timer.setSingleShot(True)
        self._retry_timer.timeout.connect(self._on_retry_timer)
        self._retry_query = None
        self._retry_idx = 0          # 下一次要用 RETRY_DELAYS_S 的第几档；>=3 表示用完
        self._retry_start = 0.0      # 首次失败的时刻（time.monotonic）
        self._retryNeeded.connect(self._on_retry_needed)
        self._attemptDone.connect(self._on_attempt_done)

    def _on_watchdog(self):
        if not self._busy:
            return
        self._seq += 1  # 让仍在运行的旧线程失效
        self._busy = False
        self.loadingChanged.emit(False)
        self.errorOccurred.emit(i18n.tr("请求超时（等待过久），已停止加载。请检查网络后重试。"))

    # ---------- 配置读写 ----------
    def _config_path(self) -> str:
        path = os.path.join(config.base_dir(), "config.json")
        if not os.path.exists(path):
            config.ensure_template_config()
        return path

    def _write_config(self, values: dict) -> bool:
        """原子写回 config.json，避免写到一半断电/被杀进程导致文件损坏。"""
        try:
            path = self._config_path()
            data = {}
            if os.path.exists(path):
                for enc in ("utf-8-sig", "utf-8", "gbk"):
                    try:
                        with open(path, "r", encoding=enc) as f:
                            data = json.load(f) or {}
                        break
                    except UnicodeDecodeError:
                        continue
            if not isinstance(data, dict):
                data = {}
            data.update(values)
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            os.replace(tmp, path)
            return True
        except Exception as e:  # noqa: BLE001
            self.report("write config err: " + str(e))
            return False

    def _auto_refresh(self):
        if self._last_query is not None and not self._busy:
            self.request(self._last_query)

    @Slot(str)
    def request(self, query: str = ""):
        # 允许用户手动搜索覆盖正在进行的请求：旧线程会被序号作废，不再卡住 loading
        self._cfg = config.load_config()  # 每次重读，确保拿到最新的 last_city
        self._last_query = query or ""
        self._timer.start()  # 手动点击刷新后，下次自动刷新从此刻重新计
        self._seq += 1
        seq = self._seq
        self._busy = True
        self._retry_timer.stop()          # 新一轮请求：清掉上一轮还没执行的重试
        self._retry_idx = 0
        self._retry_start = 0.0
        self._retry_query = query or None
        self.loadingChanged.emit(True)
        try:
            timeout_sec = float(self._cfg.get("timeout_sec", 20) or 20)
        except (TypeError, ValueError):
            timeout_sec = 20.0
        timeout_sec = max(5.0, min(60.0, timeout_sec))
        self._watchdog.start(int((timeout_sec + 35) * 1000))
        # 缓存先行：有缓存立即上屏（秒开），过期缓存也先用，后台线程再强制拉新数据覆盖。
        # 但超过 6 小时的旧缓存不再直接上屏，避免换城市/断网时长期显示旧数据与旧预警。
        key = fetch.cache_key(query or "", self._cfg)
        hit = Cache(self._cfg).get(key, allow_stale=True)
        if hit:
            age = time.time() - float(hit.get("_ts") or 0)
            if age > 6 * 3600:
                hit = None
        if hit:
            # 缓存译文放到后台线程：主线程不再为几百条文案做递归翻译，
            # 避免"启动瞬间窗口卡一下"（缓存命中也几乎无感，只是晚几毫秒上屏）。
            def _prewarm():
                try:
                    payload = i18n.localize(hit)
                    if seq == self._seq:
                        self.dataLoaded.emit(payload)
                except Exception:  # noqa: BLE001
                    pass

            threading.Thread(target=_prewarm, daemon=True).start()

        threading.Thread(target=self._work, args=(seq, query or None, False), daemon=True).start()

    # ---------- 取数 + 失败重试 ----------
    def _work(self, seq: int, query, is_retry: bool):
        """取数线程：成功就上屏，失败交回主线程按 5s/15s/20s 重试。"""
        try:
            payload = fetch.fetch_weather(query, self._cfg, use_cache=False)
            if seq != self._seq:
                return
            self._retry_idx = 0
            self._retry_start = 0.0
            self.dataLoaded.emit(i18n.localize(payload))
            self._attemptDone.emit(seq)
            if not is_retry:
                self._busy = False
                self.loadingChanged.emit(False)
        except Exception as e:  # noqa: BLE001
            if seq != self._seq:
                return
            self._retryNeeded.emit(seq, str(e))

    def _on_attempt_done(self, seq: int):
        """主线程收尾：停看门狗（QTimer 不能在工作线程里 stop）。"""
        self._watchdog.stop()

    def _on_retry_needed(self, seq: int, msg: str):
        """数据获取失败 → 按 5s / 15s / 20s 再试；三次用完才报错并等自动刷新。"""
        if seq != self._seq:
            return
        self._watchdog.stop()  # 等待重试期间不占用看门狗，重试真正开始时再起
        if self._retry_start <= 0.0:
            self._retry_start = time.monotonic()
        if self._retry_idx >= len(RETRY_DELAYS_S):
            # 三次重试都失败：结束加载态、报一次错，然后只等 refresh_minutes 后的自动刷新
            self._retry_idx = 0
            self._retry_start = 0.0
            self._busy = False
            self.loadingChanged.emit(False)
            self.errorOccurred.emit(
                i18n.tr(msg) + " · " + i18n.tr("已自动重试 3 次仍失败，将在下次自动刷新时重试")
            )
            return
        target = self._retry_start + RETRY_DELAYS_S[self._retry_idx]
        self._retry_idx += 1
        remain = target - time.monotonic()
        self._retry_timer.start(max(150, int(remain * 1000)))

    def _on_retry_timer(self):
        """到点：起一次后台重试（不打扰界面，成功就用 dataLoaded 直接上屏）。"""
        if self._retry_idx <= 0:
            return
        try:
            timeout_sec = float(self._cfg.get("timeout_sec", 20) or 20)
        except (TypeError, ValueError):
            timeout_sec = 20.0
        timeout_sec = max(5.0, min(60.0, timeout_sec))
        self._watchdog.start(int((timeout_sec + 35) * 1000))
        threading.Thread(target=self._work, args=(self._seq, self._retry_query, True), daemon=True).start()

    @Slot(str, result=str)
    def suggest(self, text: str):
        """搜索候选：本地区县/常用城市/国外别名前缀匹配（同步返回 JSON）"""
        try:
            from weather_app import geo
            return json.dumps(geo.suggest_candidates(text), ensure_ascii=False)
        except Exception as e:  # noqa: BLE001
            self.report("suggest err: " + str(e))
            return "[]"

    @Slot(str)
    def openLink(self, url: str):
        QDesktopServices.openUrl(QUrl(url))

    # ---------- 多语言 ----------
    @Slot(str, result=str)
    def translate(self, text: str) -> str:
        """QML 侧的 tr(...)：把简体原文译成当前语言。"""
        return i18n.tr(text)

    @Slot(result=str)
    def currentLanguage(self) -> str:
        return i18n.current_language()

    @Slot(str)
    def applyLanguage(self, lang: str):
        """切换界面语言：写盘 → 切词典 → 通知外层重建界面。"""
        code = i18n.normalize(lang)
        if not self._write_config({"language": code}):
            return
        i18n.set_language(code)
        self._cfg = config.load_config()
        self.languageChanged.emit(code)

    @Slot(str)
    def saveTheme(self, theme: str):
        """持久化深浅色主题（dark/light）到 config.json"""
        self._write_config({"theme": theme if theme in ("dark", "light") else "dark"})

    @Slot(int)
    def setRefreshInterval(self, minutes: int):
        """设置天气数据自动刷新间隔（分钟），并立即重启定时器"""
        v = max(1, int(minutes))
        if self._write_config({"refresh_minutes": v}):
            self._timer.setInterval(v * 60 * 1000)
            self._timer.start()

    @Slot(int)
    def setAlarmInterval(self, minutes: int):
        """设置预警更新间隔（分钟）"""
        self._write_config({"alarm_minutes": max(5, int(minutes))})

    @Slot(int)
    def setTimeoutSec(self, seconds: int):
        """设置网络连接超时（秒）"""
        self._write_config({"timeout_sec": max(5, int(seconds))})

    @Slot(str)
    def setTempUnit(self, unit: str):
        """设置温度单位（C/F）"""
        self._write_config({"temp_unit": unit if unit in ("C", "F") else "C"})

    @Slot(str)
    def setAnimLevel(self, level: str):
        """设置动画效果强度（full/simple/off）"""
        self._write_config({"anim_level": level if level in ("full", "simple", "off") else "full"})

    @Slot(str)
    def setBackupSource(self, source: str):
        """设置连接失败后的备用数据源（auto/wttr/chinacom）"""
        self._write_config({"backup_source": source if source in ("auto", "wttr", "chinacom") else "auto"})

    @Slot(float)
    def setHoverBrightness(self, brightness: float):
        """设置鼠标跟随亮度（0.0 ~ 2.0）"""
        self._write_config({"hover_brightness": max(0.0, min(2.0, float(brightness)))})

    @Slot(str, result=bool)
    def saveSettings(self, payload: str) -> bool:
        """一次性保存设置面板的全部草稿值（点击“保存配置”后才调用）。"""
        try:
            s = json.loads(payload)
            if not isinstance(s, dict):
                return False

            def _int(key, default, lo, hi):
                try:
                    v = int(s.get(key, default))
                except (TypeError, ValueError):
                    v = default
                return max(lo, min(hi, v))

            def _float(key, default, lo, hi):
                try:
                    v = float(s.get(key, default))
                except (TypeError, ValueError):
                    v = default
                return max(lo, min(hi, v))

            values = {
                "refresh_minutes": _int("refresh_minutes", 10, 1, 720),
                "alarm_minutes": _int("alarm_minutes", 30, 5, 720),
                "timeout_sec": _int("timeout_sec", 20, 5, 60),
                "temp_unit": s.get("temp_unit") if s.get("temp_unit") in ("C", "F") else "C",
                "anim_level": s.get("anim_level") if s.get("anim_level") in ("full", "simple", "off") else "full",
                "backup_source": s.get("backup_source") if s.get("backup_source") in ("auto", "wttr", "chinacom") else "auto",
                "hover_brightness": round(_float("hover_brightness", 1.0, 0.0, 2.0), 3),
                "glass_float": bool(s.get("glass_float", True)),
                "mouse_follow": bool(s.get("mouse_follow", True)),
                "theme": s.get("theme") if s.get("theme") in ("dark", "light") else "dark",
                "language": i18n.normalize(s.get("language")),
            }
            if not self._write_config(values):
                return False
            self._cfg = config.load_config()
            self._timer.setInterval(values["refresh_minutes"] * 60 * 1000)
            self._timer.start()
            return True
        except Exception as e:  # noqa: BLE001
            self.report("saveSettings err: " + str(e))
            return False

    @Slot(str, result=bool)
    def saveGlassLayout(self, layout_json: str) -> bool:
        """保存玻璃卡片拖动偏移 {layoutKey: [dx, dy]}。"""
        try:
            raw = json.loads(layout_json or "{}")
            clean = {}
            if isinstance(raw, dict):
                for k, v in list(raw.items())[:24]:
                    if not isinstance(k, str) or not k:
                        continue
                    if not isinstance(v, (list, tuple)) or len(v) != 2:
                        continue
                    try:
                        dx = round(max(-2000.0, min(2000.0, float(v[0]))), 1)
                        dy = round(max(-2000.0, min(2000.0, float(v[1]))), 1)
                    except (TypeError, ValueError):
                        continue
                    clean[k[:32]] = [dx, dy]
            return self._write_config({"glass_layout": clean})
        except Exception as e:  # noqa: BLE001
            self.report("saveGlassLayout err: " + str(e))
            return False

    @Slot(result=str)
    def getSettings(self):
        """返回当前设置 JSON"""
        try:
            path = os.path.join(config.base_dir(), "config.json")
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return json.dumps({
                "refresh_minutes": data.get("refresh_minutes", 10),
                "alarm_minutes": data.get("alarm_minutes", 30),
                "timeout_sec": data.get("timeout_sec", 20),
                "temp_unit": data.get("temp_unit", "C"),
                "anim_level": data.get("anim_level", "full"),
                "backup_source": data.get("backup_source", "auto"),
                "hover_brightness": data.get("hover_brightness", 1.0),
                "glass_float": data.get("glass_float", True),
                "mouse_follow": data.get("mouse_follow", True),
                "glass_layout": data.get("glass_layout", {}),
                "theme": data.get("theme", "dark"),
                "language": i18n.normalize(data.get("language")),
            }, ensure_ascii=False)
        except Exception:
            return json.dumps({
                "refresh_minutes": 10, "alarm_minutes": 30,
                "timeout_sec": 20, "temp_unit": "C", "anim_level": "full",
                "backup_source": "auto", "hover_brightness": 1.0,
                "glass_float": True, "mouse_follow": True,
                "glass_layout": {}, "theme": "dark", "language": "zh-CN"
            })

    @Slot(str)
    def report(self, s: str):
        """QML 侧调试回传（开发用）"""
        print("QML-REPORT:", s)

    @Slot(QImage, str)
    def saveImage(self, img: QImage, path: str):
        img.save(path)
        print("saved:", path)
