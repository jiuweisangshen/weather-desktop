import QtQuick 2.15
import QtQuick.Window 2.15

// 液态玻璃卡片 v13（正式接入 Liquid Glass 原型）
//   · 背景：主界面 bgCapture 抓取的整窗半分辨率纹理，经 ShaderEffect 做
//     圆角 SDF、边缘折射、RGB 色散、菲涅尔高光、鼠标跟随高光
//   · 悬浮：只做视觉 scale 1.00 ↔ 1.03（200ms OutCubic），不参与布局、不触发重排
//   · 放大时以卡片中心换算采样坐标，玻璃后的背景保持原位 1:1，不跟着放大
//   · 兼容旧接口：pad / radius / theme / hoverable / lt / 默认内容槽
Item {
    id: gcard

    property int pad: 18
    property int radius: 24
    property string theme: "dark"
    property bool hoverable: true
    // 拖动布局标识（主界面编辑玻璃位置时用于持久化）
    property string layoutKey: ""
    // 动画强度由主窗口设置面板控制：full=200ms 过渡；simple=瞬时缩放；off=不缩放
    property string animLevel: glassWindowItem ? (glassWindowItem.animLevel || "full") : "full"
    // 设置面板开关：玻璃浮动 / 鼠标跟随
    readonly property bool floatEnabled: glassWindowItem ? glassWindowItem.glassFloat !== false : true
    readonly property bool followEnabled: glassWindowItem ? glassWindowItem.mouseFollow !== false : true
    readonly property bool editMode: glassWindowItem ? !!glassWindowItem.glassEdit : false
    // 只有带布局标识的卡片（8 个小卡）参与位置互换；大卡片不参与拖动
    readonly property bool draggable: gcard.editMode && gcard.layoutKey !== ""
    property bool dragging: false
    property real editDX: 0
    property real editDY: 0
    // 位置互换时的临时让位偏移（松手后并入 editDX/editDY）
    property real previewDX: 0
    property real previewDY: 0
    property var swapTarget: null
    property point swapTargetBase: Qt.point(0, 0)
    property point baseVisual: Qt.point(0, 0)
    property bool baseVisualReady: false
    property bool instantPreview: false
    property point dragStartOffset: Qt.point(0, 0)
    property point dragStartVisual: Qt.point(0, 0)
    // 拖动偏移用 Translate 变换实现，绝不能绑定 x/y：
    // Column/Flow 会直接改写子项 x/y，绑定会被布局打断，导致卡片乱飞、重置失效。
    property bool applyOffsetTransform: true
    transform: Translate {
        id: posTransform
        x: gcard.applyOffsetTransform ? (gcard.editDX + gcard.previewDX) : 0
        y: gcard.applyOffsetTransform ? (gcard.editDY + gcard.previewDY) : 0
        // 拖动/交换动画进行时，玻璃采样坐标必须每帧跟着重算
        onXChanged: gcard.refreshPos()
        onYChanged: gcard.refreshPos()
        Behavior on x { enabled: !gcard.dragging && !gcard.instantPreview; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !gcard.dragging && !gcard.instantPreview; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }
    function loadLayout() {
        var v = null
        if (gcard.layoutKey && glassWindowItem && glassWindowItem.glassLayout)
            v = glassWindowItem.glassLayout[gcard.layoutKey]
        gcard.editDX = (v && v.length >= 2) ? Number(v[0]) || 0 : 0
        gcard.editDY = (v && v.length >= 2) ? Number(v[1]) || 0 : 0
        gcard.previewDX = 0
        gcard.previewDY = 0
        gcard.refreshPos()
    }
    default property alias content: body.data

    implicitWidth: 320
    implicitHeight: 160

    readonly property bool lt: gcard.theme === "light"

    // ---------- 背景纹理与坐标映射（自动取主窗口的统一背景层） ----------
    // 注意：直接在绑定里写 gcard.window 会在窗口挂载前求值为 null 且不再更新，
    // 必须由 Component.onCompleted 显式取窗口后再建立绑定。
    property var glassWindowItem: null
    property Item bgTexture: glassWindowItem ? glassWindowItem.glassTexture : null
    property Item bgRoot: glassWindowItem ? glassWindowItem.glassRoot : null
    // 滚动容器（Flickable.contentItem）：其 x/y 变化时重新映射采样坐标
    property Item followItem: glassWindowItem ? glassWindowItem.glassFollow : null
    // 未指定背景根时回退到窗口内容层，避免首个委托在兄弟 id 注册前拿到 null
    property Item bgRef: bgRoot ? bgRoot
                                : (glassWindowItem ? glassWindowItem.contentItem : null)
    // 卡片未缩放左上角在背景纹理中的位置
    property vector2d cardPos: Qt.vector2d(0, 0)

    function bindWindow() {
        if (!glassWindowItem) {
            var w = Window.window
            if (!w)
                w = gcard.window
            glassWindowItem = w
        }
    }

    Timer {
        interval: 120
        repeat: true
        running: !gcard.glassWindowItem
        onTriggered: gcard.bindWindow()
    }

    // ---------- 悬浮状态 ----------
    property bool hovered: false
    property real hoverLevel: hovered ? 1.0 : 0.0
    property bool mouseInside: false
    property real mouseHoverLevel: (mouseInside && gcard.followEnabled ? 1.0 : 0.0) * (typeof glassWindowItem !== "undefined" && glassWindowItem ? glassWindowItem.hoverBrightness : 1.0)
    property real hoverX: width * 0.5
    property real hoverY: height * 0.4
    readonly property vector2d mousePos: Qt.vector2d(hoverX, hoverY)

    // ---------- 玻璃光学参数（干净透明优先，背景细节保留） ----------
    property real refraction: 14.0
    property real dispersion: 0.10
    property vector3d tintRGB: lt ? Qt.vector3d(0.97, 0.98, 1.0)
                                  : Qt.vector3d(0.04, 0.07, 0.14)
    property real tintAlpha: lt ? 0.04 : 0.16

    // 悬浮浮动：纯视觉缩放，不占布局、不触发重排
    readonly property bool hoverScaleEnabled: gcard.hoverable && gcard.floatEnabled && gcard.animLevel !== "off"
    scale: (gcard.hovered && gcard.hoverScaleEnabled) ? 1.03 : 1.0
    Behavior on scale {
        enabled: gcard.animLevel === "full"
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
    Behavior on hoverLevel {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on mouseHoverLevel {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // ---------- 采样坐标追踪 ----------
    // 只看卡片自身 x/y 不够：横向 ListView 的 contentX 变化、预警横幅插入导致的
    // 整列下移，改的都是祖先（contentItem）的 x/y，卡片自身坐标不变，
    // 结果玻璃采样停留在旧位置，看起来就是"卡片边框和玻璃错位/残影"。
    // 因此沿 parent 链逐级挂上位移信号。
    property var hookedItems: []
    function hookChain() {
        var it = gcard.parent
        while (it) {
            if (gcard.hookedItems.indexOf(it) < 0) {
                try {
                    if (it.xChanged)
                        it.xChanged.connect(gcard.refreshPos)
                    if (it.yChanged)
                        it.yChanged.connect(gcard.refreshPos)
                    if (it.widthChanged)
                        it.widthChanged.connect(gcard.refreshPos)
                    if (it.heightChanged)
                        it.heightChanged.connect(gcard.refreshPos)
                } catch (e) {
                }
                gcard.hookedItems.push(it)
            }
            it = it.parent
        }
    }

    // 兜底校正：滚动惯性、布局动画期间的低频重算（只做一次 mapToItem，开销可忽略）
    Timer {
        interval: 120
        repeat: true
        running: gcard.visible && gcard.bgTexture !== null
        onTriggered: gcard.refreshPos()
    }

    onParentChanged: {
        gcard.hookChain()
        gcard.refreshPos()
    }

    function refreshPos() {
        if (!bgRef)
            return
        // 取卡片中心映射（scale 围绕中心，不改变中心位置），
        // 反推未缩放的左上角，保证放大时采样坐标不跟着缩放
        var c = gcard.mapToItem(bgRef, gcard.width / 2, gcard.height / 2)
        var nx = c.x - gcard.width / 2
        var ny = c.y - gcard.height / 2
        // 位置没变就不赋值：避免定时校正造成无谓的着色器重绘
        if (Math.abs(nx - gcard.cardPos.x) > 0.01 || Math.abs(ny - gcard.cardPos.y) > 0.01)
            gcard.cardPos = Qt.vector2d(nx, ny)
    }

    Component.onCompleted: {
        bindWindow()
        hookChain()
        loadLayout()
        refreshPos()
        if (glassWindowItem && glassWindowItem.registerGlassCard)
            glassWindowItem.registerGlassCard(gcard)
    }
    onXChanged: refreshPos()
    onYChanged: refreshPos()
    onWidthChanged: refreshPos()
    onHeightChanged: refreshPos()
    onBgRefChanged: refreshPos()

    Connections {
        target: gcard.bgRef
        function onWidthChanged() { gcard.refreshPos() }
        function onHeightChanged() { gcard.refreshPos() }
    }

    Connections {
        target: gcard.followItem
        function onXChanged() { gcard.refreshPos() }
        function onYChanged() { gcard.refreshPos() }
    }

    // 布局位置重置/编辑模式切换时，重新读取偏移并校准玻璃采样
    Connections {
        target: gcard.glassWindowItem
        function onGlassLayoutChanged() { gcard.loadLayout() }
        function onGlassEditChanged() { gcard.dragging = false; gcard.refreshPos() }
    }

    // ---------- 柔和外阴影（从卡片底缘开始、左右微扩、垂直渐变渐隐） ----------
    Repeater {
        model: [
            { off: 8,  a: lt ? 0.035 : 0.070, sp: 6 },
            { off: 16, a: lt ? 0.020 : 0.040, sp: 10 },
            { off: 26, a: lt ? 0.010 : 0.020, sp: 16 },
            { off: 38, a: lt ? 0.005 : 0.009, sp: 22 }
        ]
        delegate: Rectangle {
            x: -modelData.sp
            y: gcard.height - modelData.sp
            width: gcard.width + modelData.sp * 2
            height: modelData.off + modelData.sp * 2 + 18
            radius: gcard.radius + modelData.sp
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, modelData.a) }
                GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, modelData.a * 0.35) }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }
    }

    // 玻璃厚度：外圈极淡冷光 + 内缘细亮边，只勾勒边缘，不压暗背景
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: gcard.radius + 1
        color: "transparent"
        border.width: 1
        border.color: gcard.lt ? "#3CFFFFFF" : "#20FFFFFF"
        z: -1
    }
    Rectangle {
        anchors.fill: parent
        radius: gcard.radius
        color: "transparent"
        border.width: 1
        border.color: gcard.lt ? "#A6FFFFFF" : "#4DFFFFFF"
        z: 2
    }

    // 背景纹理就绪前的兜底（避免启动瞬间出现全透明卡片）
    Rectangle {
        anchors.fill: parent
        radius: gcard.radius
        visible: !gcard.bgTexture
        color: gcard.lt ? "#1AFFFFFF" : "#14FFFFFF"
        border.width: 1
        border.color: gcard.lt ? "#46FFFFFF" : "#42FFFFFF"
        gradient: Gradient {
            GradientStop { position: 0.0; color: gcard.lt ? "#28FFFFFF" : "#18FFFFFF" }
            GradientStop { position: 0.6; color: gcard.lt ? "#18FFFFFF" : "#0CFFFFFF" }
            GradientStop { position: 1.0; color: gcard.lt ? "#0EFFFFFF" : "#06FFFFFF" }
        }
    }

    // ---------- 玻璃本体 ----------
    ShaderEffect {
        id: glass
        anchors.fill: parent
        visible: !!gcard.bgTexture

        property variant bg: gcard.bgTexture
        property vector2d winSize: gcard.bgRef
                                   ? Qt.vector2d(gcard.bgRef.width, gcard.bgRef.height)
                                   : Qt.vector2d(1, 1)
        property vector2d cardPos: gcard.cardPos
        property vector2d cardSize: Qt.vector2d(gcard.width, gcard.height)
        property real radius: gcard.radius
        // 鼠标跟随：局部镜面光斑 + 指针侧边缘反光（旧版大范围提亮已移除）
        property real hover: gcard.mouseHoverLevel
        property vector2d mouse: gcard.mousePos
        property real light: gcard.lt ? 1.0 : 0.0
        property real refract: gcard.refraction
        property real disperse: gcard.dispersion
        property vector3d tintRGB: gcard.tintRGB
        property real tintAlpha: gcard.tintAlpha
        property real cardScale: gcard.scale

        fragmentShader: "glass.frag.qsb"
    }

    // ---------- 悬停追踪（所有卡片都追踪鼠标位置，用于玻璃高光；hoverable 控制是否缩放） ----------
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: {
            gcard.mouseInside = containsMouse
            if (gcard.hoverable) {
                gcard.hovered = containsMouse
            }
        }
        onPositionChanged: function (mouse) {
            gcard.hoverX = mouse.x
            gcard.hoverY = mouse.y
        }
        onEntered: {
            gcard.hoverX = mouseX
            gcard.hoverY = mouseY
        }
    }

    // ---------- 内容层 ----------
    Item {
        id: body
        z: 1
        x: gcard.pad
        y: gcard.pad
        width: gcard.width - gcard.pad * 2
        height: gcard.height - gcard.pad * 2
    }

    // ---------- 玻璃位置编辑：拖动整卡（只在编辑模式接管鼠标） ----------
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: 5
        enabled: gcard.draggable
        visible: gcard.draggable
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeAllCursor
        property point startCard: Qt.point(0, 0)
        property point startMouse: Qt.point(0, 0)
        onPressed: function (mouse) {
            startCard = Qt.point(gcard.editDX, gcard.editDY)
            startMouse = Qt.point(mouse.x, mouse.y)
            gcard.dragStartOffset = startCard
            if (glassWindowItem && glassWindowItem.glassVisualCenter) {
                gcard.dragStartVisual = glassWindowItem.glassVisualCenter(gcard)
                gcard.baseVisual = Qt.point(gcard.dragStartVisual.x - gcard.editDX - gcard.previewDX,
                                            gcard.dragStartVisual.y - gcard.editDY - gcard.previewDY)
                gcard.baseVisualReady = true
            }
            gcard.dragging = true
            gcard.hovered = false
        }
        onPositionChanged: function (mouse) {
            if (!pressed) return
            var nx = startCard.x + (mouse.x - startMouse.x)
            var ny = startCard.y + (mouse.y - startMouse.y)
            gcard.editDX = Math.max(-900, Math.min(900, nx))
            gcard.editDY = Math.max(-900, Math.min(900, ny))
            // 拖动过程中只更新自身与玻璃采样；其他卡片不动，松手时才交换
            gcard.refreshPos()
        }
        onReleased: {
            if (!gcard.dragging) return
            gcard.dragging = false
            if (glassWindowItem && glassWindowItem.findGlassSwapTarget)
                glassWindowItem.findGlassSwapTarget(gcard)
            if (glassWindowItem && glassWindowItem.commitGlassSwap)
                glassWindowItem.commitGlassSwap(gcard)
            if (gcard.layoutKey && glassWindowItem)
                glassWindowItem.updateCardLayout(gcard.layoutKey, gcard.editDX, gcard.editDY)
            gcard.refreshPos()
        }
    }
    Rectangle {
        anchors.fill: parent
        z: 6
        radius: gcard.radius
        color: "transparent"
        border.width: gcard.draggable ? 2 : 0
        border.color: "#7DD3FC"
        visible: gcard.draggable
    }
}
