import QtQuick 2.15

// 雨滴动效：雨滴落在"玻璃"上缓缓滑落（覆盖全窗口，点击穿透，不拦截事件）
// 22 条轻量粒子（Rectangle + SequentialAnimation 错峰循环），雨天时 active=true 才运行
Item {
    id: rain
    property bool active: false
    property string theme: "dark"
    readonly property bool lt: rain.theme === "light"
    readonly property color dropColor: rain.lt ? "#3D1C2B4A" : "#59FFFFFF"

    visible: rain.active
    enabled: false          // 完全鼠标穿透
    anchors.fill: parent

    // 雨滴粒子工厂：每条由 Pause(随机 0-3s 错峰) + 下滑动画 循环
    Repeater {
        model: 22
        Item {
            id: drop
            property real spd: 3200 + Math.random() * 2400      // 滑落时长 3.2-5.6s（缓缓滑落）
            property real delay: Math.random() * 3200           // 错峰
            property real tilt: 8 + Math.random() * 7           // 倾斜 8-15°
            x: Math.random() * (rain.width || 1)
            y: -40

            Rectangle {
                id: line
                anchors.centerIn: parent
                width: 1.6 + Math.random() * 0.8
                height: 13 + Math.random() * 12
                radius: width / 2
                color: rain.dropColor
                rotation: drop.tilt
            }

            SequentialAnimation on y {
                running: rain.active
                loops: Animation.Infinite
                PauseAnimation { duration: drop.delay }
                NumberAnimation {
                    from: -40
                    to: (rain.height || 400) + 40
                    duration: drop.spd
                    easing.type: Easing.Linear
                }
            }
        }
    }
}
