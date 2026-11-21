import QtQuick 2.15

// 天气图标：直接加载 SVG 源文件（按主题目录 dark/light）
Item {
    id: wic
    property string key: "cloudy"
    property int size: 40
    property string theme: "dark"

    width: size
    height: size

    Image {
        anchors.fill: parent
        source: "file:///" + res.replace(/\\/g, "/") + "/icons/svg/" + wic.theme + "/" + wic.key + ".svg"
        sourceSize: Qt.size(wic.size * 2, wic.size * 2)
        smooth: true
        antialiasing: true
    }
}
