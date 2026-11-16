import QtQuick
import qs.core
import qs.widgets
import qs.plugins.bubble

// This machine as bubbles drifting in space: dials for CPU, memory,
// temperature, network and disk, and the busiest processes, the open apps
// (each app's windows and everything they started, white) or both, picked top
// left. They drift on their own, knock with a soft sound and flatten when
// packed; behind them endless space with a black hole. A tapped bubble's page
// slides in on the left and the camera keeps that bubble in the middle of what
// is left; the buttons on the right (CPU, memory, temperature, disk; the wheel
// steps through them) open those pages. Field.qml draws the field, Monitor.qml
// holds the state, InfoPanel.qml a bubble's page.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the System page's Bubble style, BubbleMonitor.qml at
// 1909479, descended from ilyamiro's Serpantinum. Here it is a popup of its
// own, without the full-screen mode.
PopupPage {
    id: popup

    implicitWidth: Theme.px(1260)
    implicitHeight: Theme.px(860)
    placement: "center"

    Component.onCompleted: Monitor.active = true
    Component.onDestruction: {
        Monitor.active = false;
        Monitor.release();
        Monitor.closeNow();
    }
    // Escape closes an open bubble's page before the popup.
    Keys.onEscapePressed: event => {
        if (Monitor.ms.open)
            Monitor.closeOverlay();
        else
            event.accepted = false;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Look.bg
        clip: true

        Field {
            id: field

            anchors.fill: parent
            onWidthChanged: popup.measure()
            onHeightChanged: popup.measure()
        }

        // Processes, apps or both, top left: the mark slides to the one picked.
        // Out of the way while a page is open on the left.
        Rectangle {
            x: Theme.px(12)
            y: Theme.px(12)
            z: 20
            width: modeRow.implicitWidth + Theme.px(8)
            height: Theme.px(40)
            radius: height / 2
            color: Qt.alpha(Look.bg, 0.82)
            opacity: 1 - glass.e

            Rectangle {
                readonly property Item on: Monitor.mode === "apps" ? appsSeg : Monitor.mode === "both" ? bothSeg : procsSeg

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
                ModeSeg { id: bothSeg; label: "Both"; value: "both" }
            }
        }

        // the battery, top right, if there is one: a drawn battery lying down,
        // filled to the charge, the percentage under it
        Rectangle {
            id: batteryBadge

            readonly property real pct: Monitor.battery ? Monitor.battery.pct : 0
            readonly property bool low: pct <= 20 && !(Monitor.battery && Monitor.battery.plugged)

            visible: !!Monitor.battery
            z: 40
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.px(12)
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
            anchors.top: batteryBadge.visible ? batteryBadge.bottom : parent.top
            anchors.topMargin: batteryBadge.visible ? Theme.px(8) : Theme.px(12)
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
                    model: ["󰻠", "󰍛", "󰔏", "󰋊"]

                    Item {
                        required property int index
                        required property string modelData

                        width: Theme.px(32)
                        height: width

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(15)
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

            InfoPanel {
                id: card

                width: Math.round(parent.width * 0.4)
                height: parent.height
                x: -width * (1 - glass.e)
                onWidthChanged: popup.measure()
            }
        }
    }

    // Monitor works out the camera from the sizes it is drawn at.
    function measure() {
        Monitor.viewW = Math.max(1, field.width);
        Monitor.viewH = Math.max(1, field.height);
        Monitor.cardW = card.width;
        if (!Monitor.camReady && field.width > 1 && field.height > 1)
            Monitor.placeCamera();
    }

    // one side of the Processes / Apps / Both switch
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
