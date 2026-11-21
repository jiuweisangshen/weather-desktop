import QtQuick 2.15

// 月相卡片（Apple 天气风格）
//   · 真实月面：按当前月相用 Canvas 绘制明暗交界线（半圆 + 半椭圆），带环形山/月海质感
//   · 数据：月相名称、照射比例、月龄、月出/月落（按当前经纬度做高度角搜索）
//   · 独立组件，避免 main.qml 继续膨胀
GlassCard {
    id: card
    property var wd: ({})
    property int _tick: 0

    // 多语言：文案统一走 tr("简体原文")，由 Python 词典翻译
    function tr(text) {
        try { return backend.translate(text) } catch (e) { return text }
    }

    // 依赖 _tick 与 wd：数据更新或每 30 分钟重新计算
    property var info: {
        var _t = card._tick
        var _w = card.wd
        return card.computeInfo()
    }

    height: 140
    pad: 20
    radius: 24
    hoverable: true

    readonly property real synodic: 29.530588853
    readonly property real newMoonRef: 2451550.26   // 2000-01-06 18:14 UTC 新月

    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: true
        onTriggered: card._tick++
    }

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n
    }

    function phaseOf(jd) {
        var p = ((jd - card.newMoonRef) % card.synodic) / card.synodic
        if (p < 0) p += 1
        return p
    }

    function phaseName(p) {
        if (p < 0.0625 || p >= 0.9375) return tr("新月")
        if (p < 0.1875) return tr("蛾眉月")
        if (p < 0.3125) return tr("上弦月")
        if (p < 0.4375) return tr("盈凸月")
        if (p < 0.5625) return tr("满月")
        if (p < 0.6875) return tr("亏凸月")
        if (p < 0.8125) return tr("下弦月")
        return tr("残月")
    }

    // 低精度月球位置（Meeus 简化式，误差约 0.1°），返回黄经/黄纬（度）
    function moonPosition(jd) {
        var T = (jd - 2451545.0) / 36525.0
        var rad = Math.PI / 180.0
        var Lp = 218.3164477 + 481267.88123421 * T - 0.0015786 * T * T
                 + T * T * T / 538841 - T * T * T * T / 65194000
        var D = 297.8501921 + 445267.1114034 * T - 0.0018819 * T * T
                + T * T * T / 545868 - T * T * T * T / 113065000
        var M = 357.5291092 + 35999.0502909 * T - 0.0001536 * T * T
                + T * T * T / 24490000
        var Mp = 134.9633964 + 477198.8675055 * T + 0.0087414 * T * T
                 + T * T * T / 69699 - T * T * T * T / 14712000
        var F = 93.2720950 + 483202.0175233 * T - 0.0036539 * T * T
                - T * T * T / 3526000 + T * T * T * T / 863310000

        var lon = Lp
                + 6.289 * Math.sin(Mp * rad)
                + 1.274 * Math.sin((2 * D - Mp) * rad)
                + 0.658 * Math.sin(2 * D * rad)
                + 0.214 * Math.sin(2 * Mp * rad)
                - 0.186 * Math.sin(M * rad)
                - 0.114 * Math.sin(2 * F * rad)
                + 0.059 * Math.sin((2 * D - 2 * Mp) * rad)
                + 0.057 * Math.sin((2 * D - M - Mp) * rad)
                + 0.053 * Math.sin((2 * D + Mp) * rad)
                + 0.046 * Math.sin((2 * D - M) * rad)
                + 0.041 * Math.sin((M - Mp) * rad)
                - 0.035 * Math.sin(D * rad)
                - 0.031 * Math.sin((M + Mp) * rad)
                - 0.015 * Math.sin((2 * F - 2 * D) * rad)
                + 0.011 * Math.sin((Mp - 4 * D) * rad)

        var lat = 5.128 * Math.sin(F * rad)
                + 0.280 * Math.sin((Mp + F) * rad)
                + 0.277 * Math.sin((Mp - F) * rad)
                + 0.173 * Math.sin((2 * D - F) * rad)
                + 0.055 * Math.sin((2 * D - Mp + F) * rad)
                + 0.046 * Math.sin((2 * D - Mp - F) * rad)
                + 0.033 * Math.sin((2 * D + F) * rad)
                + 0.017 * Math.sin((2 * Mp + F) * rad)
        return { lon: lon, lat: lat }
    }

    // 月球在地平线上的几何高度角（度），含赤经赤纬与地方恒星时换算
    function moonAltitude(date, lat, lon) {
        var rad = Math.PI / 180.0
        var jd = date.getTime() / 86400000.0 + 2440587.5
        var T = (jd - 2451545.0) / 36525.0
        var pos = card.moonPosition(jd)
        var lam = pos.lon * rad
        var beta = pos.lat * rad
        var eps = (23.4392911 - 0.0130042 * T) * rad

        var ra = Math.atan2(Math.sin(lam) * Math.cos(eps) - Math.tan(beta) * Math.sin(eps),
                            Math.cos(lam))
        var dec = Math.asin(Math.sin(beta) * Math.cos(eps)
                            + Math.cos(beta) * Math.sin(eps) * Math.sin(lam))

        var theta = 280.46061837 + 360.98564736629 * (jd - 2451545.0)
                    + 0.000387933 * T * T - T * T * T / 38710000.0
        var H = (theta + lon - ra / rad) * rad
        var phi = lat * rad
        var alt = Math.asin(Math.sin(phi) * Math.sin(dec)
                            + Math.cos(phi) * Math.cos(dec) * Math.cos(H))
        return alt / rad
    }

    // 当天月出/月落：10 分钟步长搜索高度角穿过 +0.125° 的时刻
    function riseSet(lat, lon) {
        var now = new Date()
        var start = new Date(now.getFullYear(), now.getMonth(), now.getDate(),
                             0, 0, 0, 0).getTime()
        var step = 10 * 60 * 1000
        var prev = null
        var rise = null
        var set = null
        for (var i = 0; i <= 144; i++) {
            var t = start + i * step
            var alt = card.moonAltitude(new Date(t), lat, lon)
            if (prev !== null) {
                if (prev < 0.125 && alt >= 0.125 && rise === null)
                    rise = t - step + step * (0.125 - prev) / (alt - prev)
                if (prev >= 0.125 && alt < 0.125 && set === null)
                    set = t - step + step * (prev - 0.125) / (prev - alt)
            }
            prev = alt
        }
        return { rise: rise, set: set }
    }

    function fmtTime(ms) {
        if (ms === null) return "--:--"
        var d = new Date(ms)
        return card.pad2(d.getHours()) + ":" + card.pad2(d.getMinutes())
    }

    function computeInfo() {
        var now = new Date()
        var jd = now.getTime() / 86400000.0 + 2440587.5
        var p = card.phaseOf(jd)
        var illum = (1 - Math.cos(p * 2 * Math.PI)) / 2

        var lat = 39.9042
        var lon = 116.4074
        var loc = card.wd && card.wd.location ? card.wd.location : null
        if (loc) {
            var a = parseFloat(loc.lat)
            var b = parseFloat(loc.lon)
            if (!isNaN(a) && !isNaN(b)) { lat = a; lon = b }
        }

        var rs = card.riseSet(lat, lon)
        var toFull = p <= 0.5 ? (0.5 - p) * card.synodic
                              : (1.5 - p) * card.synodic
        return {
            phase: p,
            name: card.phaseName(p),
            illum: Math.round(illum * 100),
            age: Math.round(p * card.synodic * 10) / 10,
            toFull: Math.round(toFull * 10) / 10,
            rise: card.fmtTime(rs.rise),
            set: card.fmtTime(rs.set)
        }
    }

    // ==================== 月面绘制 ====================
    function paintMoon(ctx, w, h) {
        ctx.clearRect(0, 0, w, h)
        var R = Math.min(w, h) / 2 - 8
        var cx = w / 2
        var cy = h / 2
        var p = (card.info && card.info.phase !== undefined) ? card.info.phase : 0

        // 外圈冷光
        var glow = ctx.createRadialGradient(cx, cy, R * 0.78, cx, cy, R * 1.30)
        glow.addColorStop(0.0, "rgba(196, 218, 255, 0.26)")
        glow.addColorStop(0.55, "rgba(160, 192, 255, 0.10)")
        glow.addColorStop(1.0, "rgba(120, 160, 255, 0)")
        ctx.fillStyle = glow
        ctx.beginPath()
        ctx.arc(cx, cy, R * 1.32, 0, Math.PI * 2)
        ctx.fill()

        // 暗面（地球反照）
        var dark = ctx.createRadialGradient(cx - R * 0.25, cy - R * 0.30, R * 0.05,
                                            cx, cy, R * 1.02)
        dark.addColorStop(0.0, "#1C2946")
        dark.addColorStop(0.65, "#111B32")
        dark.addColorStop(1.0, "#0A1224")
        ctx.beginPath()
        ctx.arc(cx, cy, R, 0, Math.PI * 2)
        ctx.fillStyle = dark
        ctx.fill()

        // 明暗交界线：半圆（右缘）+ 半椭圆（晨昏线）
        var waxing = p <= 0.5
        var pp = waxing ? p : 1 - p
        var rx = R * Math.cos(pp * 2 * Math.PI)

        ctx.save()
        if (!waxing) {
            ctx.translate(cx, cy)
            ctx.scale(-1, 1)
            ctx.translate(-cx, -cy)
        }

        ctx.beginPath()
        ctx.arc(cx, cy, R, -Math.PI / 2, Math.PI / 2, false)
        var k = 0.5522847498
        if (Math.abs(rx) < 0.6) {
            ctx.lineTo(cx, cy - R)
        } else if (rx > 0) {
            ctx.bezierCurveTo(cx + rx * k, cy + R, cx + rx, cy + R * k, cx + rx, cy)
            ctx.bezierCurveTo(cx + rx, cy - R * k, cx + rx * k, cy - R, cx, cy - R)
        } else {
            var ax = -rx
            ctx.bezierCurveTo(cx - ax * k, cy + R, cx - ax, cy + R * k, cx - ax, cy)
            ctx.bezierCurveTo(cx - ax, cy - R * k, cx - ax * k, cy - R, cx, cy - R)
        }
        ctx.closePath()

        var lit = ctx.createLinearGradient(cx - R * 0.55, cy - R * 0.70,
                                           cx + R * 0.60, cy + R * 0.85)
        lit.addColorStop(0.0, "#FCFDFF")
        lit.addColorStop(0.45, "#E8EEF8")
        lit.addColorStop(1.0, "#B7C6DD")
        ctx.fillStyle = lit
        ctx.fill()

        // 只在亮面绘制月海与环形山
        ctx.clip()

        var maria = [
            [-0.30, -0.16, 0.36, 0.25, "rgba(118, 136, 166, 0.17)"],
            [ 0.18,  0.12, 0.30, 0.21, "rgba(118, 136, 166, 0.15)"],
            [-0.04,  0.36, 0.24, 0.17, "rgba(124, 142, 170, 0.13)"],
            [ 0.34, -0.30, 0.19, 0.15, "rgba(120, 138, 168, 0.12)"]
        ]
        for (var i = 0; i < maria.length; i++) {
            var m = maria[i]
            ctx.save()
            ctx.translate(cx + m[0] * R, cy + m[1] * R)
            ctx.scale(m[2], m[3])
            ctx.beginPath()
            ctx.arc(0, 0, R, 0, Math.PI * 2)
            ctx.restore()
            ctx.fillStyle = m[4]
            ctx.fill()
        }

        var craters = [
            [-0.44,  0.06, 0.045],
            [ 0.08, -0.46, 0.036],
            [ 0.30,  0.34, 0.052],
            [-0.20, -0.36, 0.030],
            [ 0.44, -0.08, 0.028],
            [-0.30,  0.44, 0.026],
            [ 0.02,  0.16, 0.022],
            [ 0.38,  0.14, 0.020],
            [-0.52, -0.16, 0.018]
        ]
        for (var j = 0; j < craters.length; j++) {
            var c = craters[j]
            var cr = c[2] * R
            ctx.beginPath()
            ctx.arc(cx + c[0] * R, cy + c[1] * R, cr, 0, Math.PI * 2)
            ctx.fillStyle = "rgba(96, 114, 142, 0.18)"
            ctx.fill()
            ctx.beginPath()
            ctx.arc(cx + c[0] * R - cr * 0.25, cy + c[1] * R - cr * 0.28,
                    cr * 0.68, 0, Math.PI * 2)
            ctx.fillStyle = "rgba(255, 255, 255, 0.11)"
            ctx.fill()
        }

        // 球面明暗：边缘压暗，左上提亮
        var shade = ctx.createRadialGradient(cx - R * 0.38, cy - R * 0.42, R * 0.08,
                                             cx, cy, R * 1.06)
        shade.addColorStop(0.0, "rgba(255, 255, 255, 0)")
        shade.addColorStop(0.68, "rgba(150, 168, 198, 0.05)")
        shade.addColorStop(1.0, "rgba(18, 28, 50, 0.40)")
        ctx.fillStyle = shade
        ctx.fillRect(cx - R, cy - R, R * 2, R * 2)

        ctx.restore()
    }

    // ==================== 界面 ====================
    Row {
        anchors.fill: parent
        spacing: 20

        Item {
            width: 110
            height: 110
            anchors.verticalCenter: parent.verticalCenter

            Canvas {
                id: moonCanvas
                anchors.fill: parent
                antialiasing: true
                renderTarget: Canvas.Image
                onPaint: {
                    var ctx = getContext("2d")
                    card.paintMoon(ctx, width, height)
                }
                Connections {
                    target: card
                    function onInfoChanged() { moonCanvas.requestPaint() }
                }
                Component.onCompleted: requestPaint()
            }
        }

        Column {
            width: parent.width - 110 - 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                text: tr("月相")
                font.pixelSize: 10
                font.letterSpacing: 1.2
                color: card.lt ? "#8C1C2B4A" : "#A6FFFFFF"
            }
            Row {
                spacing: 10
                Text {
                    text: card.info.name
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    color: card.lt ? "#1C2B4A" : "#FFFFFF"
                }
                Rectangle {
                    visible: card.info.illum >= 99
                    width: 40
                    height: 18
                    radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: card.lt ? "#1A1E6FD9" : "#268FE3FF"
                    Text {
                        anchors.centerIn: parent
                        text: tr("满月")
                        font.pixelSize: 9
                        color: card.lt ? "#1E6FD9" : "#BFE9FF"
                    }
                }
            }
            Text {
                text: tr("照射范围 ") + card.info.illum + tr("%   ·   月龄 ") + card.info.age + tr(" 天")
                font.pixelSize: 12
                color: card.lt ? "#991C2B4A" : "#B3FFFFFF"
            }
            Row {
                spacing: 20
                Row {
                    spacing: 5
                    Text { text: tr("月出"); font.pixelSize: 12; color: card.lt ? "#731C2B4A" : "#8CFFFFFF" }
                    Text { text: card.info.rise; font.pixelSize: 12; color: card.lt ? "#1C2B4A" : "#E6FFFFFF" }
                }
                Row {
                    spacing: 5
                    Text { text: tr("月落"); font.pixelSize: 12; color: card.lt ? "#731C2B4A" : "#8CFFFFFF" }
                    Text { text: card.info.set; font.pixelSize: 12; color: card.lt ? "#1C2B4A" : "#E6FFFFFF" }
                }
            }
            Text {
                text: card.info.toFull < 0.5
                      ? tr("今天是满月")
                      : tr("距满月 ") + Math.ceil(card.info.toFull) + tr(" 天")
                font.pixelSize: 11
                color: card.lt ? "#731C2B4A" : "#8CFFFFFF"
            }
        }
    }
}
