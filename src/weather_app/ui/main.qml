import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Window {
    id: root
    width: 1260
    height: 860
    minimumWidth: 1160
    minimumHeight: 720
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: appTitle

    property var wd: ({})
    property bool loading: false
    property bool hasData: false       // 是否已有可显示数据（缓存或网络）
    property bool settingsOpen: false  // 设置面板是否打开（第二层）
    property bool previewOpen: false   // 背景预览面板是否打开（第二层）
    property bool bgA: true
    property real dMin: 0
    property real dMax: 40
    readonly property bool maximized: visibility === Window.Maximized
    property bool suggTest: false  // 截图验证用：强制显示候选栏

    // ===== 液态玻璃：整窗背景纹理（供 GlassCard 采样） =====
    property Item glassTexture: bgTex
    property Item glassRoot: bgCapture
    property Item glassFollow: null
    property bool glassLive: false

    // 换图 / 改主题 / 背景动画 / 改窗口尺寸后，短暂让背景纹理跟随重抓
    // 多语言：界面里的文案统一写成 tr("简体原文")，由 Python 侧词典翻译；
    // 切换语言时 Python 会重建整个界面，无需在此处理重翻译。
    function tr(text) {
        try { return backend.translate(text) } catch (e) { return text }
    }

    function touchGlass() {
        if (!root.glassTexture)
            return
        root.glassTexture.scheduleUpdate()
        root.glassLive = true
        glassHold.restart()
    }

    Timer {
        id: glassHold
        interval: 1400
        repeat: false
        onTriggered: root.glassLive = false
    }

    // ===== 太阳高度角（背景色温层随真实太阳位置实时变化） =====
    property real solarElev: 0
    readonly property color skyTintColor: {
        if (root.light) return "#00000000"
        var e = root.solarElev
        // 白天/黄金时刻不再叠暖色：暖色 alpha 叠在蓝色天空上会发棕，
        // 日出日落时叠在深蓝夜空中会发紫。这里只做中性压暗，色相完全交给实景图。
        if (e >= 0) return "#00000000"
        var k = Math.min(1, -e / 18)
        return Qt.rgba(0.012, 0.030, 0.085, 0.10 + 0.32 * k)
    }
    onSolarElevChanged: root.touchGlass()

    // ===== 窗口状态记忆（修复：最大化→最小化→任务栏恢复 保持最大化） =====
    property int lastVis: Window.Windowed   // 最近一次非最小化可见状态
    property bool wasMin: false             // 是否经过最小化
    property bool _restoring: false         // 防递归
    property rect _windowedGeo: Qt.rect(0, 0, 1260, 860)  // 最大化前的窗口位置/尺寸
    property bool _draggingFromMax: false   // 正在从最大化拖出，避免把最大化尺寸记成窗口尺寸

    function saveWindowedGeo() {
        if (root.visibility === Window.Windowed && !root._draggingFromMax
                && root.width > 0 && root.height > 0) {
            root._windowedGeo = Qt.rect(root.x, root.y, root.width, root.height)
        }
    }

    onXChanged: root.saveWindowedGeo()
    onYChanged: root.saveWindowedGeo()
    onWidthChanged: { root.saveWindowedGeo(); root.touchGlass() }
    onHeightChanged: { root.saveWindowedGeo(); root.touchGlass() }

    onVisibilityChanged: function (visibility) {
        if (root._restoring) return
        if (visibility === Window.Minimized) {
            root.wasMin = true
            return
        }
        if (root.wasMin) {
            root.wasMin = false
            if (visibility === Window.Windowed && root.lastVis === Window.Maximized) {
                root._restoring = true
                Qt.callLater(function () {
                    root.visibility = Window.Maximized
                    root._restoring = false
                })
            }
        }
        if (visibility !== Window.Minimized) root.lastVis = visibility
        if (visibility === Window.Windowed) root.saveWindowedGeo()
    }

    // ===== 雨天判定（雨滴动效开关） =====
    readonly property bool isRain: !!(root.wd && root.wd.current &&
        (["rain", "heavy_rain", "showers", "heavy_showers", "drizzle", "freezing",
          "thunder", "thunder_hail"].indexOf(root.wd.current.icon) >= 0))

    // ================= 深浅色主题（v1.1）=================
    property string theme: (typeof initialTheme !== "undefined" && initialTheme) ? initialTheme : "dark"
    readonly property bool light: root.theme === "light"
    onThemeChanged: root.touchGlass()
    property color bgTop: root.light ? "#EDF3FB" : "#1E2E63"
    property color bgMid: root.light ? "#DCE8F4" : "#131F49"
    property color bgBot: root.light ? "#C3D4EA" : "#0B1330"
    property color tMain: root.light ? "#1C2B4A" : "#FFFFFF"
    property color tSub1: root.light ? "#991C2B4A" : "#B8FFFFFF"
    property color tSub2: root.light ? "#8C1C2B4A" : "#A6FFFFFF"
    property color tSub3: root.light ? "#D91C2B4A" : "#D9FFFFFF"
    property color tSub4: root.light ? "#731C2B4A" : "#8CFFFFFF"
    property color tSub5: root.light ? "#A61C2B4A" : "#A6FFFFFF"
    property color tSub6: root.light ? "#BF1C2B4A" : "#BFFFFFFF"
    property color tSub7: root.light ? "#9E1C2B4A" : "#B8FFFFFF"
    property color tDiv: root.light ? "#1F1C2B4A" : "#1FFFFFFF"
    property color tGlass: root.light ? "#38FFFFFF" : "#1AFFFFFF"
    property color tGlassH: root.light ? "#59FFFFFF" : "#33FFFFFF"
    property color tGlassL: root.light ? "#24FFFFFF" : "#0FFFFFFF"
    property color tGlassB: root.light ? "#4DFFFFFF" : "#29FFFFFF"
    property color tGlassFocus: root.light ? "#B31E6FD9" : "#73FFFFFF"
    property color tChromeBd: root.light ? "#40FFFFFF" : "#24FFFFFF"
    property color tChromeBdH: root.light ? "#66FFFFFF" : "#40FFFFFF"
    property color chipBg: root.light ? "#30FFFFFF" : "#14FFFFFF"
    property color chipBd: root.light ? "#52FFFFFF" : "#24FFFFFF"
    property color tBar: root.light ? "#A0E9F1FA" : "#8C0A1428"
    property color tOverlay: root.light ? "#8CE9F1FA" : "#730A1428"
    property color tNote: root.light ? "#C07A00" : "#FFD60A"

    // ===== 温度单位 / 动画强度（设置面板即时生效，启动时由 Python 注入） =====
    property string tempUnit: (typeof initialTempUnit !== "undefined" && initialTempUnit) ? initialTempUnit : "C"
    property string animLevel: (typeof initialAnimLevel !== "undefined" && initialAnimLevel) ? initialAnimLevel : "full"
    property real hoverBrightness: (typeof initialHoverBrightness !== "undefined" && initialHoverBrightness !== null) ? initialHoverBrightness : 1.0
    property bool glassFloat: (typeof initialGlassFloat !== "undefined") ? !!initialGlassFloat : true
    property bool mouseFollow: (typeof initialMouseFollow !== "undefined") ? !!initialMouseFollow : true
    property var glassLayout: {
        var o = {}
        try {
            o = JSON.parse(typeof initialGlassLayout !== "undefined" && initialGlassLayout
                            ? initialGlassLayout : "{}")
        } catch (e) { o = {} }
        return (o && typeof o === "object") ? o : {}
    }
    property bool glassEdit: false
    onGlassEditChanged: {
        searchField.focus = false
        root.touchGlass()
        if (root.glassEdit) {
            root.showToast(tr("已进入玻璃位置编辑：拖动卡片互换位置"), "#D91E6FD9", 3200)
        } else {
            for (var i = 0; i < root.glassCards.length; i++) {
                root.glassCards[i].previewDX = 0
                root.glassCards[i].previewDY = 0
                root.glassCards[i].swapTarget = null
            }
        }
    }
    property bool refreshRequested: false
    property bool refreshFailed: false
    property string pendingQuery: ""

    function convT(v) {
        if (v === null || v === undefined || v === "") return null
        var n = parseFloat(v)
        if (isNaN(n)) return null
        return root.tempUnit === "F" ? n * 9 / 5 + 32 : n
    }
    function fmtT(v, dec) {
        var n = root.convT(v)
        if (n === null) return "--"
        var d = (dec === undefined) ? 1 : dec
        var s = n.toFixed(d)
        if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "")
        return s
    }
    function tempText(v, unit) {
        if (root.convT(v) === null) return "--"
        return root.fmtT(v) + (unit === false ? "°" : "°" + root.tempUnit)
    }

    // ===== 刷新反馈 / 设置保存 / 玻璃位置编辑 =====
    function showToast(msg, color, ms) {
        toastText.text = msg || ""
        toast.color = color || "#D9DC3C3C"
        toastTimer.interval = ms || 3800
        toastTimer.restart()
    }

    function manualRequest(q) {
        searchField.focus = false
        root.pendingQuery = q || ""
        root.refreshRequested = true
        root.refreshFailed = false
        if (q)
            root.showToast(tr("正在搜索「{q}」…").replace("{q}", q), "#D91E6FD9", 6000)
        else
            root.showToast(tr("正在刷新天气数据…"), "#D91E6FD9", 6000)
        backend.request(q || "")
    }

    function fmtUpdated(meta) {
        if (!meta) return ""
        if (meta.fetched_at) return meta.fetched_at
        var s = meta.updated_full || meta.updated || ""
        if (s.length >= 16) return s.substring(5, 16).replace("T", " ")
        return s
    }

    function updateCardLayout(key, dx, dy) {
        var o = {}
        for (var k in root.glassLayout)
            o[k] = root.glassLayout[k]
        o[key] = [Math.round(dx * 10) / 10, Math.round(dy * 10) / 10]
        root.glassLayout = o
        try { backend.saveGlassLayout(JSON.stringify(o)) } catch (e) {}
    }

    function resetGlassLayout() {
        root.glassLayout = ({})
        try { backend.saveGlassLayout("{}") } catch (e) {}
        for (var i = 0; i < root.glassCards.length; i++) {
            var c = root.glassCards[i]
            c.previewDX = 0
            c.previewDY = 0
            c.editDX = 0
            c.editDY = 0
            c.swapTarget = null
        }
        root.showToast(tr("已恢复玻璃卡片的默认位置"), "#D910B981", 2400)
    }

    // ===== iOS 风格位置互换：拖一张卡靠近另一张时，另一张平滑让位并交换 =====
    property var glassCards: []
    function registerGlassCard(card) {
        if (card && card.layoutKey && root.glassCards.indexOf(card) < 0)
            root.glassCards.push(card)
    }
    function glassVisualCenter(c) {
        if (!c || !bgCapture) return Qt.point(0, 0)
        var p = c.mapToItem(bgCapture, c.width / 2, c.height / 2)
        return Qt.point(p.x, p.y)
    }
    function glassBaseCenter(c) {
        var p = glassVisualCenter(c)
        return Qt.point(p.x - c.editDX - c.previewDX,
                        p.y - c.editDY - c.previewDY)
    }
    function glassOverlap(a, b) {
        var ca = glassVisualCenter(a)
        var cb = glassVisualCenter(b)
        return Math.abs(ca.x - cb.x) < (a.width + b.width) * 0.50 &&
               Math.abs(ca.y - cb.y) < (a.height + b.height) * 0.50
    }
    // 只在松手时判定目标：8 个小卡槽位里离拖动卡最近的那一个。
    // 拖动过程中不让其他卡片移动，彻底避免闪烁与连锁错位。
    function findGlassSwapTarget(dragged) {
        dragged.swapTarget = null
        if (!dragged) return
        var best = null
        var bestD = 1e12
        var dc = glassVisualCenter(dragged)
        for (var i = 0; i < root.glassCards.length; i++) {
            var o = root.glassCards[i]
            if (o === dragged || !o.layoutKey || !o.visible) continue
            if (o.parent !== dragged.parent) continue
            if (Math.abs(o.width - dragged.width) > 40 ||
                    Math.abs(o.height - dragged.height) > 40) continue
            var oc = o.baseVisualReady
                     ? Qt.point(o.baseVisual.x + o.editDX, o.baseVisual.y + o.editDY)
                     : glassVisualCenter(o)
            var dx = oc.x - dc.x
            var dy = oc.y - dc.y
            // 目标必须在拖动卡附近（约 1.5 个卡宽以内）
            if (Math.abs(dx) > dragged.width * 1.5 || Math.abs(dy) > dragged.height * 1.5)
                continue
            var d = dx * dx + dy * dy
            if (d < bestD) { bestD = d; best = o }
        }
        if (best) {
            dragged.swapTarget = best
            dragged.swapTargetBase = best.baseVisualReady ? best.baseVisual : glassBaseCenter(best)
        }
    }
    function commitGlassSwap(dragged) {
        var t = dragged.swapTarget
        if (!t) return
        var db = dragged.baseVisualReady ? dragged.baseVisual : glassBaseCenter(dragged)
        var tb = dragged.swapTargetBase
        var so = dragged.dragStartOffset
        var to = Qt.point(t.editDX, t.editDY)
        dragged.editDX = to.x + (tb.x - db.x)
        dragged.editDY = to.y + (tb.y - db.y)
        t.editDX = so.x + (db.x - tb.x)
        t.editDY = so.y + (db.y - tb.y)
        t.previewDX = 0
        t.previewDY = 0
        dragged.swapTarget = null
        // 两张卡一次性提交：避免逐张写回时 onGlassLayoutChanged 把另一张重置
        var o = {}
        for (var k in root.glassLayout) o[k] = root.glassLayout[k]
        o[dragged.layoutKey] = [Math.round(dragged.editDX * 10) / 10,
                                Math.round(dragged.editDY * 10) / 10]
        o[t.layoutKey] = [Math.round(t.editDX * 10) / 10,
                          Math.round(t.editDY * 10) / 10]
        root.glassLayout = o
        try { backend.saveGlassLayout(JSON.stringify(o)) } catch (e) {}
    }

    // 非编辑状态下持续记录每张卡的“布局基准中心”（不含任何拖动偏移）
    Timer {
        interval: 600
        repeat: true
        running: true
        onTriggered: {
            if (root.glassEdit) return
            for (var i = 0; i < root.glassCards.length; i++) {
                var c = root.glassCards[i]
                if (!c || c.previewDX !== 0 || c.previewDY !== 0 || c.dragging) continue
                var vc = glassVisualCenter(c)
                c.baseVisual = Qt.point(vc.x - c.editDX, vc.y - c.editDY)
                c.baseVisualReady = true
            }
        }
    }

    // 天气数据更新 → 背景平滑切换到对应的天气实景图（深色主题）
    onWdChanged: { root.refreshSky(); root.updateSolar() }

    // 太阳高度角变化（每分钟刷新一次，保证背景随真实光照平滑变化）
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.updateSolar()
    }

    // 启动请求：等首帧渲染后再拉数据，避免 QML 还在构建时就开始网络/解析
    Timer {
        id: startupTimer
        interval: 220
        repeat: false
        onTriggered: backend.request("")
    }

    // 回到顶部：从当前位置平滑过渡到顶部，不做瞬移
    NumberAnimation {
        id: scrollTopAnim
        objectName: "scrollTopAnim"
        target: content
        property: "contentY"
        duration: 460
        easing.type: Easing.OutCubic
    }

    // ================= 窗口圆角外壳 =================
    Rectangle {
        id: chrome
        anchors.fill: parent
        radius: root.maximized ? 0 : 26
        clip: true
        color: "transparent"
        border.width: root.maximized ? 0 : 1
        border.color: root.tChromeBd

        // ================= 背景捕获层（玻璃卡片只抓这一层，不把前景内容折射进去） =================
        Item {
            id: bgCapture
            anchors.fill: parent

            // ---------- 渐变垫底（启动即时可见，杜绝全透明抽动） ----------
            Rectangle {
                id: bgBase
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.bgTop }
                    GradientStop { position: 0.55; color: root.bgMid }
                    GradientStop { position: 1.0; color: root.bgBot }
                }
            }

            // ---------- 天气实景背景（深色主题：随当前天气状况切换，苹果天气风格；浅色主题隐藏） ----------
            Image {
                id: bgImage
                anchors.fill: parent
                source: "file:///" + res.replace(/\\/g, "/") + "/ui/sky/sky_clear.jpg"
                fillMode: Image.PreserveAspectCrop
                smooth: true
                opacity: 0
                visible: !root.light
                onStatusChanged: {
                    if (status == Image.Ready && !root.light) {
                        bgFade.start()
                        root.touchGlass()
                    }
                }
            }
            NumberAnimation {
                id: bgFade
                target: bgImage
                property: "opacity"
                to: 1
                duration: 900
                easing.type: Easing.InOutQuad
            }

            // ---------- 太阳高度色温层（随真实太阳高度角连续变化，深色主题） ----------
            Rectangle {
                id: bgTint
                objectName: "bgTint"
                anchors.fill: parent
                visible: !root.light
                color: root.skyTintColor
                Behavior on color { ColorAnimation { duration: 1200; easing.type: Easing.InOutQuad } }
            }
        }

        // 整窗背景纹理：1/2 分辨率 + mipmap，轻磨砂；换图/动画/改尺寸时短暂 live
        ShaderEffectSource {
            id: bgTex
            z: -10
            sourceItem: bgCapture
            live: root.glassLive
            textureSize: Qt.size(Math.max(1, Math.ceil(root.width / 2)),
                                 Math.max(1, Math.ceil(root.height / 2)))
            wrapMode: ShaderEffectSource.ClampToEdge
            smooth: true
            mipmap: true
            visible: true
        }
        // 天气数据更新时，背景平滑淡入到对应的天气实景图（主题切换走 root.refreshSky）
        // 注：onWdChanged 定义在 Window 根级（root.wd 属性处），见文件顶部

        // ================= 顶部栏（可拖拽窗口） =================
        Rectangle {
            id: header
            z: 100  // 提示气泡必须盖在内容区玻璃卡片之上
            height: 62
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                property point clickPos: "0,0"
                property bool _armed: true

                onPressed: function (mouse) {
                    clickPos = Qt.point(mouse.x, mouse.y)
                    _armed = true
                    searchField.focus = false
                }
                onPositionChanged: function (mouse) {
                    if (!pressed || !_armed) return

                    // 最大化时拖动：先还原到窗口态，再让窗口跟着鼠标走（Windows 原生行为）
                    if (root.maximized) {
                        if (Math.abs(mouse.x - clickPos.x) + Math.abs(mouse.y - clickPos.y) < 8)
                            return
                        var gx = root.x + mouse.x          // 光标在屏幕上的位置
                        var gy = root.y + mouse.y
                        var geo = root._windowedGeo
                        var ww = (geo && geo.width > 200) ? geo.width : 1260
                        var wh = (geo && geo.height > 200) ? geo.height : 860
                        var ratio = Math.max(0.08, Math.min(0.92, gx / Math.max(1, root.width)))
                        var offY = Math.max(10, Math.min(mouse.y, 40))

                        root._draggingFromMax = true
                        root.visibility = Window.Windowed
                        _armed = false
                        Qt.callLater(function () {
                            root.width = ww
                            root.height = wh
                            root.x = Math.round(gx - ww * ratio)
                            root.y = Math.round(gy - offY)
                            // 重新校准拖动基准，让后续移动连续
                            clickPos = Qt.point(root.width * ratio, offY)
                            root._draggingFromMax = false
                            _armed = true
                        })
                        return
                    }

                    root.x += mouse.x - clickPos.x
                    root.y += mouse.y - clickPos.y
                }
                onDoubleClicked: {
                    root.visibility = (root.visibility === Window.Maximized)
                                    ? Window.Windowed : Window.Maximized
                }
            }

            // 标题
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    width: 30
                    height: 30
                    radius: 9
                    color: root.tChromeBd
                    border.color: root.tChromeBdH
                    border.width: 1
                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "file:///" + res.replace(/\\/g, "/") + "/appicon/app_icon_1024.png"
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(60, 60)
                    }
                }
                Column {
                    id: titleCol
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: tr("天气")
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: root.tMain
                    }
                    Text {
                        text: tr("多源天气分析")
                        font.pixelSize: 10
                        color: root.tSub2
                    }
                }

                // 天气背景预览入口（标题右侧小太阳）
                Item {
                    width: 26
                    height: 30

                    Rectangle {
                        id: previewEntry
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: (previewArea.containsMouse || skyPreview.opened) ? root.tGlassH : root.tGlass
                        border.width: 1
                        border.color: root.tGlassB
                        Behavior on color { ColorAnimation { duration: 160 } }

                        Image {
                            anchors.centerIn: parent
                            source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/clear.svg"
                            sourceSize: Qt.size(15, 15)
                            scale: previewArea.containsMouse ? 1.10 : 1.0
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            id: previewArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: skyPreview.opened = !skyPreview.opened
                        }
                        TipBubble { text: tr("天气背景预览"); hovered: previewArea.containsMouse; theme: root.theme }
                    }
                }

                // 设置入口（预览图标右侧）
                Item {
                    width: 26
                    height: 30

                    Rectangle {
                        id: settingsBtn
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: (settingsArea.containsMouse || settingsPanel._open) ? root.tGlassH : root.tGlass
                        border.width: 1
                        border.color: root.tGlassB
                        Behavior on color { ColorAnimation { duration: 160 } }

                        Image {
                            anchors.centerIn: parent
                            source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/settings.svg"
                            sourceSize: Qt.size(15, 15)
                            scale: settingsArea.containsMouse ? 1.10 : 1.0
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            id: settingsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: settingsPanel.open()
                        }
                        TipBubble { text: tr("设置"); hovered: settingsArea.containsMouse; theme: root.theme }
                    }
                }
            }

            // ===== 玻璃位置编辑入口（搜索框左侧） =====
            Item {
                id: glassEditEntry
                anchors.right: searchBox.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                height: 34

                Rectangle {
                    anchors.fill: parent
                    radius: 17
                    color: root.glassEdit ? (root.light ? "#CC1E6FD9" : "#CC3B82F6") : (glassEditArea.containsMouse ? root.tGlassH : root.tGlass)
                    border.width: 1
                    border.color: root.glassEdit ? "#7DD3FC" : root.tGlassB
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Text {
                        anchors.centerIn: parent
                        text: root.glassEdit ? tr("完成") : tr("编辑")
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: root.glassEdit ? "#FFFFFF" : root.tMain
                        scale: glassEditArea.containsMouse ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: glassEditArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchField.focus = false
                            root.glassEdit = !root.glassEdit
                        }
                    }
                    TipBubble {
                        text: root.glassEdit ? tr("完成") : tr("编辑")
                        hovered: glassEditArea.containsMouse && !root.glassEdit
                        theme: root.theme
                    }
                }
            }

            // 搜索框
            Rectangle {
                id: searchBox
                anchors.left: parent.left
                anchors.leftMargin: 300
                anchors.right: parent.right
                // 右侧有 6 个 36px 按钮（266px）+ 28px 边距，这里留出 316px 防重叠
                anchors.rightMargin: 316
                anchors.verticalCenter: parent.verticalCenter
                height: 38
                radius: 19
                color: loading ? root.tGlassL : root.tGlass
                border.width: 1
                border.color: searchField.activeFocus ? root.tGlassFocus : root.tGlassB
                Behavior on border.color { ColorAnimation { duration: 160 } }

                Image {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/search.svg"
                    sourceSize: Qt.size(17, 17)
                    opacity: 0.7
                }

                TextField {
                    id: searchField
                    objectName: "searchField"
                    anchors.fill: parent
                    anchors.leftMargin: 42
                    anchors.rightMargin: 14
                    background: Item {}
                    color: root.tMain
                    placeholderText: tr("搜索城市，如：北京 / 上海 / 广州…")
                    placeholderTextColor: root.tSub4
                    font.pixelSize: 14
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true
                    onTextChanged: {
                        var q = text.trim()
                        if (q.length >= 1) {
                            var arr = []
                            try { arr = JSON.parse(backend.suggest(q)) } catch (e) {}
                            suggestModel.clear()
                            for (var i = 0; i < arr.length; i++)
                                suggestModel.append(arr[i])
                            suggestPanel.visible =
                                (arr.length > 0 && (activeFocus || root.suggTest))
                        } else {
                            suggestPanel.visible = false
                        }
                    }
                    onActiveFocusChanged: {
                        if (!activeFocus) suggestPanel.visible = false
                    }
                    onAccepted: {
                        suggestPanel.visible = false
                        var q = text.trim()
                        focus = false
                        if (q) root.manualRequest(q)
                    }
                }
            }

            // ===== 搜索候选栏（打字实时出词：本地区县/常用城市/国外别名） =====
            Rectangle {
                id: suggestPanel
                visible: false
                z: 80
                anchors.top: searchBox.bottom
                anchors.topMargin: 6
                anchors.left: searchBox.left
                anchors.right: searchBox.right
                height: Math.min(suggestModel.count, 8) * 34 + 2
                radius: 12
                color: root.tOverlay
                border.width: 1
                border.color: root.tGlassB

                ListModel { id: suggestModel }

                ListView {
                    id: suggestList
                    anchors.fill: parent
                    clip: true
                    model: suggestModel
                    interactive: false
                    delegate: Rectangle {
                        width: suggestList.width
                        height: 34
                        radius: 8
                        color: itemHov ? root.tGlassH : "transparent"
                        property bool itemHov: false
                        Text {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: label
                            color: root.tMain
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: sub
                            color: root.tSub3
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: itemHov = true
                            onExited: itemHov = false
                            onClicked: {
                                searchField.text = label
                                suggestPanel.visible = false
                                root.manualRequest(label)
                            }
                        }
                    }
                }
            }

            // 主题 / 设置 / 回到顶部 / 刷新 / 最小化 / 最大化 / 关闭（悬停显示说明气泡）
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                    property bool hov: false
                    width: 36
                    height: 36
                    radius: 18
                    color: hov ? root.tGlassH : root.tGlass
                    border.color: root.tGlassB
                    border.width: 1
                    Image {
                        anchors.centerIn: parent
                        source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" +
                                (root.light ? "light/night_clear" : "light/clear") + ".svg"
                        sourceSize: Qt.size(20, 20)
                    }
                    TipBubble { text: tr("切换深浅色主题"); hovered: parent.hov; theme: root.theme }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: {
                            searchField.focus = false
                            root.theme = root.light ? "dark" : "light"
                            backend.saveTheme(root.theme)
                            root.refreshSky()
                        }
                    }
                }
                Rectangle {
                    property bool hov: false
                    width: 36
                    height: 36
                    radius: 18
                    color: hov ? root.tGlassH : root.tGlass
                    border.color: root.tGlassB
                    border.width: 1
                    Image {
                        anchors.centerIn: parent
                        source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/arrow_up.svg"
                        sourceSize: Qt.size(19, 19)
                    }
                    TipBubble { text: tr("回到顶部"); hovered: parent.hov; theme: root.theme }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: root.scrollToTop()
                    }
                }
                Rectangle {
                    id: refreshBtn
                    property bool hov: false
                    width: 36
                    height: 36
                    radius: 18
                    color: root.loading ? (root.light ? "#5C3B82F6" : "#733B82F6")
                                        : (hov ? root.tGlassH : root.tGlass)
                    border.color: root.loading ? "#B37DD3FC" : root.tGlassB
                    border.width: 1
                    scale: hov ? 1.06 : 1.0
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    // 加载时的呼吸光圈，让"正在刷新"一眼可见
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: 22
                        color: "transparent"
                        border.width: 2
                        border.color: "#7DD3FC"
                        opacity: 0
                        visible: root.loading
                        SequentialAnimation on opacity {
                            running: root.loading
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.10; to: 0.70; duration: 700; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.70; to: 0.10; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }

                    Image {
                        id: refreshIcon
                        anchors.centerIn: parent
                        source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/refresh.svg"
                        sourceSize: Qt.size(19, 19)
                        RotationAnimation on rotation {
                            running: root.loading
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }
                    TipBubble { text: root.loading ? tr("正在刷新天气数据…") : tr("刷新天气数据"); hovered: parent.hov; theme: root.theme }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: root.manualRequest(searchField.text.trim())
                    }
                }
                Rectangle {
                    property bool hov: false
                    width: 36
                    height: 36
                    radius: 18
                    color: hov ? root.tGlassH : root.tGlass
                    border.color: root.tGlassB
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "—"
                        font.pixelSize: 13
                        color: root.tMain
                    }
                    TipBubble { text: tr("最小化"); hovered: parent.hov; theme: root.theme }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: root.visibility = Window.Minimized
                    }
                }
                Rectangle {
                    property bool hov: false
                    width: 36
                    height: 36
                    radius: 18
                    color: hov ? root.tGlassH : root.tGlass
                    border.color: root.tGlassB
                    border.width: 1
                    Item {
                        anchors.centerIn: parent
                        width: 15
                        height: 15
                        Rectangle {
                            x: 0
                            y: 0
                            width: 11
                            height: 11
                            radius: 2
                            color: "transparent"
                            border.color: root.tMain
                            border.width: 1.3
                        }
                        Rectangle {
                            x: 4
                            y: 4
                            width: 11
                            height: 11
                            radius: 2
                            color: "transparent"
                            border.color: root.tMain
                            border.width: 1.3
                            visible: root.maximized
                        }
                    }
                    TipBubble { text: root.maximized ? tr("还原窗口") : tr("最大化"); hovered: parent.hov; theme: root.theme }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: root.visibility = root.maximized ? Window.Windowed : Window.Maximized
                    }
                }
                Rectangle {
                    property bool hov: false
                    width: 36
                    height: 36
                    radius: 18
                    color: hov ? "#8CFF5050" : "#1AFFFFFF"
                    border.color: root.tGlassB
                    border.width: 1
                    Image {
                        anchors.centerIn: parent
                        source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/close.svg"
                        sourceSize: Qt.size(17, 17)
                    }
                    TipBubble { text: tr("关闭应用"); hovered: parent.hov; theme: root.theme }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: Qt.quit()
                    }
                }
            }
        }

        // ================= 主内容（垂直滚动） =================
        Item {
            id: contentArea
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: sourceBar.top
            // 第二层页面打开时，底层内容不再接收鼠标/滚轮/悬停
            enabled: !root.settingsOpen && !root.previewOpen

            Flickable {
                id: content
                objectName: "contentFlick"
                anchors.fill: parent
                contentWidth: width
                contentHeight: col.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 3600
                maximumFlickVelocity: 7500
                interactive: !root.settingsOpen && !root.previewOpen
                onMovementStarted: searchField.focus = false
                onFlickStarted: searchField.focus = false

                Column {
                    id: col
                    x: 28
                    width: content.width - 56
                    spacing: 16

                    // ============ 当前天气 ============
                    GlassCard {
                        theme: root.theme
                        hoverable: false  // 大卡不浮动，但仍参与鼠标跟随
                        id: currentCard
                        width: parent.width
                        height: 260
                        pad: 22

                        Column {
                            anchors.fill: parent
                            spacing: 14

                            Row {
                                width: parent.width
                                spacing: 26

                                WeatherIcon {
                                    key: wd.current ? wd.current.icon : "cloudy"
                                    size: 118
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Row {
                                        spacing: 8
                                        Text {
                                            text: wd.location ? wd.location.name : "--"
                                            font.pixelSize: 22
                                            font.weight: Font.DemiBold
                                            color: root.tMain
                                        }
                                        Text {
                                            text: (wd.location && (wd.location.admin || wd.location.country)) ?
                                                  (wd.location.admin + " · " + wd.location.country) : ""
                                            font.pixelSize: 13
                                            color: root.tSub1
                                            anchors.baseline: parent.baseline
                                        }
                                        Text {
                                            id: locSourceTag
                                            text: {
                                                var s = wd.location ? (wd.location.loc_source || "") : "";
                                                if (s === "windows") {
                                                    var acc = wd.location ? wd.location.accuracy_m : 0;
                                                    return acc ? tr("系统定位 ±{acc} 米").replace("{acc}", Math.round(acc)) : tr("系统定位");
                                                }
                                                if (s === "remembered") return tr("上次选择");
                                                if (s === "config") return tr("默认城市");
                                                if (s === "ip") return tr("IP 定位");
                                                if (s === "fallback") return tr("默认城市");
                                                return "";
                                            }
                                            visible: text !== ""
                                            font.pixelSize: 11
                                            color: root.tSub1
                                            anchors.baseline: parent.baseline
                                        }
                                    }
                                    Text {
                                        text: root.tempText(wd.current ? wd.current.temp : null)
                                        font.pixelSize: 76
                                        font.weight: Font.Light
                                        color: root.tMain
                                    }
                                    Row {
                                        spacing: 12
                                        Text {
                                            text: wd.current ? tr("{desc} · 体感 {t}").replace("{desc}", wd.current.desc).replace("{t}", root.tempText(wd.current.feels)) : "--"
                                            font.pixelSize: 15
                                            color: root.tSub3
                                        }
                                        Text {
                                            text: (wd.today && wd.today.tmax !== null && wd.today.tmin !== null) ?
                                                  tr("高 {hi}°  低 {lo}°").replace("{hi}", root.fmtT(wd.today.tmax)).replace("{lo}", root.fmtT(wd.today.tmin)) : ""
                                            font.pixelSize: 14
                                            color: root.tSub1
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: root.tDiv
                            }

                            Row {
                                width: parent.width
                                spacing: 10
                                Text {
                                    text: tr("多源综合温度")
                                    font.pixelSize: 12
                                    color: root.tSub1
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Repeater {
                                    model: wd.current ? wd.current.sources : []
                                    delegate: Rectangle {
                                        property var it: modelData
                                        width: chipRow.implicitWidth + 20
                                        height: 24
                                        radius: 12
                                        color: root.chipBg
                                        border.color: root.tChromeBd
                                        border.width: 1
                                        Row {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Rectangle {
                                                width: 7
                                                height: 7
                                                radius: 3.5
                                                color: root.srcColor(it.key)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: root.srcLabel(it.key) + " " + root.fmtT(it.temp) + "°"
                                                font.pixelSize: 12
                                                color: root.tMain
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }

                                Text {
                                    text: wd.meta && wd.meta.note ? (tr("注意：") + wd.meta.note) : ""
                                    font.pixelSize: 12
                                    color: root.tNote
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - x)
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // ============ 天气预警横幅（有预警时才显示） ============
                    Rectangle {
                        id: alarmBanner
                        width: parent.width
                        height: alarmBanner.visible ? implicitHeight : 0
                        implicitHeight: 56
                        radius: 16
                        property string lv: wd.current && wd.current.alarm ? wd.current.alarm.max_level : ""
                        // 颜色判断用后端给的稳定 code（red/orange/yellow/blue），避免翻译后字符串比对失效
                        property string lvCode: wd.current && wd.current.alarm
                                                 ? (wd.current.alarm.max_level_code || "") : ""
                        property color lvColor: {
                            if (lvCode === "red") return "#FF3B30";
                            if (lvCode === "orange") return "#FF9F0A";
                            if (lvCode === "yellow") return "#F5C542";
                            if (lvCode === "blue") return "#4A90D9";
                            return "transparent";
                        }
                        property color lvBg: {
                            if (lvCode === "red") return Qt.rgba(1.0, 0.23, 0.19, 0.30);
                            if (lvCode === "orange") return Qt.rgba(1.0, 0.62, 0.04, 0.28);
                            if (lvCode === "yellow") return Qt.rgba(0.96, 0.77, 0.26, 0.26);
                            if (lvCode === "blue") return Qt.rgba(0.29, 0.56, 0.85, 0.26);
                            return "transparent";
                        }
                        color: lvBg
                        border.width: 1
                        border.color: lvColor
                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
                        visible: !!(wd.current && wd.current.alarm && wd.current.alarm.count > 0)

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: alarmBanner.lvColor
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: "!"
                                    font.pixelSize: 20
                                    font.weight: Font.Bold
                                    color: alarmBanner.lvCode === "red" ? "#FFFFFF" : "#000000"
                                }
                            }

                            Column {
                                spacing: 2
                                Text {
                                    text: {
                                        var a = wd.current && wd.current.alarm ? wd.current.alarm : null;
                                        if (!a) return "";
                                        return tr("{lv}预警 · {type}（共 {n} 条）")
                                                .replace("{lv}", a.max_level)
                                                .replace("{type}", a.max_type)
                                                .replace("{n}", a.count);
                                    }
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    color: root.tMain
                                }
                                Text {
                                    text: {
                                        var a = wd.current && wd.current.alarm ? wd.current.alarm : null;
                                        if (!a || !a.items || a.items.length === 0) return "";
                                        var t = a.items[0].title;
                                        return t.length > 36 ? t.substring(0, 36) + "…" : t;
                                    }
                                    font.pixelSize: 11
                                    color: root.tSub3
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // ============ 指标磁贴 ============
                    Flow {
                        id: metricFlow
                        width: parent.width
                        spacing: 12

                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_thermo"
                            iconKey: "thermo"
                            label: tr("体感温度")
                            value: (wd.current && wd.current.feels !== null) ? root.tempText(wd.current.feels) : "--"
                        }
                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_humidity"
                            iconKey: "humidity"
                            label: tr("湿度")
                            value: (wd.current && wd.current.humidity !== null) ? wd.current.humidity + "%" : "--"
                        }
                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_pressure"
                            iconKey: "pressure"
                            label: tr("气压")
                            value: (wd.current && wd.current.pressure !== null) ? wd.current.pressure : "--"
                            sub: "hPa"
                        }
                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_visibility"
                            iconKey: "visibility"
                            label: tr("能见度")
                            value: (wd.current && wd.current.visibility_km !== null) ? wd.current.visibility_km : "--"
                            sub: "km"
                        }
                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_winddir"
                            iconKey: "winddir"
                            label: tr("风向 / 风力")
                            value: (wd.current && wd.current.wind_kmh !== null) ? wd.current.wind_kmh + "km/h" : "--"
                            sub: wd.current ? wd.current.wind_dir : ""
                        }
                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_gust"
                            iconKey: "gust"
                            label: tr("阵风")
                            value: (wd.current && wd.current.wind_gust !== null) ? wd.current.wind_gust : "--"
                            sub: "km/h"
                        }
                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_uv"
                            iconKey: "uv"
                            label: tr("紫外线")
                            value: (wd.current && wd.current.uv !== null) ? wd.current.uv : "--"
                            sub: (wd.current && wd.current.uv_info) ? wd.current.uv_info.label : ""
                            valueColor: (wd.current && wd.current.uv_info) ? wd.current.uv_info.color : "#FFFFFF"
                        }
                        MetricTile {
                            theme: root.theme
                            width: (metricFlow.width - 36) / 4
                            layoutKey: "m_precip"
                            iconKey: "precip"
                            label: tr("当前降水")
                            value: (wd.current && wd.current.precip_mm !== null) ? wd.current.precip_mm : "--"
                            sub: "mm"
                        }
                        // 月相磁贴（Apple 天气风格，独立组件）
                        MoonPhaseCard {
                            objectName: "moonCard"
                            theme: root.theme
                            wd: root.wd
                            width: parent.width
                        }
                    }

                    // ============ 空气质量 ============
                    GlassCard {
                        theme: root.theme
                        hoverable: false  // 大卡不浮动，但仍参与鼠标跟随
                        width: parent.width
                        height: 140
                        pad: 18

                        Row {
                            width: parent.width
                            spacing: 22

                            Column {
                                width: 170
                                spacing: 2
                                Text {
                                    text: tr("空气污染")
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    color: root.tMain
                                }
                                Row {
                                    spacing: 8
                                    Text {
                                        text: (wd.current && wd.current.aqi !== null) ? wd.current.aqi : "--"
                                        font.pixelSize: 40
                                        font.weight: Font.DemiBold
                                        color: (wd.current && wd.current.aqi_info) ? wd.current.aqi_info.color : "#FFFFFF"
                                    }
                                    Text {
                                        text: (wd.current && wd.current.aqi_info) ? wd.current.aqi_info.label : tr("暂无数据")
                                        font.pixelSize: 14
                                        color: (wd.current && wd.current.aqi_info) ? wd.current.aqi_info.color : "#FFFFFF"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // AQI 0-500 分级刻度条（六档颜色渐变 + 当前值指示点）
                                Item {
                                    width: 170
                                    height: 12
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 5
                                        radius: 2.5
                                        gradient: Gradient {
                                            GradientStop { position: 0.00; color: "#3ED477" }
                                            GradientStop { position: 0.20; color: "#FFD60A" }
                                            GradientStop { position: 0.30; color: "#FF9F0A" }
                                            GradientStop { position: 0.40; color: "#FF3B30" }
                                            GradientStop { position: 0.60; color: "#BF5AF2" }
                                            GradientStop { position: 1.00; color: "#9B2C2C" }
                                        }
                                    }
                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        border.width: 1.5
                                        border.color: root.tMain
                                        color: (wd.current && wd.current.aqi_info) ? wd.current.aqi_info.color : "#888888"
                                        x: (wd.current && wd.current.aqi !== null)
                                           ? Math.max(0, Math.min(170 - 8, (wd.current.aqi / 500) * 170))
                                           : 0
                                        y: (parent.height - 8) / 2
                                        visible: !!(wd.current && wd.current.aqi !== null)
                                    }
                                }
                            }

                            MetricTile {
                                theme: root.theme
                                width: 240
                                iconKey: "info"
                                label: tr("PM2.5 细颗粒物（模型）")
                                value: (wd.current && wd.current.pm25 !== null && wd.current.pm25 !== undefined) ? wd.current.pm25 : "--"
                                sub: "µg/m³"
                            }
                            MetricTile {
                                theme: root.theme
                                width: 240
                                iconKey: "info"
                                label: tr("PM10 可吸入颗粒（模型）")
                                value: (wd.current && wd.current.pm10 !== null && wd.current.pm10 !== undefined) ? wd.current.pm10 : "--"
                                sub: "µg/m³"
                            }

                            Column {
                                width: parent.width - 170 - 240 - 240 - 44
                                spacing: 7
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    width: parent.width
                                    text: (wd.current && wd.current.aqi_source === "chinacom")
                                          ? tr("空气污染指数为中国国标 AQI（中国天气网官方实时监测数据）。\nPM2.5 / PM10 为模型推算值，可能与官方监测偏差较大，判断空气质量请以 AQI 为准。")
                                          : tr("空气污染指数按中国 HJ 633-2012 标准换算（Open-Meteo 模型浓度，小时值参考）。")
                                    font.pixelSize: 12
                                    color: root.tSub1
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.55
                                }

                                // AQI 分级图例：六档色点 + 区间，当前档高亮
                                Text {
                                    width: parent.width
                                    textFormat: Text.RichText
                                    text: root.aqiLegendHtml()
                                    font.pixelSize: 11
                                    color: root.tSub1
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.4
                                }
                            }
                        }
                    }

                    // ============ 逐小时 ============
                    GlassCard {
                        theme: root.theme
                        hoverable: false  // 容器大卡不浮动，内部 HourlyTile 小卡浮动
                        width: parent.width
                        height: 300
                        pad: 18

                        Column {
                            anchors.fill: parent
                            spacing: 12

                            Row {
                                width: parent.width
                                Text {
                                    text: tr("逐小时 · 未来 48 小时")
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    color: root.tMain
                                }
                                Text {
                                    text: tr("  （左右滑动查看）")
                                    font.pixelSize: 11
                                    color: root.tSub4
                                    anchors.baseline: parent.baseline
                                }
                            }

                            ListView {
                                id: hourlyList
                                width: parent.width
                                height: 226
                                orientation: ListView.Horizontal
                                spacing: 10
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                flickDeceleration: 2800
                                cacheBuffer: 900
                                model: wd.hourly ? wd.hourly : []
                                delegate: HourlyTile {
                                    theme: root.theme
                                    item: modelData
                                    useF: root.tempUnit === "F"
                                    width: 214
                                }
                            }
                        }
                    }

                    // ============ 15 天预报 ============
                    GlassCard {
                        theme: root.theme
                        hoverable: false  // 大卡不浮动，但仍参与鼠标跟随
                        width: parent.width
                        height: 890
                        pad: 18

                        Column {
                            anchors.fill: parent
                            spacing: 6

                            Row {
                                width: parent.width
                                Text {
                                    text: tr("15 天预报 · 多源加权")
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    color: root.tMain
                                }
                                Text {
                                    text: tr("  （高低温为 Open-Meteo / ECMWF / wttr.in / 和风 加权平均）")
                                    font.pixelSize: 11
                                    color: root.tSub4
                                    anchors.baseline: parent.baseline
                                }
                            }

                            Column {
                                width: parent.width
                                Repeater {
                                    model: wd.daily ? wd.daily.slice(0, 15) : []
                                    delegate: DailyRow {
                                        theme: root.theme
                                        item: modelData
                                        useF: root.tempUnit === "F"
                                        barMin: root.convT(root.dMin)
                                        barMax: root.convT(root.dMax)
                                        width: parent.width
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= 数据源底栏 =================
        Rectangle {
            id: sourceBar
            height: 50
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: root.tBar
            border.color: root.tDiv
            border.width: 1
            radius: 0

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    text: tr("数据来源：")
                    font.pixelSize: 12
                    color: root.tSub2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Repeater {
                    model: wd.source_links ? wd.source_links : []
                    delegate: Row {
                        opacity: (modelData.enabled === false) ? 0.4 : 1.0
                        spacing: 6
                        Text {
                            text: modelData.name
                            font.pixelSize: 12
                            color: root.light ? "#1E6FD9" : "#7DD3FC"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.openLink(modelData.url)
                            }
                        }
                        Text {
                            text: index === (wd.source_links.length - 1) ? "" : "·"
                            font.pixelSize: 12
                            color: root.light ? "#661C2B4A" : "#66FFFFFF"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                text: (wd.meta ? tr("更新 ") + wd.meta.updated + "  ·  " : "") +
                      (wd.current ? wd.current.sources.length + tr(" 个数据源综合") : "") +
                      (wd.meta && wd.meta.cache_hit && !root.loading ? tr("  ·  缓存数据") : "") +
                      (root.loading && root.hasData ? tr("  ·  更新中…") : "")
                font.pixelSize: 12
                color: root.tSub2
            }
        }

        // ================= 加载遮罩 =================
        Rectangle {
            id: loadingOverlay
            anchors.fill: parent
            color: root.tOverlay
            // 有缓存/已有数据时不遮全屏：刷新只在右上角转圈，启动即可操作
            visible: root.loading && !root.hasData
            Behavior on visible { enabled: false }

            Column {
                anchors.centerIn: parent
                spacing: 16
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/loading.svg"
                    sourceSize: Qt.size(52, 52)
                    RotationAnimation on rotation {
                        running: root.loading
                        from: 0
                        to: 360
                        duration: 1100
                        loops: Animation.Infinite
                    }
                }
                Text {
                    text: tr("正在从多源获取天气数据…")
                    font.pixelSize: 14
                    color: root.tSub3
                }
            }
        }

        // ================= Toast =================
        Rectangle {
            id: toast
            visible: toastText.text.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: sourceBar.top
            anchors.bottomMargin: 16
            width: Math.min(520, toastText.implicitWidth + 44)
            height: 40
            radius: 20
            color: "#D9DC3C3C"
            Text {
                id: toastText
                anchors.centerIn: parent
                text: ""
                font.pixelSize: 13
                color: root.tMain
                elide: Text.ElideRight
                width: parent.width - 36
                horizontalAlignment: Text.AlignHCenter
            }
            Timer {
                id: toastTimer
                interval: 6000
                running: toastText.text.length > 0
                onTriggered: toastText.text = ""
            }
        }

        // ================= 玻璃位置编辑工具条 =================
        Rectangle {
            id: glassEditBar
            visible: root.glassEdit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: header.bottom
            anchors.topMargin: 10
            z: 900
            width: editBarRow.implicitWidth + 28
            height: 44
            radius: 22
            color: root.light ? "#EFF4FA" : "#1B2748"
            border.width: 1
            border.color: root.tChromeBdH

            Row {
                id: editBarRow
                anchors.centerIn: parent
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tr("拖动任意玻璃卡片调整位置")
                    font.pixelSize: 12
                    color: root.tMain
                }
                Rectangle {
                    property bool hov: false
                    width: 60; height: 28; radius: 14
                    color: hov ? root.tGlassH : root.tGlass
                    border.width: 1; border.color: root.tGlassB
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Text { anchors.centerIn: parent; text: tr("重置"); font.pixelSize: 12; color: root.tMain }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: root.resetGlassLayout()
                    }
                    TipBubble { text: tr("恢复默认位置"); hovered: parent.hov; theme: root.theme }
                }
                Rectangle {
                    property bool hov: false
                    width: 64; height: 28; radius: 14
                    color: hov ? "#5C3B82F6" : "#3B82F6"
                    border.width: 1; border.color: "#7DD3FC"
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Text { anchors.centerIn: parent; text: tr("完成"); font.pixelSize: 12; color: "#FFFFFF" }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.hov = true
                        onExited: parent.hov = false
                        onClicked: {
                            root.glassEdit = false
                            root.showToast(tr("玻璃位置已保存"), "#D910B981", 2400)
                        }
                    }
                    TipBubble { text: tr("完成编辑并保存"); hovered: parent.hov; theme: root.theme }
                }
            }
        }

        // ================= 边缘缩放手柄（无边框窗口自绘缩放） =================
        // 左缘
        MouseArea {
            visible: !root.maximized
            x: 0; y: 8
            width: 8
            height: parent.height - 16
            cursorShape: Qt.SizeHorCursor
            property real sx: 0
            property real ox: 0
            property real ow: 0
            onPressed: { sx = mouse.x; ox = root.x; ow = root.width }
            onPositionChanged: if (pressed) {
                var dx = mouse.x - sx
                var nw = ow - dx
                if (nw >= root.minimumWidth) { root.x = ox + dx; root.width = nw }
            }
        }
        // 右缘
        MouseArea {
            visible: !root.maximized
            x: parent.width - 8; y: 8
            width: 8
            height: parent.height - 16
            cursorShape: Qt.SizeHorCursor
            property real sx: 0
            property real ow: 0
            onPressed: { sx = mouse.x; ow = root.width }
            onPositionChanged: if (pressed) {
                var dx = mouse.x - sx
                var nw = ow + dx
                if (nw >= root.minimumWidth) root.width = nw
            }
        }
        // 上缘
        MouseArea {
            visible: !root.maximized
            x: 8; y: 0
            width: parent.width - 16
            height: 8
            cursorShape: Qt.SizeVerCursor
            property real sy: 0
            property real oy: 0
            property real oh: 0
            onPressed: { sy = mouse.y; oy = root.y; oh = root.height }
            onPositionChanged: if (pressed) {
                var dy = mouse.y - sy
                var nh = oh - dy
                if (nh >= root.minimumHeight) { root.y = oy + dy; root.height = nh }
            }
        }
        // 下缘
        MouseArea {
            visible: !root.maximized
            x: 8; y: parent.height - 8
            width: parent.width - 16
            height: 8
            cursorShape: Qt.SizeVerCursor
            property real sy: 0
            property real oh: 0
            onPressed: { sy = mouse.y; oh = root.height }
            onPositionChanged: if (pressed) {
                var dy = mouse.y - sy
                var nh = oh + dy
                if (nh >= root.minimumHeight) root.height = nh
            }
        }
        // 左上角
        MouseArea {
            visible: !root.maximized
            x: 0; y: 0
            width: 16; height: 16
            cursorShape: Qt.SizeFDiagCursor
            property real sx: 0
            property real sy: 0
            property real ox: 0
            property real ow: 0
            property real oy: 0
            property real oh: 0
            onPressed: { sx = mouse.x; sy = mouse.y; ox = root.x; oy = root.y; ow = root.width; oh = root.height }
            onPositionChanged: if (pressed) {
                var dx = mouse.x - sx
                var dy = mouse.y - sy
                var nw = ow - dx
                var nh = oh - dy
                if (nw >= root.minimumWidth) { root.x = ox + dx; root.width = nw }
                if (nh >= root.minimumHeight) { root.y = oy + dy; root.height = nh }
            }
        }
        // 右上角
        MouseArea {
            visible: !root.maximized
            x: parent.width - 16; y: 0
            width: 16; height: 16
            cursorShape: Qt.SizeBDiagCursor
            property real sx: 0
            property real sy: 0
            property real ow: 0
            property real oy: 0
            property real oh: 0
            onPressed: { sx = mouse.x; sy = mouse.y; ow = root.width; oy = root.y; oh = root.height }
            onPositionChanged: if (pressed) {
                var dx = mouse.x - sx
                var dy = mouse.y - sy
                var nw = ow + dx
                var nh = oh - dy
                if (nw >= root.minimumWidth) root.width = nw
                if (nh >= root.minimumHeight) { root.y = oy + dy; root.height = nh }
            }
        }
        // 左下角
        MouseArea {
            visible: !root.maximized
            x: 0; y: parent.height - 16
            width: 16; height: 16
            cursorShape: Qt.SizeBDiagCursor
            property real sx: 0
            property real sy: 0
            property real ox: 0
            property real ow: 0
            property real oh: 0
            onPressed: { sx = mouse.x; sy = mouse.y; ox = root.x; ow = root.width; oh = root.height }
            onPositionChanged: if (pressed) {
                var dx = mouse.x - sx
                var dy = mouse.y - sy
                var nw = ow - dx
                var nh = oh + dy
                if (nw >= root.minimumWidth) { root.x = ox + dx; root.width = nw }
                if (nh >= root.minimumHeight) root.height = nh
            }
        }
        // 右下角
        MouseArea {
            visible: !root.maximized
            x: parent.width - 16; y: parent.height - 16
            width: 16; height: 16
            cursorShape: Qt.SizeFDiagCursor
            property real sx: 0
            property real sy: 0
            property real ow: 0
            property real oh: 0
            onPressed: { sx = mouse.x; sy = mouse.y; ow = root.width; oh = root.height }
            onPositionChanged: if (pressed) {
                var dx = mouse.x - sx
                var dy = mouse.y - sy
                var nw = ow + dx
                var nh = oh + dy
                if (nw >= root.minimumWidth) root.width = nw
                if (nh >= root.minimumHeight) root.height = nh
            }
        }

        // ===== 雨滴动效：雨天雨滴落在玻璃上缓缓滑落（全窗口最顶层，点击穿透） =====
        RainDrops {
            anchors.fill: parent
            z: 1000
            active: root.isRain
            theme: root.theme
        }

        // ===== 天气背景预览面板（入口为标题右侧小太阳，开合带过渡动画） =====
        SkyPreview {
            id: skyPreview
            objectName: "skyPreview"
            z: 1200
            theme: root.theme
            assets: res
            wd: root.wd
            solarElev: root.solarElev
            onOpenedChanged: root.previewOpen = opened
        }

        // ==================== 登录页（chrome 内最顶层） ====================
        Rectangle {
            id: loginPage
            anchors.fill: parent
            visible: false
            z: 99999
            color: "#0F172A"

            // 拦截所有事件，不让底层响应
            MouseArea {
                anchors.fill: parent
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 200
                text: tr("天气")
                font.pixelSize: 32
                color: "#FFFFFF"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 250
                text: tr("登录以同步你的天气偏好")
                font.pixelSize: 14
                color: "#94A3B8"
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 300
                width: 320; height: 44; radius: 12
                color: "#1E293B"
                Text {
                    anchors.centerIn: parent
                    text: tr("邮箱地址")
                    font.pixelSize: 14
                    color: "#64748B"
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 360
                width: 320; height: 44; radius: 12
                color: "#1E293B"
                Text {
                    anchors.centerIn: parent
                    text: tr("5 位数字验证码")
                    font.pixelSize: 14
                    color: "#64748B"
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 420
                width: 320; height: 44; radius: 22
                color: "#3B82F6"
                Text { anchors.centerIn: parent; text: tr("进入天气"); font.pixelSize: 15; color: "#FFFFFF"; font.weight: Font.DemiBold }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: loginPage.visible = false
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 480
                text: tr("跳过登录")
                font.pixelSize: 12
                color: "#64748B"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: loginPage.visible = false
                }
            }
        }
    }

    // ================= 太阳高度角与滚动控制 =================
    // 依据经纬度与当前时刻计算真太阳高度角（含均时差修正，误差在分钟量级）
    function solarElevationDeg(lat, lon, dt) {
        var rad = Math.PI / 180
        var jd = dt.getTime() / 86400000 + 2440587.5
        var n = jd - 2451545.0
        var L = (280.460 + 0.9856474 * n) % 360
        if (L < 0) L += 360
        var g = (357.528 + 0.9856003 * n) % 360
        if (g < 0) g += 360
        var lambda = L + 1.915 * Math.sin(g * rad) + 0.020 * Math.sin(2 * g * rad)
        var eps = (23.439 - 0.0000004 * n) * rad
        var dec = Math.asin(Math.sin(eps) * Math.sin(lambda * rad))
        var B = 360 * (n - 81) / 364 * rad
        var eot = 9.87 * Math.sin(2 * B) - 7.53 * Math.cos(B) - 1.5 * Math.sin(B)
        var utcH = dt.getUTCHours() + dt.getUTCMinutes() / 60 + dt.getUTCSeconds() / 3600
        var solarH = utcH + lon / 15 + eot / 60
        var Ha = (solarH - 12) * 15 * rad
        var s = Math.sin(lat * rad) * Math.sin(dec) + Math.cos(lat * rad) * Math.cos(dec) * Math.cos(Ha)
        if (s > 1) s = 1
        if (s < -1) s = -1
        return Math.asin(s) / rad
    }

    // 从当前数据包中取经纬度；优先 location（聚合结果里 meta 通常不带坐标），缺失时回退北京
    function updateSolar() {
        var lat = 39.9042
        var lon = 116.4074
        var loc = root.wd && root.wd.location ? root.wd.location : null
        if (loc) {
            var a = parseFloat(loc.lat)
            var b = parseFloat(loc.lon)
            if (!isNaN(a) && !isNaN(b)) { lat = a; lon = b }
        }
        var m = root.wd && root.wd.meta ? root.wd.meta : null
        if (m) {
            var c = parseFloat(m.lat)
            var d = parseFloat(m.lon)
            if (!isNaN(c) && !isNaN(d)) { lat = c; lon = d }
        }
        root.solarElev = root.solarElevationDeg(lat, lon, new Date())
    }

    // 回到顶部：从当前位置平滑过渡，不做瞬移
    function scrollToTop() {
        if (content.contentY <= 0) return
        scrollTopAnim.stop()
        scrollTopAnim.from = content.contentY
        scrollTopAnim.to = 0
        scrollTopAnim.start()
    }

    // ================= 数据绑定 =================
    function srcLabel(k) {
        var m = { "open-meteo": "Open-Meteo", "chinacom": tr("中国天气网"), "gfs": "GFS",
                  "ecmwf": "ECMWF", "wttr.in": "wttr.in", "qweather": tr("和风天气") }
        return m[k] || k
    }
    function srcColor(k) {
        var dark = { "open-meteo": "#7DD3FC", "chinacom": "#FB7185", "gfs": "#A78BFA",
                     "ecmwf": "#F472B6", "wttr.in": "#34D399", "qweather": "#FBBF24" }
        var light = { "open-meteo": "#1E6FD9", "chinacom": "#C7446E", "gfs": "#7C5CE0",
                      "ecmwf": "#D2458F", "wttr.in": "#0FA36B", "qweather": "#C07A00" }
        var m = root.light ? light : dark
        return m[k] || (root.light ? "#2E4A7A" : "#CFE7FF")
    }
    // AQI 六档分级图例（RichText）：色点始终显示档位色，当前档加粗着色
    function aqiLegendHtml() {
        var lv = (root.wd && root.wd.current && root.wd.current.aqi_info) ? root.wd.current.aqi_info.label : ""
        var items = [[tr("优"), "≤50", "#3ED477"], [tr("良"), "≤100", "#FFD60A"], [tr("轻度"), "≤150", "#FF9F0A"],
                     [tr("中度"), "≤200", "#FF3B30"], [tr("重度"), "≤300", "#BF5AF2"], [tr("严重"), "&gt;300", "#9B2C2C"]]
        var parts = []
        for (var i = 0; i < items.length; i++) {
            var n = items[i][0], r = items[i][1], c = items[i][2]
            var cur = (lv.indexOf(n) === 0)
            var dot = '<font color="' + c + '">●</font>'
            var txt = cur ? ('<font color="' + c + '"><b>' + n + r + '</b></font>') : (n + r)
            parts.push(dot + " " + txt)
        }
        return parts.join("&nbsp;&nbsp;")
    }

    // 当前天气状况 → 实景背景图（苹果天气风格；图标键集见 assets/icons/svg/dark）
    function skyKey() {
        if (!root.wd || !root.wd.current || !root.wd.current.icon) return "sky_clear.jpg"
        var k = root.wd.current.icon
        // 夜间：晴/局部多云 → 夜空；其余（云/雨/雪/雾/雷）→ 夜间多云实景，避免白天场景
        if (root.wd.current.is_day === false) {
            return (k === "night_clear" || k === "clear" || k === "partly" || k === "night_partly")
                   ? "sky_night.jpg" : "sky_night_cloudy.jpg"
        }
        var map = {
            "clear": "sky_clear.jpg",
            "partly": "sky_partly.jpg", "night_partly": "sky_partly.jpg",
            "cloudy": "sky_cloudy.jpg", "overcast": "sky_cloudy.jpg",
            "rain": "sky_rain.jpg", "heavy_rain": "sky_rain.jpg", "showers": "sky_rain.jpg",
            "heavy_showers": "sky_rain.jpg", "drizzle": "sky_rain.jpg", "freezing": "sky_rain.jpg",
            "snow": "sky_snow.jpg", "heavy_snow": "sky_snow.jpg", "snow_showers": "sky_snow.jpg",
            "heavy_snow_showers": "sky_snow.jpg", "snow_grains": "sky_snow.jpg",
            "fog": "sky_fog.jpg",
            "thunder": "sky_thunder.jpg", "thunder_hail": "sky_thunder.jpg",
            "night_clear": "sky_night.jpg"
        }
        return map[k] || "sky_clear.jpg"
    }
    // 深色主题下刷新背景（数据更新 / 主题切换共用）
    function refreshSky() {
        if (root.light) return
        bgImage.opacity = 0
        bgImage.source = "file:///" + res.replace(/\\/g, "/") + "/ui/sky/" + root.skyKey()
        bgFade.start()
        root.touchGlass()
    }

    Connections {
        target: backend
        function onLoadingChanged(v) { root.loading = v }
        function onDataLoaded(d) {
            root.hasData = true
            root.wd = d
            var asked = root.refreshRequested
            var cacheHit = !!(d.meta && d.meta.cache_hit)
            root.refreshRequested = false
            root.pendingQuery = ""
            if (asked) {
                if (cacheHit)
                    root.showToast(tr("缓存数据 · ") + root.fmtUpdated(d.meta) + tr("（后台正在更新）"), "#D9368BFA", 4200)
                else
                    root.showToast(tr("数据已更新 · ") + root.fmtUpdated(d.meta), "#D910B981", 3200)
            }
            if (d.daily && d.daily.length) {
                var mn = 999, mx = -999
                for (var i = 0; i < d.daily.length; i++) {
                    if (d.daily[i].tmin !== null && d.daily[i].tmin < mn) mn = d.daily[i].tmin
                    if (d.daily[i].tmax !== null && d.daily[i].tmax > mx) mx = d.daily[i].tmax
                }
                if (mn !== 999) root.dMin = mn
                if (mx !== -999) root.dMax = mx
            }
        }
        function onErrorOccurred(m) {
            root.refreshFailed = true
            root.refreshRequested = false
            root.pendingQuery = ""
            root.showToast(tr("获取数据失败：") + m, "#D9DC3C3C", 5000)
        }
    }

    Component.onCompleted: {
        // 玻璃采样：滚动跟随 Flickable 内容层（滚动时只更新坐标，不重抓纹理）
        root.glassFollow = content.contentItem
        Qt.callLater(function () { root.touchGlass() })
        // 等首帧渲染完再请求；有缓存时 200ms 内即可上屏，后台再拉新数据
        startupTimer.start()
    }

    // 整窗抓图（含设置/预览等浮层），用于验证第二层界面
    signal grabAllRequested(string path)
    onGrabAllRequested: function (path) {
        var target = root.contentItem || chrome
        target.grabToImage(function (resp) {
            if (resp) {
                if (resp.saveToFile) {
                    resp.saveToFile(path)
                } else if (resp.image) {
                    backend.saveImage(resp.image, path)
                }
            }
        })
    }

    // 供 --screenshot 验证模式调用：离屏抓取整窗图像
    signal grabRequested(string path)
    onGrabRequested: function (path) {
        chrome.grabToImage(function (resp) {
            if (resp) {
                if (resp.saveToFile) {
                    resp.saveToFile(path)
                } else if (resp.image) {
                    backend.saveImage(resp.image, path)
                }
            }
        })
    }

    // 滚到内容底部抓图（验证 15 天预报等下方区域），抓完恢复原位
    signal grabFullRequested(string path)
    onGrabFullRequested: function (path) {
        content.contentY = Math.max(0, col.height - content.height)
        backend.report("y=" + content.contentY + " cH=" + content.contentHeight + " visH=" + content.height)
        chrome.grabToImage(function (resp) {
            if (resp && resp.image) {
                backend.saveImage(resp.image, path)
            }
            content.contentY = 0
        })
    }

    signal grabAtRequested(string path, int y)
    onGrabAtRequested: function (path, y) {
        content.contentY = Math.max(0, Math.min(y, col.height - content.height))
        chrome.grabToImage(function (resp) {
            if (resp && resp.image) {
                backend.saveImage(resp.image, path)
            }
            content.contentY = 0
        })
    }

    // ==================== 设置面板（草稿值 + 保存配置） ====================
    Rectangle {
        id: settingsPanel
        objectName: "settingsPanel"
        anchors.fill: parent
        visible: false
        opacity: 0
        color: "transparent"
        z: 1300

        property bool _open: false
        property bool animPage: false
        property bool dirty: false
        property bool savedFlash: false

        // 草稿值：点击选项只改这里，点“保存配置”才写入磁盘并应用到主界面
        property int refreshMin: 10
        property int alarmMin: 30
        property int timeoutSec: 20
        property string tempUnit: "C"
        property string animLevel: "full"
        property string backupSource: "auto"
        property real hoverBrightness: 1.0
        property string themeDraft: "dark"
        property bool glassFloatDraft: true
        property bool mouseFollowDraft: true
        property string languageDraft: "zh-CN"

        function markDirty() {
            dirty = true
            savedFlash = false
        }

        function open() {
            if (skyPreview.opened) skyPreview.opened = false
            searchField.focus = false
            _open = true
            root.settingsOpen = true
            animPage = false
            dirty = false
            savedFlash = false
            visible = true
            // 读取当前设置（不立即应用到主界面，必须点“保存配置”）
            try {
                var s = JSON.parse(backend.getSettings())
                refreshMin = s.refresh_minutes || 10
                alarmMin = s.alarm_minutes || 30
                timeoutSec = s.timeout_sec || 20
                tempUnit = s.temp_unit || "C"
                animLevel = s.anim_level || "full"
                backupSource = s.backup_source || "auto"
                hoverBrightness = (typeof s.hover_brightness === "number") ? s.hover_brightness : 1.0
                themeDraft = s.theme || "dark"
                glassFloatDraft = s.glass_float !== false
                mouseFollowDraft = s.mouse_follow !== false
                languageDraft = s.language || "zh-CN"
            } catch (e) {
                themeDraft = root.theme
            }
            fadeIn.start()
        }

        function close() {
            _open = false
            root.settingsOpen = false
            fadeOut.start()
        }

        function save() {
            var payload = {
                refresh_minutes: refreshMin,
                alarm_minutes: alarmMin,
                timeout_sec: timeoutSec,
                temp_unit: tempUnit,
                anim_level: animLevel,
                backup_source: backupSource,
                hover_brightness: hoverBrightness,
                theme: themeDraft,
                glass_float: glassFloatDraft,
                mouse_follow: mouseFollowDraft,
                language: languageDraft
            }
            var ok = false
            try { ok = backend.saveSettings(JSON.stringify(payload)) } catch (e) { ok = false }
            if (!ok) {
                root.showToast(tr("保存失败，请重试"), "#D9DC3C3C", 3200)
                return
            }
            // 保存成功后才把草稿应用到主界面
            root.tempUnit = tempUnit
            root.animLevel = animLevel
            root.hoverBrightness = hoverBrightness
            root.glassFloat = glassFloatDraft
            root.mouseFollow = mouseFollowDraft
            root.theme = themeDraft
            if (themeDraft === "dark") root.refreshSky()
            dirty = false
            savedFlash = true
            savedTimer.restart()
            root.showToast(tr("保存成功"), "#D910B981", 2600)
            // 语言变更：界面文案需要整体重建，交给 Python 端延迟执行
            try {
                if (languageDraft !== backend.currentLanguage()) backend.applyLanguage(languageDraft)
            } catch (e) {}
        }

        // 半透明背景遮罩：点击关闭；滚轮与点击都不穿透
        Rectangle {
            anchors.fill: parent
            color: root.tOverlay
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                onClicked: settingsPanel.close()
                onWheel: function (wheel) { wheel.accepted = true }
            }
        }

        // 设置面板本体：直接用液态玻璃卡片，面板本身即为真实玻璃折射
        GlassCard {
            id: settingsBox
            objectName: "settingsBox"
            anchors.centerIn: parent
            width: Math.min(460, root.width - 80)
            height: Math.min(640, root.height - 80)
            radius: 20
            pad: 0
            theme: root.theme
            hoverable: false
            applyOffsetTransform: false
            // 面板比普通卡片略厚一点：保留折射/高光，同时保证文字可读
            tintAlpha: root.light ? 0.28 : 0.55
            transform: Scale {
                id: panelScale
                xScale: 0.94
                yScale: 0.94
                origin.x: settingsBox.width / 2
                origin.y: settingsBox.height / 2
            }

            // 拦截面板内部滚轮
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                onWheel: function (wheel) { wheel.accepted = true }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12

                // 标题栏
                Item {
                    id: settingsHeader
                    width: parent.width
                    height: 32

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/" + (settingsPanel.animPage ? "settings.svg" : "settings.svg")
                            sourceSize: Qt.size(20, 20)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: settingsPanel.animPage ? tr("动画效果") : tr("设置")
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            color: root.tMain
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: settingsPanel.dirty
                            text: tr("有未保存的更改")
                            font.pixelSize: 11
                            color: "#F59E0B"
                        }
                    }
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: root.tGlass
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            anchors.centerIn: parent
                            source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + root.theme + "/close.svg"
                            sourceSize: Qt.size(13, 13)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: settingsPanel.close()
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.tDiv }

                // 内容区可滚动：小窗口下也不会溢出面板
                Flickable {
                    id: settingsFlick
                    objectName: "settingsFlick"
                    width: parent.width
                    height: Math.max(0, settingsBox.height - 44 - 32 - 1 - 42 - 48)
                    contentWidth: width
                    contentHeight: settingsPanel.animPage ? animBody.height : settingsBody.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 3600

                    // ---------- 设置主页面 ----------
                    Column {
                        id: settingsBody
                        visible: !settingsPanel.animPage
                        width: settingsFlick.width
                        spacing: 14

                        // 界面语言（三选一）：名称按各自语言书写，不参与翻译
                        Column {
                            spacing: 8
                            Text { text: tr("界面语言"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: [["zh-CN", "简体中文"], ["zh-TW", "繁體中文"], ["en", "English"]]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.languageDraft === modelData[0]
                                        property bool hov: false
                                        width: 96; height: 32; radius: 16
                                        color: active ? "#6366F1" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#6366F1" : root.tChromeBd
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData[1]
                                            font.pixelSize: 12
                                            color: active ? "#FFFFFF" : root.tMain
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.languageDraft = modelData[0]
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 刷新频率
                        Column {
                            spacing: 8
                            Text { text: tr("天气数据刷新"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: [5, 10, 30, 60]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.refreshMin === modelData
                                        property bool hov: false
                                        width: 84; height: 32; radius: 16
                                        color: active ? "#3B82F6" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#3B82F6" : root.tChromeBd
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Text { anchors.centerIn: parent; text: modelData + tr("分钟"); font.pixelSize: 12; color: active ? "#FFFFFF" : root.tMain }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.refreshMin = modelData
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 预警更新频率
                        Column {
                            spacing: 8
                            Text { text: tr("预警信息更新"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: [10, 30, 60]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.alarmMin === modelData
                                        property bool hov: false
                                        width: 84; height: 32; radius: 16
                                        color: active ? "#F59E0B" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#F59E0B" : root.tChromeBd
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Text { anchors.centerIn: parent; text: modelData + tr("分钟"); font.pixelSize: 12; color: active ? "#FFFFFF" : root.tMain }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.alarmMin = modelData
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 连接超时
                        Column {
                            spacing: 8
                            Text { text: tr("网络连接超时"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: [10, 15, 20, 30]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.timeoutSec === modelData
                                        property bool hov: false
                                        width: 76; height: 32; radius: 16
                                        color: active ? "#10B981" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#10B981" : root.tChromeBd
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Text { anchors.centerIn: parent; text: modelData + tr("秒"); font.pixelSize: 12; color: active ? "#FFFFFF" : root.tMain }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.timeoutSec = modelData
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 温度单位
                        Column {
                            spacing: 8
                            Text { text: tr("温度单位"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: ["C", "F"]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.tempUnit === modelData
                                        property bool hov: false
                                        width: 100; height: 32; radius: 16
                                        color: active ? "#8B5CF6" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#8B5CF6" : root.tChromeBd
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Text { anchors.centerIn: parent; text: modelData === "C" ? tr("摄氏度 °C") : tr("华氏度 °F"); font.pixelSize: 12; color: active ? "#FFFFFF" : root.tMain }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.tempUnit = modelData
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 动画效果（二级页面入口）
                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 14
                            color: animEntryArea.hov ? root.tGlassH : root.tGlass
                            border.width: 1
                            border.color: root.tChromeBd
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Text { anchors.verticalCenter: parent.verticalCenter; text: tr("动画效果"); font.pixelSize: 13; color: root.tMain }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: tr("玻璃浮动 · 鼠标跟随 · 亮度"); font.pixelSize: 11; color: root.tSub3 }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"
                                font.pixelSize: 20
                                color: root.tSub2
                            }
                            MouseArea {
                                id: animEntryArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: settingsPanel.animPage = true
                            }
                        }

                        // 备用数据源
                        Column {
                            spacing: 8
                            Text { text: tr("连接失败备用源"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: ["auto", "wttr", "chinacom"]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.backupSource === modelData
                                        property bool hov: false
                                        width: 100; height: 32; radius: 16
                                        color: active ? "#10B981" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#10B981" : root.tChromeBd
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData === "auto" ? tr("自动") : (modelData === "wttr" ? "wttr.in" : tr("中国天气网"))
                                            font.pixelSize: 12
                                            color: active ? "#FFFFFF" : root.tMain
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.backupSource = modelData
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 主题（同样纳入保存流程）
                        Column {
                            spacing: 8
                            Text { text: tr("外观主题"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: ["dark", "light"]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.themeDraft === modelData
                                        property bool hov: false
                                        width: 100; height: 36; radius: 18
                                        color: active ? "#3B82F6" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#3B82F6" : root.tChromeBd
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Text { anchors.centerIn: parent; text: modelData === "dark" ? tr("深色") : tr("浅色"); font.pixelSize: 12; color: active ? "#FFFFFF" : root.tMain }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.themeDraft = modelData
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: root.tDiv }

                        Text {
                            text: tr("软件介绍")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: root.tMain
                        }
                        Text {
                            text: tr("天气是一款桌面端天气应用，以 PySide6 + QML 构建界面，将多个公开气象数据源的结果并行获取后加权融合，输出温度、体感、降水相态、空气质量与 15 日预报，并在界面背景中呈现与当前天气、光照时段一致的实景画面。")
                            width: parent.width
                            wrapMode: Text.WordWrap
                            lineHeight: 1.5
                            font.pixelSize: 12
                            color: root.tSub1
                        }
                        Rectangle { width: parent.width; height: 1; color: root.tDiv }
                        Text {
                            text: tr("天气 v13 · 数据来自 Open-Meteo / 中国天气网 / 中央气象台\n预警：蓝黄橙红四级 · 每 30 分钟更新")
                            width: parent.width
                            font.pixelSize: 11
                            color: root.tSub4
                            wrapMode: Text.Wrap
                        }
                        Item { width: 1; height: 4 }
                    }

                    // ---------- 动画效果二级页面 ----------
                    Column {
                        id: animBody
                        visible: settingsPanel.animPage
                        width: settingsFlick.width
                        spacing: 16

                        Rectangle {
                            width: parent.width
                            height: 38
                            radius: 14
                            border.width: 1
                            border.color: root.tChromeBdH
                            scale: backArea.hov ? 1.02 : 1.0
                            gradient: Gradient {
                                GradientStop { position: 0; color: backArea.hov ? (root.light ? "#A6FFFFFF" : "#42FFFFFF") : (root.light ? "#7AFFFFFF" : "#2EFFFFFF") }
                                GradientStop { position: 1; color: root.light ? "#3CFFFFFF" : "#12FFFFFF" }
                            }
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            // 内缘高光：液态玻璃的“厚度切面”
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 13
                                color: "transparent"
                                border.width: 1
                                border.color: root.light ? "#80FFFFFF" : "#28FFFFFF"
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: tr("‹ 返回设置")
                                font.pixelSize: 13
                                color: root.tMain
                            }
                            MouseArea {
                                id: backArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: settingsPanel.animPage = false
                            }
                        }

                        // 液态玻璃设计说明
                        Rectangle {
                            width: parent.width
                            radius: 14
                            color: root.light ? "#8CDCEBFF" : "#663B82F6"
                            border.width: 1
                            border.color: root.light ? "#6A1E6FD9" : "#7DD3FC"
                            height: glassInfo.implicitHeight + 24
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 13
                                color: "transparent"
                                border.width: 1
                                border.color: root.light ? "#80FFFFFF" : "#3AFFFFFF"
                            }
                            Column {
                                id: glassInfo
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 12
                                spacing: 6
                                Text { text: tr("液态玻璃设计"); font.pixelSize: 13; font.weight: Font.DemiBold; color: root.tMain }
                                Text {
                                    text: tr("玻璃卡片采用圆角折射、边缘高光与局部镜面光斑；面板内所有按钮均为液态玻璃质感。动画参数在下方调节，点击“保存配置”后生效。")
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.4
                                    font.pixelSize: 11
                                    color: root.tSub1
                                }
                            }
                        }

                        // 是否启用玻璃浮动
                        Rectangle {
                            width: parent.width
                            height: 46
                            radius: 14
                            border.width: 1
                            border.color: root.tChromeBdH
                            gradient: Gradient {
                                GradientStop { position: 0; color: root.light ? "#6EFFFFFF" : "#2AFFFFFF" }
                                GradientStop { position: 1; color: root.light ? "#38FFFFFF" : "#10FFFFFF" }
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 13
                                color: "transparent"
                                border.width: 1
                                border.color: root.light ? "#70FFFFFF" : "#24FFFFFF"
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: tr("是否启用玻璃浮动")
                                font.pixelSize: 13
                                color: root.tMain
                            }
                            Rectangle {
                                id: floatSwitch
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 46
                                height: 26
                                radius: 13
                                color: settingsPanel.glassFloatDraft ? "#CC3B82F6" : (root.light ? "#9AA7B8" : "#9955637E")
                                border.width: 1
                                border.color: settingsPanel.glassFloatDraft ? "#B37DD3FC" : root.tChromeBdH
                                Behavior on color { ColorAnimation { duration: 180 } }
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: 12
                                    color: "transparent"
                                    border.width: 1
                                    border.color: "#40FFFFFF"
                                }
                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    x: settingsPanel.glassFloatDraft ? 23 : 3
                                    y: 3
                                    color: "#F5FAFF"
                                    border.width: 1
                                    border.color: "#FFFFFF"
                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        settingsPanel.glassFloatDraft = !settingsPanel.glassFloatDraft
                                        settingsPanel.markDirty()
                                    }
                                }
                            }
                        }

                        // 鼠标跟随
                        Rectangle {
                            width: parent.width
                            height: 46
                            radius: 14
                            border.width: 1
                            border.color: root.tChromeBdH
                            gradient: Gradient {
                                GradientStop { position: 0; color: root.light ? "#6EFFFFFF" : "#2AFFFFFF" }
                                GradientStop { position: 1; color: root.light ? "#38FFFFFF" : "#10FFFFFF" }
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 13
                                color: "transparent"
                                border.width: 1
                                border.color: root.light ? "#70FFFFFF" : "#24FFFFFF"
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: tr("鼠标跟随")
                                font.pixelSize: 13
                                color: root.tMain
                            }
                            Rectangle {
                                id: followSwitch
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 46
                                height: 26
                                radius: 13
                                color: settingsPanel.mouseFollowDraft ? "#CC3B82F6" : (root.light ? "#9AA7B8" : "#9955637E")
                                border.width: 1
                                border.color: settingsPanel.mouseFollowDraft ? "#B37DD3FC" : root.tChromeBdH
                                Behavior on color { ColorAnimation { duration: 180 } }
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: 12
                                    color: "transparent"
                                    border.width: 1
                                    border.color: "#40FFFFFF"
                                }
                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    x: settingsPanel.mouseFollowDraft ? 23 : 3
                                    y: 3
                                    color: "#F5FAFF"
                                    border.width: 1
                                    border.color: "#FFFFFF"
                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        settingsPanel.mouseFollowDraft = !settingsPanel.mouseFollowDraft
                                        settingsPanel.markDirty()
                                    }
                                }
                            }
                        }

                        // 鼠标跟随亮度：无极调节
                        Column {
                            width: animBody.width
                            spacing: 8
                            opacity: settingsPanel.mouseFollowDraft ? 1.0 : 0.45
                            Item {
                                width: parent.width
                                height: 18
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tr("鼠标跟随亮度")
                                    font.pixelSize: 13
                                    color: root.tSub1
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(settingsPanel.hoverBrightness * 100) + "%"
                                    font.pixelSize: 12
                                    color: root.tSub2
                                }
                            }
                            Slider {
                                id: brightnessSlider
                                width: parent.width
                                from: 0.0
                                to: 2.0
                                stepSize: 0.01
                                value: settingsPanel.hoverBrightness
                                enabled: settingsPanel.mouseFollowDraft
                                // 液态玻璃滑块：半透明玻璃轨道 + 玻璃握柄
                                background: Rectangle {
                                    x: brightnessSlider.leftPadding
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                    width: brightnessSlider.availableWidth
                                    height: 6
                                    radius: 3
                                    color: root.light ? "#3C1C2B4A" : "#3AFFFFFF"
                                    border.width: 1
                                    border.color: root.tChromeBdH
                                    Rectangle {
                                        width: brightnessSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 3
                                        color: "#C03B82F6"
                                    }
                                }
                                handle: Rectangle {
                                    x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * brightnessSlider.availableWidth - width / 2
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: "#F5FAFF"
                                    border.width: 1
                                    border.color: "#FFFFFF"
                                }
                                onValueChanged: {
                                    if (value === settingsPanel.hoverBrightness) return
                                    settingsPanel.hoverBrightness = value
                                    settingsPanel.markDirty()
                                }
                            }
                        }

                        // 整体动画强度
                        Column {
                            spacing: 8
                            Text { text: tr("整体动画强度"); font.pixelSize: 13; color: root.tSub1 }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: ["full", "simple", "off"]
                                    delegate: Rectangle {
                                        property bool active: settingsPanel.animLevel === modelData
                                        property bool hov: false
                                        width: 100; height: 32; radius: 16
                                        color: active ? "#CCEC4899" : (hov ? root.tGlassH : root.tGlass)
                                        border.width: 1
                                        border.color: active ? "#F9A8D4" : root.tChromeBdH
                                        scale: hov ? 1.04 : 1.0
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            radius: 15
                                            color: "transparent"
                                            border.width: 1
                                            border.color: active ? "#80FFFFFF" : (root.light ? "#70FFFFFF" : "#24FFFFFF")
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData === "full" ? tr("完整") : (modelData === "simple" ? tr("简化") : tr("关闭"))
                                            font.pixelSize: 12
                                            color: active ? "#FFFFFF" : root.tMain
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: parent.hov = true
                                            onExited: parent.hov = false
                                            onClicked: {
                                                settingsPanel.animLevel = modelData
                                                settingsPanel.markDirty()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Item { width: 1; height: 4 }
                    }
                }

                // 底部保存栏：统一提交草稿值
                Rectangle {
                    id: saveFooter
                    width: parent.width
                    height: 42
                    color: "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: settingsPanel.savedFlash ? tr("✓ 保存成功") : (settingsPanel.dirty ? tr("● 有未保存的更改") : "")
                        font.pixelSize: 12
                        color: settingsPanel.savedFlash ? "#34D399" : "#F59E0B"
                    }
                    Rectangle {
                        id: saveBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 118
                        height: 36
                        radius: 18
                        border.width: 1
                        border.color: "#8FD8FF"
                        scale: saveArea.hov ? 1.03 : 1.0
                        gradient: Gradient {
                            GradientStop { position: 0; color: saveArea.hov ? "#E660A5FA" : "#CC3B82F6" }
                            GradientStop { position: 1; color: saveArea.hov ? "#CC2563EB" : "#992561EB" }
                        }
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 17
                            color: "transparent"
                            border.width: 1
                            border.color: "#66FFFFFF"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: tr("保存配置")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: "#FFFFFF"
                        }
                        MouseArea {
                            id: saveArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: settingsPanel.save()
                        }
                        TipBubble { text: tr("保存后生效"); hovered: saveArea.containsMouse; theme: root.theme }
                    }
                    Timer {
                        id: savedTimer
                        interval: 2400
                        repeat: false
                        onTriggered: settingsPanel.savedFlash = false
                    }
                }
            }
        }

        SequentialAnimation {
            id: fadeIn
            PropertyAction { target: settingsPanel; property: "visible"; value: true }
            NumberAnimation { target: settingsPanel; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            PropertyAction { target: panelScale; property: "xScale"; value: 1 }
            PropertyAction { target: panelScale; property: "yScale"; value: 1 }
        }
        SequentialAnimation {
            id: fadeOut
            NumberAnimation { target: settingsPanel; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
            PropertyAction { target: settingsPanel; property: "visible"; value: false }
        }
    }
}
