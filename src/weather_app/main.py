# -*- coding: utf-8 -*-
"""天气 · 主程序入口
用法（开发）:  .venv\\Scripts\\python.exe src\\weather_app\\main.py
用法（验证）:  ... main.py --screenshot <out.png> [--city 北京]   （配合 QT_QPA_PLATFORM=offscreen）
"""
import json
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_src = os.path.dirname(_here)
if _src not in sys.path:
    sys.path.insert(0, _src)

from PySide6.QtCore import Q_ARG, QCoreApplication, QMetaObject, QObject, QTimer, Qt, QUrl  # noqa: E402
from PySide6.QtGui import QFont, QGuiApplication, QIcon  # noqa: E402
from PySide6.QtNetwork import QLocalServer, QLocalSocket  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402

from weather_app import config, i18n  # noqa: E402
from weather_app.app import Backend  # noqa: E402


def _single_instance_name() -> str:
    """当前用户独占的命名管道名（ASCII，避免中文管道名问题）。"""
    import hashlib
    u = (os.environ.get("USERNAME") or "user").lower()
    return "weather-app-single-" + hashlib.md5(u.encode("utf-8")).hexdigest()[:10]


def _win32_find_window(hint: str) -> int:
    """按标题关键字找可见顶层窗口（回传句柄失败时的兜底）。"""
    try:
        import ctypes
        from ctypes import wintypes
        u32 = ctypes.windll.user32
        found = []
        proc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

        def cb(h, _l):
            if u32.IsWindowVisible(h):
                n = u32.GetWindowTextLengthW(h)
                if n > 0:
                    buf = ctypes.create_unicode_buffer(n + 1)
                    u32.GetWindowTextW(h, buf, n + 1)
                    if hint in buf.value:
                        found.append(int(h))
                        return False
            return True

        u32.EnumWindows(proc(cb), 0)
        return found[0] if found else 0
    except Exception:  # noqa: BLE001
        return 0


def _win32_foreground(hwnd: int) -> None:
    """把指定窗口恢复并置前。调用方应是刚被用户点击启动的进程（持有前台权限），
    否则 Windows 会拒绝 SetForegroundWindow。"""
    try:
        import ctypes
        from ctypes import wintypes
        u32 = ctypes.windll.user32
        h = wintypes.HWND(hwnd)
        if u32.IsIconic(h):
            u32.ShowWindow(h, 9)  # SW_RESTORE
        else:
            u32.ShowWindow(h, 5)  # SW_SHOW
        if u32.GetForegroundWindow() == h:
            return
        u32.SetForegroundWindow(h)
        if u32.GetForegroundWindow() == h:
            return
        # 前台锁仍拒绝时，临时附加到当前前台线程的输入队列再抢一次
        fg = u32.GetForegroundWindow()
        fpid = wintypes.DWORD()
        t_fg = u32.GetWindowThreadProcessId(fg, ctypes.byref(fpid))
        oid = wintypes.DWORD()
        t_own = u32.GetWindowThreadProcessId(h, ctypes.byref(oid))
        if t_fg and t_own:
            u32.AttachThreadInput(t_fg, t_own, True)
            u32.SetForegroundWindow(h)
            u32.AttachThreadInput(t_fg, t_own, False)
        if u32.GetForegroundWindow() == h:
            return
        try:
            u32.SwitchToThisWindow(h, True)
        except Exception:  # noqa: BLE001
            pass
    except Exception:  # noqa: BLE001
        pass


