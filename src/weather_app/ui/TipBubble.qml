// 液态玻璃风格说明气泡：悬停按钮 500ms 后显示，移开立即隐藏（深浅色双版）
import QtQuick 2.15

Item {
    id: tipB
    property string text: ""
    property bool hovered: false
    property int delay: 500
    property string theme: "dark"
    readonly property bool lt: tipB.theme === "light"

    visible: false
    z: 99
    width: tipText.implicitWidth + 18
    height: 26
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.bottom
    anchors.topMargin: 8

    Rectangle {
        anchors.fill: parent
        radius: 13
        color: tipB.lt ? "#EFFFFFFF" : "#E6202A4A"
        border.color: tipB.lt ? "#5A1C2B4A" : "#40FFFFFF"
        border.width: 1
    }
    Rectangle {
        width: 10
        height: 10
        x: parent.width / 2 - 5
        y: -5
        radius: 2
        rotation: 45
        color: tipB.lt ? "#EFFFFFFF" : "#E6202A4A"
        border.color: tipB.lt ? "#5A1C2B4A" : "#40FFFFFF"
        border.width: 1
    }
    Text {
        id: tipText
        anchors.centerIn: parent
        text: tipB.text
        font.pixelSize: 11
        color: tipB.lt ? "#1C2B4A" : "#FFFFFF"
    }
    Timer {
        interval: tipB.delay
        running: tipB.hovered
        onTriggered: tipB.visible = true
    }
    onHoveredChanged: if (!hovered) visible = false
}
