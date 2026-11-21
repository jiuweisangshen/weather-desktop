import QtQuick 2.15

// 指标磁贴：图标 + 标签 + 数值 + 副信息
// 悬停交互由 GlassCard 统一处理：只叠加极淡高光，不做缩放/位移，避免整卡重绘卡顿。
GlassCard {
    id: tile
    property string iconKey: ""
    property string label: ""
    property string value: "--"
    property string sub: ""
    property color valueColor: tile.theme === "light" ? "#1C2B4A" : "#FFFFFF"
    property string theme: "dark"

    width: parent.width
    height: 132
    pad: 14
    radius: 20

    // 悬停交给 GlassCard 统一处理（只叠高光，不做缩放），
    // 避免 MetricTile 再叠加 1.03 缩放导致卡片“浮太高”和渐变重绘卡顿。

    Column {
        anchors.fill: parent
        spacing: 7

        WeatherIcon {
            key: tile.iconKey
            size: 30
            theme: tile.theme
        }
        Text {
            text: tile.label
            font.pixelSize: 12
            color: tile.theme === "light" ? "#9E1C2B4A" : "#B8FFFFFF"
        }
        Row {
            spacing: 4
            Text {
                id: valueText
                text: tile.value
                font.pixelSize: 21
                font.weight: Font.DemiBold
                color: tile.valueColor
            }
            Text {
                text: tile.sub
                font.pixelSize: 12
                color: tile.theme === "light" ? "#8C1C2B4A" : "#A6FFFFFF"
                anchors.baseline: valueText.baseline
            }
        }
    }
}
