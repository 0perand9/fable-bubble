import QtQuick
import qs.core
import qs.widgets
import qs.plugins.bubble

// The monitor's page: the field of bubbles (Field.qml) and what lies over it.
// Top left, the switch between the busiest processes and the open apps (full
// screen shows both). Top right, the full-screen button with the battery
// beside it, and under it the buttons of the CPU, memory, temperature and disk
// pages (the wheel steps through them). A tapped bubble's page slides in on
// the left (InfoPanel.qml) and the camera keeps that bubble in the middle of
// what is left.
//
// It is one item so that it can travel: full screen takes it out of the popup
// into a window of its own and brings it back (FullScreen.qml).
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the page of the System page's Bubble style,
// BubbleMonitor.qml at 1909479, descended from ilyamiro's Serpantinum.
Item {
    id: page

    // the full-screen button, or Escape while full screen
    signal fullToggled

    // Monitor works out the camera from the sizes it is drawn at.
    function measure() {
        Monitor.viewW = Math.max(1, field.width);
        Monitor.viewH = Math.max(1, field.height);
        Monitor.cardW = card.width;
        if (!Monitor.camReady && field.width > 1 && field.height > 1)
            Monitor.placeCamera();
    }

    clip: true
    focus: true
    // Escape closes an open bubble's page, then full screen, then the popup.
    Keys.onEscapePressed: event => {
        if (Monitor.ms.open)
            Monitor.closeOverlay();
        else if (Monitor.full)
            page.fullToggled();
        else
            event.accepted = false;
    }

    Field {
        id: field

        anchors.fill: parent
        onWidthChanged: page.measure()
        onHeightChanged: page.measure()
    }

    // Processes or open apps: the mark slides to the one picked. Out of the
    // way while a page is open on the left.
    Rectangle {
        visible: !Monitor.full
        x: Theme.px(12)
        y: Theme.px(12)
        z: 20
        width: modeRow.implicitWidth + Theme.px(8)
        height: Theme.px(40)
        radius: height / 2
        color: Qt.alpha(Look.bg, 0.82)
        opacity: 1 - glass.e

        Rectangle {
            readonly property Item on: Monitor.mode === "apps" ? appsSeg : procsSeg

            x: modeRow.x + on.x
            y: modeRow.y
            width: on.width
            height: Theme.px(32)
            radius: height / 2
            color: Qt.alpha(Look.text, 0.16)

            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Row {
            id: modeRow

            anchors.centerIn: parent

            ModeSeg { id: procsSeg; label: "Processes"; value: "procs" }
            ModeSeg { id: appsSeg; label: "Apps"; value: "apps" }
        }
    }

    // full screen and back
    Rectangle {
        id: fullBtn

        z: 40          // above an open page's dimming, as all on this side: they still work
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.px(12)
        width: Theme.px(40)
        height: width
        radius: width / 2
        color: Qt.alpha(fullArea.containsMouse ? Look.line : Look.bg, 0.82)

        Behavior on color { ColorAnimation { duration: 140 } }

        Icon {
            anchors.centerIn: parent
            text: Monitor.full ? "\u{f0294}" : Icons.fullscreen     // md-fullscreen_exit
            size: 17
            color: Look.text
        }

        MouseArea {
            id: fullArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.fullToggled()
        }
    }

    // the battery beside it, if there is one: a drawn battery lying down,
    // filled to the charge, the percentage under it
    Rectangle {
        id: batteryBadge

        readonly property real pct: Monitor.battery ? Monitor.battery.pct : 0
        readonly property bool plugged: !!(Monitor.battery && Monitor.battery.plugged)
        readonly property bool low: pct <= 20 && !plugged

        visible: !!Monitor.battery
        z: 40
        anchors.right: fullBtn.left
        anchors.rightMargin: Theme.px(8)
        anchors.verticalCenter: fullBtn.verticalCenter
        width: Theme.px(40)
        height: width
        radius: width / 2
        color: Qt.alpha(Look.bg, 0.82)

        Item {
            id: batGlyph

            x: (parent.width - width) / 2
            y: Theme.px(8)
            width: Theme.px(24)
            height: Theme.px(12)

            Rectangle {
                width: parent.width - Theme.px(3)
                height: parent.height
                radius: Theme.px(3.5)
                color: "transparent"
                border.width: Theme.px(1.5)
                border.color: Qt.alpha(Look.text, 0.55)

                Rectangle {
                    x: Theme.px(2.5)
                    y: x
                    height: parent.height - 2 * x
                    radius: Theme.px(1.5)
                    width: Math.max(Theme.px(2), (parent.width - 2 * x) * batteryBadge.pct / 100)
                    color: batteryBadge.low ? Look.hot : Look.accent

                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }

                Icon {
                    anchors.centerIn: parent
                    visible: batteryBadge.plugged
                    text: Icons.bolt
                    size: 9
                    color: Look.ink
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.px(2)
                height: Theme.px(5)
                radius: Theme.px(1)
                color: Qt.alpha(Look.text, 0.55)
            }
        }

        FlowText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: batGlyph.bottom
            anchors.topMargin: Theme.px(2)
            target: Math.round(batteryBadge.pct) + "%"
            font.family: Look.font
            font.pixelSize: Theme.px(9)
            color: Look.text
        }
    }

    // CPU, memory, temperature and disk in a column: a click, or the wheel
    // over them (one step a click, stopping at either end), opens that
    // bubble's page; the mark slides to it.
    Rectangle {
        id: quick

        readonly property var keys: ["cpu", "mem", "temp", "disk"]
        readonly property int at: Monitor.info ? keys.indexOf(Monitor.info.id) : -1
        property int last: 0
        property real wheelAcc: 0

        function go(i) {
            i = Math.max(0, Math.min(keys.length - 1, i));
            // back up the list, the page comes down into place instead of up
            Monitor.swapDir = at >= 0 && i < at ? -1 : 1;
            Monitor.openId(keys[i]);
        }
        function step(dir) {
            go((at >= 0 ? at : last - dir) + dir);
        }

        onAtChanged: if (at >= 0) last = at
        z: 40
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(12)
        anchors.top: fullBtn.bottom
        anchors.topMargin: Theme.px(8)
        width: Theme.px(40)
        height: quickCol.implicitHeight + Theme.px(8)
        radius: width / 2
        color: Qt.alpha(Look.bg, 0.82)

        Rectangle {
            visible: quick.at >= 0
            x: Theme.px(4)
            y: Theme.px(4) + quick.last * Theme.px(32)
            width: Theme.px(32)
            height: width
            radius: width / 2
            color: Qt.alpha(Look.text, 0.16)

            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Column {
            id: quickCol

            x: Theme.px(4)
            y: Theme.px(4)

            Repeater {
                model: [Icons.cpu, Icons.memory, Icons.thermometer, Icons.disk]

                Item {
                    required property int index
                    required property string modelData

                    width: Theme.px(32)
                    height: width

                    Icon {
                        anchors.centerIn: parent
                        text: parent.modelData
                        size: 15
                        color: quick.at === parent.index || quickArea.containsMouse ? Look.text : Look.muted

                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    MouseArea {
                        id: quickArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: quick.go(parent.index)
                    }
                }
            }
        }

        // a wheel click is one step; a touchpad swipe counts once
        Timer {
            id: quickSwipe

            property bool locked: false

            interval: 220
            onTriggered: {
                locked = false;
                quick.wheelAcc = 0;
            }
        }

        WheelHandler {
            orientation: Qt.Vertical
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: e => {
                const d = e.angleDelta.y;
                if (d === 0)
                    return;
                if (!quickSwipe.running && Math.abs(d) % 120 === 0) {
                    quick.step(d < 0 ? 1 : -1);
                    return;
                }
                if (Math.abs(d) >= 120)
                    return;
                const locked = quickSwipe.locked;
                quickSwipe.restart();
                if (locked)
                    return;
                quick.wheelAcc += d;
                if (Math.abs(quick.wheelAcc) < 120)
                    return;
                quick.step(quick.wheelAcc < 0 ? 1 : -1);
                quick.wheelAcc = 0;
                quickSwipe.locked = true;
            }
        }
    }

    // An open bubble: the field stays (dimmed, the bubble ringed) and its
    // page slides in from the left.
    Item {
        id: glass

        readonly property real e: Monitor.ov ? Monitor.ov.e : 0

        anchors.fill: parent
        z: 30
        visible: !!Monitor.ov

        Rectangle {
            anchors.fill: parent
            color: Look.bg
            opacity: 0.22 * glass.e

            // a bubble shows its page; anywhere else closes it
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: m => {
                    const w = Monitor.toWorld({ x: m.x, y: m.y }), n = Monitor.world.hit(w.x, w.y);
                    if (n && !n.dying)
                        Monitor.openId(n.id);
                    else
                        Monitor.closeOverlay();
                }
                onWheel: w => w.accepted = true
            }
        }

        Rectangle {
            readonly property real rr: Monitor.ov ? Monitor.ov.r + Theme.px(7) : 0

            x: (Monitor.ov ? Monitor.ov.x : 0) - rr
            y: (Monitor.ov ? Monitor.ov.y : 0) - rr
            width: 2 * rr
            height: width
            radius: rr
            color: "transparent"
            border.width: Theme.px(2)
            border.color: Monitor.ov ? Monitor.ov.color : "transparent"
            opacity: glass.e
        }

        // one sheet down the whole left side: 40 % of the popup, 30 % of the screen
        InfoPanel {
            id: card

            width: Math.round(parent.width * (Monitor.full ? 0.3 : 0.4))
            height: parent.height
            x: -width * (1 - glass.e)
            onWidthChanged: page.measure()
        }
    }

    // one side of the Processes / Apps switch
    component ModeSeg: Item {
        id: seg

        property string label
        property string value
        readonly property bool on: Monitor.mode === value

        width: segText.implicitWidth + Theme.px(28)
        height: Theme.px(32)

        Text {
            id: segText

            anchors.centerIn: parent
            text: seg.label
            font.family: Look.font
            font.pixelSize: Theme.px(12)
            color: seg.on || segArea.containsMouse ? Look.text : Look.muted

            Behavior on color { ColorAnimation { duration: 200 } }
        }

        MouseArea {
            id: segArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Monitor.mode = seg.value
        }
    }
}
