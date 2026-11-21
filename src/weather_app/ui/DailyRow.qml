import QtQuick 2.15

// 15 天预报行：星期 + 图标 + 描述 + 降水概率 + 温度区间条 + 日出日落
Item {
    id: dr
    property var item: ({})
    property real barMin: 0
    property real barMax: 40
    property string theme: "dark"
    property bool useF: false
    readonly property bool lt: dr.theme === "light"
    readonly property color cMain: dr.lt ? "#1C2B4A" : "#FFFFFF"
    readonly property color cSub2: dr.lt ? "#8C1C2B4A" : "#A6FFFFFF"
    readonly property color cDesc: dr.lt ? "#D11C2B4A" : "#D1FFFFFF"
    readonly property color cProb: dr.lt ? "#BF1C2B4A" : "#BFFFFFFF"
    readonly property color cTempL: dr.lt ? "#D91C2B4A" : "#D9FFFFFF"
    readonly property color cSun: dr.lt ? "#A61C2B4A" : "#B8FFFFFF"
    readonly property color cTrack: dr.lt ? "#1F1C2B4A" : "#1FFFFFFF"

    function conv(v) {
        if (v === null || v === undefined || v === "") return null
        var n = parseFloat(v)
        if (isNaN(n)) return null
        return dr.useF ? n * 9 / 5 + 32 : n
    }
    function fmt(v) {
        var n = dr.conv(v)
        if (n === null) return "--"
        var s = n.toFixed(1)
        if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "")
        return s
    }

    width: parent.width
    height: 54

    // 星期 / 日期
    Column {
        x: 0
        width: 104
        spacing: 1
        anchors.verticalCenter: parent.verticalCenter
        Text {
            text: dr.item.weekday ? dr.item.weekday : "--"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: dr.cMain
        }
        Text {
            text: dr.item.date_cn ? dr.item.date_cn : ""
            font.pixelSize: 11
            color: dr.cSub2
        }
    }

    // 天气图标
    Item {
        x: 114
        width: 34
        anchors.verticalCenter: parent.verticalCenter
        WeatherIcon {
            key: dr.item.icon ? dr.item.icon : "cloudy"
            size: 32
            theme: dr.theme
            anchors.centerIn: parent
        }
    }

    // 描述
    Text {
        x: 158
        width: 74
        text: dr.item.desc ? dr.item.desc : "--"
        font.pixelSize: 13
        color: dr.cDesc
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }

    // 降水概率
    Item {
        x: 242
        width: 58
        anchors.verticalCenter: parent.verticalCenter
        Row {
            anchors.centerIn: parent
            spacing: 4
            Image {
                source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + dr.theme + "/precip.svg"
                sourceSize: Qt.size(14, 14)
                anchors.verticalCenter: parent.verticalCenter
                opacity: 0.85
            }
            Text {
                text: (dr.item.prob === null || dr.item.prob === undefined) ? "--%" : dr.item.prob + "%"
                font.pixelSize: 12
                color: dr.cProb
            }
        }
    }

    // 温度区间条（绑定式：数据 / barMin / barMax / 窗口缩放变化自动重算；数字紧贴条两端）
    Item {
        id: barBox
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 310
        anchors.rightMargin: 128

        // 左右各留 34px 给温度数字，避免数字压到温度条
        Item {
            id: trackBox
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 34
            anchors.rightMargin: 34
            height: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: dr.cTrack

                Rectangle {
                    id: bar
                    height: 6
                    radius: 3
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: dr.lt ? "#2E6FC4" : "#4FB3FF" }
                        GradientStop { position: 1.0; color: dr.lt ? "#C07A00" : "#FFB800" }
                    }
                    // 绑定式计算：trackBox.width / tmin / tmax / barMin / barMax 任一变化自动重算
                    readonly property var _tmin: dr.conv(dr.item.tmin)
                    readonly property var _tmax: dr.conv(dr.item.tmax)
                    readonly property real _span: (barMax - barMin) || 1
                    x: {
                        if (_tmin === null || _tmin === undefined || _tmax === null || _tmax === undefined) return 0
                        var bw = trackBox.width
                        var x0 = (_tmin - barMin) / _span * bw
                        var w0 = Math.max(6, (_tmax - _tmin) / _span * bw)
                        if (x0 < 0) x0 = 0
                        if (x0 + w0 > bw) w0 = Math.max(6, bw - x0)
                        return x0
                    }
                    width: {
                        if (_tmin === null || _tmin === undefined || _tmax === null || _tmax === undefined) return 0
                        var bw = trackBox.width
                        var x0 = (_tmin - barMin) / _span * bw
                        if (x0 < 0) x0 = 0
                        var w0 = Math.max(6, (_tmax - _tmin) / _span * bw)
                        if (x0 + w0 > bw) w0 = Math.max(6, bw - x0)
                        return w0
                    }
                }
            }
        }

        // 低温数字：紧贴条左端外侧；条贴左边时落在左侧预留区内，不压条
        Text {
            id: lowTxt
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(trackBox.x + bar.x - width - 6, barBox.width - width))
            text: dr.fmt(dr.item.tmin) === "--" ? "--" : dr.fmt(dr.item.tmin) + "°"
            font.pixelSize: 12
            color: dr.cTempL
        }
        // 高温数字：紧贴条右端外侧；条贴右边时落在右侧预留区内，不压条
        Text {
            id: highTxt
            anchors.verticalCenter: parent.verticalCenter
            x: Math.min(barBox.width - width, Math.max(trackBox.x + bar.x + bar.width + 6, 0))
            text: dr.fmt(dr.item.tmax) === "--" ? "--" : dr.fmt(dr.item.tmax) + "°"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: dr.cMain
        }
    }

    // 日出日落
    Column {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 118
        spacing: 1
        Row {
            spacing: 3
            Image {
                source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + dr.theme + "/sunrise.svg"
                sourceSize: Qt.size(13, 13)
                opacity: 0.85
            }
            Text {
                text: dr.item.sunrise ? dr.item.sunrise : "--:--"
                font.pixelSize: 11
                color: dr.cSun
            }
        }
        Row {
            spacing: 3
            Image {
                source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + dr.theme + "/sunset.svg"
                sourceSize: Qt.size(13, 13)
                opacity: 0.85
            }
            Text {
                text: dr.item.sunset ? dr.item.sunset : "--:--"
                font.pixelSize: 11
                color: dr.cSun
            }
        }
    }
}
