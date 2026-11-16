import QtQuick
import QtQuick.Shapes
import qs.plugins.bubble
import "BubbleLogic.js" as B

// One bubble: a process (by kind, paused dashed, hot ring), an open app
// (white) or a metric dial. The world moves its node in place every frame;
// Monitor.frame() hands each bubble just the numbers that move (sync), so a
// bubble redraws only what changed. Sizes are world units: the camera scales them.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the Bubble component of BubbleMonitor.qml at 1909479,
// restyled with Fableland's theme (Look.qml).
Item {
    id: bub

    required property string nid
    property string type: ""
    property string key: ""
    property string kind: ""
    property string name: ""
    property real rad: 0
    property real sq: 0
    property real sqA: 0
    property real wv: 0
    property bool grab: false
    property bool paused: false
    property bool hot: false
    property string value: ""                 // the number under the name
    property real pct: 0.01                   // a dial's arc, in steps of 0.5 % (it redraws only when it moves)
    property real dialRad: 0                  // the dial's size, in half units (the same)

    readonly property bool metric: type === "metric"
    readonly property bool app: type === "group"
    readonly property real lift: grab ? 1.08 : 1
    readonly property color fillColor: app ? Look.white : metric ? Look.panel : paused ? "transparent" : kind === "dev" ? Look.accent : kind === "sys" ? Look.panel : Look.text
    readonly property color textColor: metric ? Look.text : paused ? Look.muted : kind === "sys" ? Look.text : Look.ink

    function sync(o) {
        type = o.type; key = o.key || ""; kind = o.kind || ""; name = o.name || "";
        rad = o.ef; x = o.x - o.ef; y = o.y - o.ef;
        sq = o.sq; sqA = o.sqA; wv = o.w * Math.sin(o.ph);
        grab = !!o.grab; paused = !!o.paused;
        hot = o.type !== "metric" && o.cpu > Monitor.hotCpu && !o.paused && !o.dying;
        if (o.type === "metric") {
            pct = Math.round(Monitor.dialFrac(key) * 200) / 200;
            dialRad = Math.round(o.ef * 2) / 2;
            value = Monitor.dialText(key);
        } else {
            value = o.paused ? "Paused" : o.cpu.toFixed(o.cpu < 10 ? 1 : 0) + "%";
        }
    }

    Component.onCompleted: {
        Monitor.bubbleItems[nid] = bub;
        const o = Monitor.world.find(nid);
        if (o)
            sync(o);
    }
    Component.onDestruction: delete Monitor.bubbleItems[nid]

    width: 2 * rad
    height: 2 * rad
    z: grab ? 10 : 0
    // flattened along where it is pressed (turned to that line, squeezed, turned back), then the jelly wobble
    transform: [
        Rotation { origin.x: bub.rad; origin.y: bub.rad; angle: -bub.sqA },
        Scale { origin.x: bub.rad; origin.y: bub.rad; xScale: 1 - bub.sq; yScale: 1 + bub.sq * 0.55 },
        Rotation { origin.x: bub.rad; origin.y: bub.rad; angle: bub.sqA },
        Scale { origin.x: bub.rad; origin.y: bub.rad; xScale: (1 + bub.wv) * bub.lift; yScale: (1 - bub.wv) * bub.lift }
    ]

    // a pulsing ring above Monitor.hotCpu
    Rectangle {
        property real grow: 0

        visible: bub.hot
        anchors.centerIn: parent
        width: bub.width + 2 * grow
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Look.hot
        opacity: 0.6 * (1 - grow / 18)

        NumberAnimation on grow {
            running: bub.hot
            from: 0
            to: 18
            duration: 1600
            loops: Animation.Infinite
            easing.type: Easing.OutCubic
        }
    }

    // an open app: a soft white halo round it
    Rectangle {
        visible: bub.app
        anchors.centerIn: parent
        width: bub.width + 10
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Qt.alpha(Look.white, 0.3)
    }

    // lifted while held
    Rectangle {
        visible: bub.grab
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 10
        width: bub.width + 8
        height: width
        radius: width / 2
        color: Qt.alpha("#000000", 0.35)
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: bub.fillColor
        border.width: bub.metric ? 1 : (!bub.paused && bub.kind === "sys" ? 1.5 : 0)
        border.color: bub.metric ? Look.line : Look.muted
    }

    // paused: a dashed outline
    Shape {
        visible: bub.paused
        anchors.fill: parent

        ShapePath {
            strokeColor: Look.line2
            strokeWidth: 1.5
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 3]

            PathAngleArc { centerX: bub.rad; centerY: bub.rad; radiusX: Math.max(0, bub.rad - 1); radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
        }
    }

    // a dial: track and the metric's arc, centred on the bubble
    Shape {
        visible: bub.metric
        x: bub.rad - bub.dialRad
        y: x
        width: 2 * bub.dialRad
        height: width

        ShapePath {
            strokeColor: Look.line
            strokeWidth: bub.dialRad * 0.1
            fillColor: "transparent"

            PathAngleArc { centerX: bub.dialRad; centerY: bub.dialRad; radiusX: bub.dialRad * 0.9; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
        }

        ShapePath {
            strokeColor: bub.metric ? Look.metricColor(bub.key) : "transparent"
            strokeWidth: bub.dialRad * 0.1
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc { centerX: bub.dialRad; centerY: bub.dialRad; radiusX: bub.dialRad * 0.9; radiusY: radiusX; startAngle: -90; sweepAngle: bub.pct * 360 }
        }
    }

    Column {
        readonly property bool tiny: !bub.metric && bub.rad * Monitor.camZ < 22 * Monitor.zoomMax
        readonly property bool small: !bub.metric && bub.rad < 42

        anchors.centerIn: parent
        spacing: 1
        visible: !tiny

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: bub.metric && bub.key === "net" ? "Net ↓" : bub.name
            width: Math.min(implicitWidth, bub.rad * 2 - 14)
            elide: Text.ElideRight
            font.family: Look.font
            font.pixelSize: Math.round(bub.metric ? Math.max(6, bub.rad * 0.17) : B.clamp(bub.rad * 0.28, 10, 19))
            font.weight: bub.metric ? Font.Normal : Font.DemiBold
            color: bub.metric ? Look.muted : bub.textColor
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !parent.small
            text: bub.value
            font.family: Look.font
            font.pixelSize: Math.round(bub.metric ? Math.max(8, bub.rad * 0.4) : B.clamp(bub.rad * 0.2, 7, 14))
            font.weight: bub.metric ? Font.Medium : Font.Normal
            opacity: bub.metric ? 1 : 0.75
            color: bub.textColor
        }
    }
}