def _raise_existing_instance(name: str) -> bool:
    """已有实例在跑就通知它前置窗口，返回 True（本次启动应立即退出）。
    已存在实例会把自身窗口句柄回传，由本进程（持有前台权限）完成置前。"""
    sock = QLocalSocket()
    sock.connectToServer(name)
    ok = sock.waitForConnected(3000)
    if os.environ.get("WEATHER_SINGLE_DEBUG"):
        print(f"[single] connect name={name} ok={ok} err={sock.errorString()}", flush=True)
    if not ok:
        sock.abort()
        return False
    hwnd = 0
    try:
        sock.write(b"raise")
        sock.flush()
        sock.waitForBytesWritten(1500)
        if sock.waitForReadyRead(2500):
            raw = bytes(sock.readAll().data()).decode("ascii", "ignore").strip()
            hwnd = int(raw) if raw.isdigit() else 0
    except Exception:  # noqa: BLE001
        hwnd = 0
    finally:
        sock.abort()
    if os.environ.get("WEATHER_SINGLE_DEBUG"):
        print(f"[single] existing hwnd={hwnd}", flush=True)
    if sys.platform == "win32":
        target = hwnd
        if target <= 0:
            target = _win32_find_window(config.APP_TITLE or "天气")
            if os.environ.get("WEATHER_SINGLE_DEBUG"):
                print(f"[single] fallback find window={target}", flush=True)
        if target > 0:
            _win32_foreground(target)
    return True


def _activate_window(win) -> None:
    """本进程内恢复窗口（最小化 → 还原）；置前由新实例完成，见 _win32_foreground。"""
    if sys.platform == "win32":
        try:
            import ctypes
            hwnd = int(win.winId())
            if hwnd and ctypes.windll.user32.IsIconic(hwnd):
                ctypes.windll.user32.ShowWindow(hwnd, 9)  # SW_RESTORE
            return
        except Exception:  # noqa: BLE001
            pass
    try:
        if win.windowState() & Qt.WindowState.WindowMinimized:
            win.setWindowState(Qt.WindowState.WindowNoState)
        win.show()
        win.raise_()
    except Exception:  # noqa: BLE001
        pass


def _serve_single_instance(app, name: str, holder: dict):
    """注册命名管道监听；返回 None 表示已被别的实例抢先（本次应退出）。
    holder 里保存当前窗口引用——界面重建（切换语言）后窗口对象会换新，监听回调要跟着走。"""
    QLocalServer.removeServer(name)  # 清理上次异常退出残留的管道
    srv = QLocalServer(app)

    def _on_connection():
        win = holder.get("win")
        while srv.hasPendingConnections():
            conn = srv.nextPendingConnection()
            if conn is None:
                break
            try:
                conn.waitForReadyRead(500)
                conn.readAll()
                # 回传窗口句柄：新实例有前台权限，由它完成置前
                hwnd = 0
                try:
                    hwnd = int(win.winId()) if win is not None else 0
                except Exception:  # noqa: BLE001
                    hwnd = 0
                conn.write(str(hwnd).encode("ascii"))
                conn.flush()
                conn.waitForBytesWritten(800)
                conn.disconnectFromServer()
                conn.deleteLater()
            except Exception:  # noqa: BLE001
                pass
        if os.environ.get("WEATHER_SINGLE_DEBUG"):
            print("[single] got raise request -> activate window", flush=True)
        if win is not None:
            _activate_window(win)

    srv.newConnection.connect(_on_connection)
    ok = srv.listen(name)
    if os.environ.get("WEATHER_SINGLE_DEBUG"):
        print(f"[single] listen name={name} ok={ok} full={srv.fullServerName()} err={srv.errorString()}",
              flush=True)
    if not ok:
        return None
    return srv



def _args():
    argv = sys.argv
    out, city = None, ""
    if "--screenshot" in argv:
        i = argv.index("--screenshot")
        if i + 1 < len(argv):
            out = argv[i + 1]
    if "--city" in argv:
        j = argv.index("--city")
        if j + 1 < len(argv):
            city = argv[j + 1]
    return out, city


