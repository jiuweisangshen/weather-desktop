import QtQuick 2.15

// 逐小时卡片（横向滑动）
GlassCard {
    id: ht
    property var item: ({})
    property string theme: "dark"
    property bool useF: false
    readonly property bool lt: ht.theme === "light"

    // 多语言：文案统一走 tr("简体原文")，由 Python 词典翻译
    function tr(text) {
        try { return backend.translate(text) } catch (e) { return text }
    }

    function conv(v) {
        if (v === null || v === undefined || v === "") return null
        var n = parseFloat(v)
        if (isNaN(n)) return null
        return ht.useF ? n * 9 / 5 + 32 : n
    }
    function fmt(v) {
        var n = ht.conv(v)
        if (n === null) return "--"
        var s = n.toFixed(1)
        if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "")
        return s
    }

    // 202 → 214：内边距 12 后内容区 190，两列信息（178）两侧各留 6px，
    // 避免数字位数多时（如 27.4km/h）文字顶到卡片描边、看起来"溢出卡外"
    width: 214
    height: 218
    pad: 12
    radius: 18

    Column {
        anchors.fill: parent
        spacing: 2

        Text {
            text: ht.item.time ? ht.item.time : "--:--"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: ht.lt ? "#D91C2B4A" : "#D9FFFFFF"
        }
        WeatherIcon {
            key: ht.item.icon ? ht.item.icon : "cloudy"
            size: 34
            theme: ht.theme
        }
        Text {
            text: ht.fmt(ht.item.temp) === "--" ? "--°" : ht.fmt(ht.item.temp) + "°"
            font.pixelSize: 22
            font.weight: Font.DemiBold
            color: ht.lt ? "#1C2B4A" : "#FFFFFF"
        }
        Text {
            text: ht.fmt(ht.item.feels) === "--" ? tr("体感 --") : tr("体感 ") + ht.fmt(ht.item.feels) + "°"
            font.pixelSize: 12
            color: ht.lt ? "#991C2B4A" : "#B3FFFFFF"
        }
        Rectangle {
            width: parent.width
            height: 1
            color: ht.lt ? "#1F1C2B4A" : "#1FFFFFFF"
        }

        Grid {
            columns: 2
            columnSpacing: 6
            rowSpacing: 3

            Repeater {
                model: [
                    { l: ht.item.wind_dir ? ht.item.wind_dir.substr(0, 2) : tr("风"), v: (ht.item.wind === null || ht.item.wind === undefined) ? "--" : ht.item.wind + "km/h" },
                    { l: tr("阵风"), v: (ht.item.gust === null || ht.item.gust === undefined) ? "--" : ht.item.gust + "km/h" },
                    { l: "UV", v: (ht.item.uv === null || ht.item.uv === undefined) ? "--" : ht.item.uv },
                    { l: tr("降水"), v: (ht.item.precip === null || ht.item.precip === undefined) ? "--" : ht.item.precip + "mm" },
                    { l: tr("概率"), v: (ht.item.prob === null || ht.item.prob === undefined) ? "--" : ht.item.prob + "%" },
                    { l: tr("湿度"), v: (ht.item.humidity === null || ht.item.humidity === undefined) ? "--" : ht.item.humidity + "%" },
                    { l: tr("气压"), v: (ht.item.pressure === null || ht.item.pressure === undefined) ? "--" : ht.item.pressure },
                    { l: tr("能见度"), v: (ht.item.vis === null || ht.item.vis === undefined) ? "--" : ht.item.vis + "km" }
                ]
                Row {
                    width: 86
                    spacing: 3
                    Text {
                        text: modelData.l
                        font.pixelSize: 11
                        color: ht.lt ? "#8C1C2B4A" : "#A6FFFFFF"
                        width: 33
                    }
                    Text {
                        text: modelData.v
                        font.pixelSize: 11
                        color: ht.lt ? "#1C2B4A" : "#FFFFFF"
                        elide: Text.ElideRight
                        width: 50
                    }
                }
            }
        }
    }
}
