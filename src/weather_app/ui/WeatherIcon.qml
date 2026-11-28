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
        // SVG 栅格化放到加载线程：启动时几十个图标不再逐个卡住首帧
        asynchronous: true
        cache: true
    }
}