def _ensure_fonts(app) -> None:
    """显式加载系统 CJK 字体，避免字体数据库为空时中文渲染成豆腐块。
    同时加载 Light 字重（msyhl.ttc）：大温度用了 Font.Light，缺这个字重时
    Qt 会回退到别的字体面，极端情况下会取到错误的字形（表现为"Â°"之类乱码）。"""
    from PySide6.QtGui import QFontDatabase

    for p in (r"C:\Windows\Fonts\msyh.ttc",
              r"C:\Windows\Fonts\msyhbd.ttc",
              r"C:\Windows\Fonts\msyhl.ttc"):
        if os.path.exists(p):
            QFontDatabase.addApplicationFont(p)
    f = QFont("Microsoft YaHei UI", 10)
    f.setStyleStrategy(QFont.PreferAntialias)
    app.setFont(f)


def _fix_win32_window(win) -> None:
    """无边框窗口补原生样式（Windows）：
    WS_MINIMIZEBOX/WS_MAXIMIZEBOX —— 任务栏点击可恢复/切换最小化；
    WS_EX_APPWINDOW —— 任务栏按钮稳定存在、点击可前置/后置。
    仅在真实窗口（非 offscreen 截图）下执行。"""
    if sys.platform != "win32" or os.environ.get("QT_QPA_PLATFORM") == "offscreen":
        return
    try:
        import ctypes

        u32 = ctypes.windll.user32
        GWL_STYLE, GWL_EXSTYLE = -16, -20
        WS_MINIMIZEBOX, WS_MAXIMIZEBOX = 0x20000, 0x10000
        WS_EX_APPWINDOW = 0x40000
        SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER, SWP_FRAMECHANGED = 0x2, 0x1, 0x4, 0x20
        hwnd = int(win.winId())
        style = u32.GetWindowLongW(hwnd, GWL_STYLE) | WS_MINIMIZEBOX | WS_MAXIMIZEBOX
        u32.SetWindowLongW(hwnd, GWL_STYLE, style)
        ex = u32.GetWindowLongW(hwnd, GWL_EXSTYLE) | WS_EX_APPWINDOW
        u32.SetWindowLongW(hwnd, GWL_EXSTYLE, ex)
        u32.SetWindowPos(hwnd, 0, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED)
    except Exception:  # noqa: BLE001
        pass


def _build_ui(backend, cfg: dict):
    """创建 QML 引擎并加载主界面，返回 (engine, rootWindow)。"""
    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("backend", backend)
    ctx.setContextProperty("res", config.assets_dir())
    ctx.setContextProperty("appTitle", i18n.tr(config.APP_TITLE))
    ctx.setContextProperty("initialTheme", cfg.get("theme", "dark"))
    ctx.setContextProperty("initialTempUnit", cfg.get("temp_unit", "C"))
    ctx.setContextProperty("initialAnimLevel", cfg.get("anim_level", "full"))
    ctx.setContextProperty("initialHoverBrightness", cfg.get("hover_brightness", 1.0))
    ctx.setContextProperty("initialGlassFloat", bool(cfg.get("glass_float", True)))
    ctx.setContextProperty("initialMouseFollow", bool(cfg.get("mouse_follow", True)))
    ctx.setContextProperty(
        "initialGlassLayout", json.dumps(cfg.get("glass_layout") or {}, ensure_ascii=False))

    ui = os.path.join(config.ui_dir(), "main.qml")
    engine.load(QUrl.fromLocalFile(ui))
    roots = engine.rootObjects()
    return engine, (roots[0] if roots else None)


def _install_language_switch(backend, holder: dict, icon_path: str) -> None:
    """语言变更后重建界面：比逐条 retranslate 更彻底，也不会残留旧绑定。"""
    def _rebuild(_code):
        def _do():
            old = holder.get("win")
            maxed = True
            try:
                maxed = bool(old.windowState() & Qt.WindowState.WindowMaximized) if old else True
            except Exception:  # noqa: BLE001
                maxed = True
            try:
                if old is not None:
                    old.close()
                    old.deleteLater()
            except Exception:  # noqa: BLE001
                pass
            try:
                eng2, win2 = _build_ui(backend, config.load_config())
            except Exception as e:  # noqa: BLE001
                print("rebuild ui failed:", e, flush=True)
                return
            if win2 is None:
                return
            holder["win"] = win2
            holder.setdefault("engines", []).append(eng2)
            if icon_path and os.path.exists(icon_path):
                win2.icon = QIcon(icon_path)
            if maxed:
                win2.showMaximized()
            else:
                win2.show()
            QTimer.singleShot(0, lambda: _fix_win32_window(win2))
            # 新界面是空白的，立刻按上次查询重新拉数据（有缓存会秒开）
            QTimer.singleShot(50, lambda: backend.request(getattr(backend, "_last_query", "") or ""))
        QTimer.singleShot(220, _do)

    backend.languageChanged.connect(_rebuild)


