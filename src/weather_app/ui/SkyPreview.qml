import QtQuick 2.15

// 天气背景预览面板：深色模式下按时段 × 天气状况展示实景背景，并附数据来源与工作原理说明。
// 入口为主界面标题"天气"右侧的小太阳按钮；开合带淡入与缩放过渡。
Item {
    id: pv
    anchors.fill: parent
    z: 500

    property bool opened: false
    property string theme: "dark"
    property string assets: ""
    property var wd: ({})
    property real solarElev: 0

    // 多语言：文案统一走 tr("简体原文")，由 Python 词典翻译
    function tr(text) {
        try { return backend.translate(text) } catch (e) { return text }
    }

    readonly property bool lt: pv.theme === "light"
    property real op: pv.opened ? 1 : 0
    Behavior on op { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    opacity: pv.op
    visible: pv.op > 0.002

    // ===== 时段定义（按真实太阳高度角判定当前时段） =====
    // 时段 key 保留简体原文（isNight 判断依赖它），显示时再经 tr() 翻译
    property var rows: [
        { short: "清晨", span: "06:30 – 09:00", tint: "#33FF9F55" },
        { short: "正午", span: "11:00 – 14:00", tint: "#14FFFFFF" },
        { short: "黄昏", span: "17:30 – 19:30", tint: "#3A5B3A8E" },
        { short: "夜间", span: tr("20:00 之后"),   tint: "#4D06122A" }
    ]
    property var conds: [
        { label: tr("晴"),  day: "sky_clear.jpg",  night: "sky_night.jpg" },
        { label: tr("多云"), day: "sky_partly.jpg", night: "sky_night_cloudy.jpg" },
        { label: tr("阴"),  day: "sky_cloudy.jpg", night: "sky_night_cloudy.jpg" },
        { label: tr("雨"),  day: "sky_rain.jpg",   night: "sky_night_cloudy.jpg" }
    ]

    function buildCells() {
        var out = []
        for (var r = 0; r < rows.length; r++) {
            for (var c = 0; c < conds.length; c++) {
                var isNight = rows[r].short === "夜间"
                out.push({
                    rowIdx: r,
                    colIdx: c,
                    title: tr(rows[r].short) + " · " + conds[c].label,
                    sky: isNight ? conds[c].night : conds[c].day,
                    tint: rows[r].tint
                })
            }
        }
        return out
    }
    property var cells: buildCells()

    // 当前时段（太阳高度角优先，退化到本地小时）
    readonly property int curRow: {
        var e = pv.solarElev
        var h = new Date().getHours() + new Date().getMinutes() / 60
        if (e < -6) return 3
        if (e < 6) return (h < 12) ? 0 : 2
        return 1
    }

    function imgPath(name) {
        return "file:///" + pv.assets.replace(/\\/g, "/") + "/ui/sky/" + name
    }

    // ===== 遮罩（点击关闭） =====
    Rectangle {
        anchors.fill: parent
        color: pv.lt ? "#66000000" : "#73000000"
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onClicked: pv.opened = false
            onWheel: function (wheel) { wheel.accepted = true }
        }
    }

    // ===== 面板 =====
    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.max(420, Math.min(pv.width - 120, 900))
        height: Math.max(320, Math.min(pv.height - 90, 660))
        radius: 26
        color: pv.lt ? "#F7F4F8FC" : "#F00A1430"
        border.width: 1
        border.color: pv.lt ? "#5AFFFFFF" : "#3DFFFFFF"
        scale: pv.opened ? 1.0 : 0.94
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onWheel: function (wheel) { wheel.accepted = true }
        }   // 吃掉点击/滚轮，避免穿透到遮罩和底层内容

        // 顶部高光
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            radius: panel.radius
            color: pv.lt ? "#A8FFFFFF" : "#59FFFFFF"
        }

        // ---------- 标题栏 ----------
        Item {
            id: bar
            height: 58
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: tr("天气背景预览")
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    color: pv.lt ? "#1C2B4A" : "#FFFFFF"
                }
                Text {
                    text: tr("深色模式实景背景 · 随天气状况与太阳高度角切换")
                    font.pixelSize: 11
                    color: pv.lt ? "#8C1C2B4A" : "#8CFFFFFF"
                }
            }

            // 关闭按钮
            Rectangle {
                id: closeBtn
                width: 30
                height: 30
                radius: 15
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                color: closeArea.containsMouse ? (pv.lt ? "#1F1C2B4A" : "#33FFFFFF") : "transparent"
                border.width: 1
                border.color: pv.lt ? "#331C2B4A" : "#24FFFFFF"
                Behavior on color { ColorAnimation { duration: 150 } }
                Image {
                    anchors.centerIn: parent
                    source: "file:///" + pv.assets.replace(/\\/g, "/") + "/icons/svg/" + pv.theme + "/close.svg"
                    sourceSize: Qt.size(13, 13)
                }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pv.opened = false
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                height: 1
                color: pv.lt ? "#1A1C2B4A" : "#1FFFFFFF"
            }
        }

        // ---------- 内容（可滚动） ----------
        Flickable {
            id: bodyFlick
            anchors.top: bar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 26
            anchors.rightMargin: 26
            anchors.bottomMargin: 20
            contentWidth: width
            contentHeight: bodyCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 3600

            Column {
                id: bodyCol
                width: bodyFlick.width
                spacing: 14

                Item { width: 1; height: 4 }

                // ---------- 时段 × 天气 背景网格 ----------
                Text {
                    text: tr("背景状态对照")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: pv.lt ? "#1C2B4A" : "#FFFFFF"
                }

                Grid {
                    id: grid
                    width: bodyCol.width
                    columns: 4
                    spacing: 10
                    readonly property real cellW: (width - spacing * 3) / 4

                    Repeater {
                        model: pv.cells
                        delegate: Item {
                            width: grid.cellW
                            height: width * 0.56 + 26

                            Rectangle {
                                id: cellBox
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: parent.height - 26
                                radius: 12
                                clip: true
                                color: "transparent"
                                border.width: modelData.rowIdx === pv.curRow ? 2 : 1
                                border.color: modelData.rowIdx === pv.curRow
                                              ? (pv.lt ? "#1E6FD9" : "#8FE3FF")
                                              : (pv.lt ? "#221C2B4A" : "#2EFFFFFF")

                                Image {
                                    anchors.fill: parent
                                    source: pv.imgPath(modelData.sky)
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    asynchronous: true
                                    sourceSize: Qt.size(360, 220)
                                }
                                // 时段色罩（体现清晨暖光 / 黄昏紫调 / 夜间深色）
                                Rectangle {
                                    anchors.fill: parent
                                    color: modelData.tint
                                }
                                // 当前时段角标（每行只在首格标注一次）
                                Rectangle {
                                    visible: modelData.rowIdx === pv.curRow && modelData.colIdx === 0
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                    height: 20
                                    width: curTxt.implicitWidth + 14
                                    radius: 10
                                    color: pv.lt ? "#331E6FD9" : "#4D8FE3FF"
                                    Text {
                                        id: curTxt
                                        anchors.centerIn: parent
                                        text: tr("当前")
                                        font.pixelSize: 10
                                        color: pv.lt ? "#0B2E5C" : "#DFF3FF"
                                    }
                                }
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.leftMargin: 3
                                text: modelData.title
                                font.pixelSize: 11
                                color: pv.lt ? "#731C2B4A" : "#99FFFFFF"
                            }
                        }
                    }
                }

                Text {
                    text: tr("说明：浅色主题不启用实景背景，仅深色主题显示；色温层随太阳高度角连续变化，夜间与阴雨场景的明度自动收敛。")
                    font.pixelSize: 11
                    color: pv.lt ? "#731C2B4A" : "#73FFFFFF"
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: 6 }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: pv.lt ? "#141C2B4A" : "#14FFFFFF"
                }

                Item { width: 1; height: 2 }

                Text {
                    text: tr("数据来源")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: pv.lt ? "#731C2B4A" : "#CCFFFFFF"
                }

                Column {
                    spacing: 5
                    Repeater {
                        model: [
                            { n: "Open-Meteo", d: tr("欧洲中期天气预报中心（ECMWF）与 NOAA GFS 数值模式数据，主源，融合权重 28%") },
                            { n: tr("中国天气网"), d: tr("中国气象局公共气象服务观测与预报产品，融合权重 24%") },
                            { n: "wttr.in", d: tr("基于 WorldWeatherOnline 的派生数据，用于交叉校验，融合权重 22%") },
                            { n: tr("和风天气"), d: tr("商业气象服务接口，需在 config.json 配置 API Key 后启用，融合权重 12%") },
                            { n: "GFS / ECMWF", d: tr("两套全球模式直连数据，用于补充与偏差校验，各占 7%") }
                        ]
                        delegate: Row {
                            width: bodyCol.width
                            spacing: 8
                            Rectangle {
                                width: 5
                                height: 5
                                radius: 2.5
                                anchors.verticalCenter: parent.verticalCenter
                                color: pv.lt ? "#5A1C2B4A" : "#59FFFFFF"
                            }
                            Text {
                                width: bodyCol.width - 13
                                text: modelData.n + " —— " + modelData.d
                                wrapMode: Text.WordWrap
                                font.pixelSize: 11
                                color: pv.lt ? "#8C1C2B4A" : "#99FFFFFF"
                            }
                        }
                    }
                }

                Item { width: 1; height: 2 }

                Text {
                    text: tr("工作原理")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: pv.lt ? "#731C2B4A" : "#CCFFFFFF"
                }

                Column {
                    spacing: 5
                    Repeater {
                        model: [
                            tr("坐标解析：搜索词经地理编码转换为经纬度与行政归属，支持区县级行政区。"),
                            tr("并行取数：各数据源并发请求，单个数据源失败不影响整体结果，异常值按中位数剔除。"),
                            tr("加权融合：按数据源可信度与历史偏差对温度、湿度、气压、风等要素加权求值。"),
                            tr("相态校正：逐日降水按降雨量、降雪量与最高气温判别小雨、雨夹雪与各级降雪。"),
                            tr("背景渲染：按当前天气与太阳高度角选择实景图，并按光照强度叠加色温层。"),
                            tr("自动刷新：每 10 分钟主动拉取一次；网络异常时沿用本地缓存并在下一周期重试。")
                        ]
                        delegate: Row {
                            width: bodyCol.width
                            spacing: 8
                            Text {
                                width: 16
                                text: (index + 1) + "."
                                font.pixelSize: 11
                                color: pv.lt ? "#5A1C2B4A" : "#8CFFFFFF"
                            }
                            Text {
                                width: bodyCol.width - 24
                                text: modelData
                                wrapMode: Text.WordWrap
                                font.pixelSize: 11
                                color: pv.lt ? "#8C1C2B4A" : "#99FFFFFF"
                            }
                        }
                    }
                }

                Item { width: 1; height: 10 }
            }
        }

        // 底部渐隐：提示下方仍有内容可滚动
        Rectangle {
            anchors.left: bodyFlick.left
            anchors.right: bodyFlick.right
            anchors.bottom: bodyFlick.bottom
            height: 28
            visible: bodyFlick.contentHeight > bodyFlick.height + 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: pv.lt ? "#F2F7F4F8FC" : "#F00A1430" }
            }
        }
    }

    // 打开时聚焦内容顶部
    onOpenedChanged: if (opened) { bodyFlick.contentY = 0 }
}