def main() -> int:
    out, city = _args()

    # 控制台日志统一 UTF-8：否则 Windows 默认代码页会把中文报告打成乱码
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

    # 非原生控件样式：允许 TextField 自定义背景
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    if out:
        # 截图验证模式强制离屏渲染：不依赖桌面 GPU 窗口，抓图最稳定
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    app = QGuiApplication(sys.argv)
    app.setApplicationName(config.APP_NAME)
    app.setApplicationDisplayName(config.APP_TITLE)
    _ensure_fonts(app)

    # 单实例：已有窗口在跑就唤起它并立刻退出（连点多次不会开出一堆窗口）
    single_name = _single_instance_name()
    if not out and _raise_existing_instance(single_name):
        return 0

    icon_path = os.path.join(config.assets_dir(), "appicon", "app_icon.ico")
    if os.path.exists(icon_path):
        app.setWindowIcon(QIcon(icon_path))

    cfg = config.load_config()
    config.ensure_template_config()

    # 多语言：先按配置装词典，标题与界面文案都依赖当前语言
    i18n.load()
    i18n.set_language(cfg.get("language"))

    backend = Backend(cfg)
    engine, win = _build_ui(backend, cfg)
    if win is None:
        return 1
    if os.path.exists(icon_path):
        win.icon = QIcon(icon_path)

    if not out:
        # 真实窗口：启动直接最大化（无边框窗口原生任务栏样式修复：最小化恢复 / 任务栏点击）
        holder = {"win": win, "engines": [engine]}
        server = _serve_single_instance(app, single_name, holder)
        if server is None:
            # 竞态兜底：几乎同时启动的另一份已先抢到管道，本份静默退出
            return 0

        _install_language_switch(backend, holder, icon_path)
        win.showMaximized()
        QTimer.singleShot(0, lambda: _fix_win32_window(win))
        return app.exec()

    if out:
        # 截图模式：普通尺寸窗口（grabToImage 需要已 show 的窗口，保持 1260x860）
        win.show()
        app.processEvents()
        import time
        state = {"done": False}

        def _loaded(_d):
            state["done"] = True

        def _err(_m):
            state["done"] = True

        backend.dataLoaded.connect(_loaded)
        backend.errorOccurred.connect(_err)
        backend.request(city)
        deadline = time.time() + 40
        while not state["done"] and time.time() < deadline:
            app.processEvents()
            time.sleep(0.05)
        app.processEvents()
        for _ in range(12):  # 等渲染稳定
            app.processEvents()
            time.sleep(0.2)
        if "--cand" in sys.argv:
            # 候选栏截图验证：强制显示 + 注入输入文本触发 onTextChanged
            win.setProperty("suggTest", True)
            sf = win.findChild(QObject, "searchField")
            if sf:
                sf.setProperty("text", "北")
                for _ in range(6):
                    app.processEvents()
                    time.sleep(0.1)
        try:
            if os.path.exists(out):
                os.remove(out)
            QMetaObject.invokeMethod(win, "grabRequested", Qt.ConnectionType.DirectConnection,
                                     Q_ARG(str, out))
            for _ in range(500):
                app.processEvents()
                if os.path.exists(out):
                    break
                time.sleep(0.02)
            print("screenshot saved:", out)
            return 0 if os.path.exists(out) else 1
        except Exception as e:  # noqa: BLE001
            print("screenshot failed:", e)
            return 1

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
