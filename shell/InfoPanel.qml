import QtQuick
import QtQuick.Shapes
import qs.core
import qs.widgets
import qs.plugins.bubble
import "BubbleLogic.js" as B

// The open bubble's page, one sheet down the left side. Another bubble's page
// takes its place by moving up: the old one goes up and away, the new one
// comes up from below (two pages taking turns); stepped back up the buttons,
// the same downwards.
//
// A page, the same order for every kind: its shape and title with a line under
// it, the number, how it looks (a chart, water or a gauge), facts in two
// columns, lists.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): InfoPanel, InfoPage and the pieces they draw with in
// BubbleMonitor.qml at 1909479; sizes follow Fableland's UI scale.
Rectangle {
    id: panel

    readonly property var d: Monitor.info
    readonly property bool big: Monitor.full     // full screen: taller charts, whole lists
    property var oldD: null
    property bool flip: false            // which page is the live one
    property string lastKey: ""
    property var lastD: null
    property real swap: 1                // 0 → 1 while one page gives way to the other
    property int dir: 1                  // up (1) or down (-1), taken from Monitor.swapDir as it starts

    onDChanged: {
        const k = d ? (d.id || d.kind) : "";
        if (k === "") {
            lastKey = "";
            lastD = null;
            return;
        }
        if (lastKey !== "" && k !== lastKey) {
            oldD = lastD;
            flip = !flip;
            dir = Monitor.swapDir;
            Monitor.swapDir = 1;
            swapAnim.restart();
        }
        lastKey = k;
        lastD = d;
    }

    color: Qt.alpha(Theme.mantle, 0.96)
    clip: true

    NumberAnimation { id: swapAnim; target: panel; property: "swap"; from: 0; to: 1; duration: 460; easing.type: Easing.OutCubic }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: w => w.accepted = true
    }

    Repeater {
        model: 2

        InfoPage {
            required property int index
            readonly property bool live: (index === 1) === panel.flip

            x: Theme.px(22)
            width: panel.width - Theme.px(44)
            // the old one is gone before the new one is halfway up, so they never sit on each other
            y: live ? Theme.px(22) + Theme.px(80) * panel.dir * (1 - panel.swap) : Theme.px(22) - Theme.px(80) * panel.dir * panel.swap
            opacity: live ? B.clamp((panel.swap - 0.12) * 1.8, 0, 1) : B.clamp(1 - panel.swap * 2.4, 0, 1)
            visible: live || panel.swap < 1
            d: live ? panel.d : panel.oldD
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.px(16)
        width: Theme.px(32)
        height: width
        radius: width / 2
        color: closeArea.containsMouse ? Look.line : "transparent"

        Behavior on color { ColorAnimation { duration: 140 } }

        Icon {
            anchors.centerIn: parent
            text: Icons.close
            size: 14
            color: Look.text
        }

        MouseArea {
            id: closeArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Monitor.closeOverlay()
        }
    }

    component InfoPage: Column {
        id: info

        property var d: null
        readonly property string kind: d ? d.kind : ""

        spacing: Theme.px(16)

        Column {
            width: parent.width
            spacing: Theme.px(4)

            Row {
                spacing: Theme.px(10)

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: info.kind
                    color: info.d ? info.d.color : "transparent"
                }

                Text {
                    width: Math.min(implicitWidth, info.width - Theme.px(60))
                    elide: Text.ElideRight
                    text: info.d ? info.d.title : ""
                    font.family: Look.font
                    font.pixelSize: Theme.px(20)
                    font.weight: Font.DemiBold
                    color: Monitor.fg
                }
            }

            Text {
                width: parent.width - Theme.px(40)
                elide: Text.ElideRight
                text: info.d ? info.d.sub : ""
                font.family: Look.font
                font.pixelSize: Theme.px(12)
                color: Qt.alpha(Monitor.fg, 0.62)
            }
        }

        Row {
            FlowText {
                id: infoNum

                target: info.d ? info.d.num : ""
                font.family: Look.font
                font.pixelSize: Theme.px(56)
                font.weight: Font.DemiBold
                color: info.d ? info.d.color : Monitor.fg
            }

            Text {
                anchors.baseline: infoNum.baseline
                text: info.d ? "  " + info.d.unit : ""
                font.family: Look.font
                font.pixelSize: Theme.px(15)
                color: Qt.alpha(Monitor.fg, 0.62)
            }
        }

        Loader {
            width: parent.width
            sourceComponent: ({ cpu: cpuLook, mem: memLook, temp: tempLook, net: ioLook, disk: ioLook, app: histLook, group: histLook })[info.kind] || null
        }

        Facts { items: info.d ? info.d.facts : [] }
        InfoList { list: info.d ? info.d.list2 : null }
        InfoList { list: info.d ? info.d.list : null }

        // CPU: its history, and every thread as a glass of water filled to how busy it is
        Component {
            id: cpuLook

            Column {
                width: parent ? parent.width : 0
                spacing: Theme.px(12)

                Rectangle {
                    width: parent.width
                    height: Theme.px(panel.big ? 96 : 72)
                    radius: Theme.px(12)
                    color: Qt.alpha(Monitor.fg, 0.06)

                    Chart {
                        anchors.fill: parent
                        anchors.margins: Theme.px(6)
                        values: info.d ? info.d.hist : []
                    }
                }

                // a row of glasses per 16 threads, so a big processor still fits
                Grid {
                    id: coreGrid

                    readonly property var cores: info.d ? info.d.cores : []
                    readonly property real cell: (width - spacing * (columns - 1)) / columns

                    width: parent.width
                    columns: Math.min(16, Math.max(1, cores.length))
                    spacing: Theme.px(5)

                    Repeater {
                        model: coreGrid.cores.length

                        Column {
                            required property int index
                            readonly property real v: coreGrid.cores[index] || 0

                            width: coreGrid.cell
                            spacing: Theme.px(4)

                            Rectangle {
                                width: parent.width
                                height: Theme.px(40)
                                radius: Theme.px(6)
                                color: Qt.alpha(Monitor.fg, 0.08)

                                Water {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    level: parent.parent.v / 100
                                    period: 2400 + parent.parent.index * 260
                                }
                            }

                            FlowText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                target: String(Math.round(parent.v))
                                font.family: Look.font
                                font.pixelSize: Theme.px(11)
                                color: Qt.alpha(Monitor.fg, 0.7)
                            }
                        }
                    }
                }
            }
        }

        // memory: what holds it, in one bar
        Component {
            id: memLook

            Column {
                width: parent ? parent.width : 0
                spacing: Theme.px(10)

                Rectangle {
                    width: parent.width
                    height: Theme.px(22)
                    radius: Theme.px(8)
                    color: Qt.alpha(Monitor.fg, 0.1)
                    clip: true

                    Row {
                        spacing: Theme.px(3)

                        Rectangle {
                            width: info.d ? parent.parent.width * info.d.memApps / Monitor.vTotal : 0
                            height: Theme.px(22)
                            radius: Theme.px(8)
                            color: Monitor.fgAccent

                            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            width: info.d ? parent.parent.width * info.d.memCache / Monitor.vTotal : 0
                            height: Theme.px(22)
                            radius: Theme.px(8)
                            color: Qt.alpha(Monitor.fg, 0.4)

                            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                Legend {
                    items: info.d ? [{ t: "Apps " + info.d.memApps.toFixed(1), a: 1 }, { t: "Cache " + info.d.memCache.toFixed(1), a: 0.4 },
                                     { t: "Free " + info.d.memFree.toFixed(1), a: 0.12 }] : []
                }
            }
        }

        // temperature: where it sits from 30 to 100 °C
        Component {
            id: tempLook

            Item {
                readonly property real pct: B.clamp((Monitor.vTemp - 30) / 70, 0, 1)

                width: parent ? parent.width : 0
                height: Theme.px(62)

                Rectangle {
                    x: (parent.width - width) * parent.pct
                    width: markText.implicitWidth + Theme.px(20)
                    height: Theme.px(22)
                    radius: height / 2
                    color: Monitor.fgAccent

                    FlowText {
                        id: markText

                        anchors.centerIn: parent
                        target: Math.round(Monitor.vTemp) + "°C"
                        font.family: Look.font
                        font.pixelSize: Theme.px(12)
                        font.weight: Font.Medium
                        color: Look.ink
                    }
                }

                Rectangle {
                    y: Theme.px(30)
                    width: parent.width
                    height: Theme.px(8)
                    radius: height / 2
                    color: Qt.alpha(Monitor.fg, 0.1)
                    clip: true

                    Rectangle {
                        width: parent.width * parent.parent.pct
                        height: parent.height
                        radius: height / 2
                        color: Monitor.fgAccent
                    }
                }

                Repeater {
                    model: [{ t: "30°", f: 0 }, { t: "50°", f: 0.286 }, { t: "70°", f: 0.571 }, { t: "90°", f: 0.857 }, { t: "100°", f: 1 }]

                    Text {
                        required property var modelData

                        y: Theme.px(46)
                        x: modelData.f === 0 ? 0 : modelData.f === 1 ? parent.width - implicitWidth : parent.width * modelData.f - implicitWidth / 2
                        text: modelData.t
                        font.family: Look.font
                        font.pixelSize: Theme.px(11)
                        color: Qt.alpha(Monitor.fg, 0.62)
                    }
                }
            }
        }

        // network and disk: both ways at once, one above the middle and one
        // below, as smooth lines; which is which in the box's corner
        Component {
            id: ioLook

            Rectangle {
                id: ioBox

                readonly property var io: info.d && info.d.io ? info.d.io : null
                readonly property var lines: io && io.up.length > 2 ? B.twoWay(io.up, io.down, Monitor.phase, width - Theme.px(12), height, io.maxUp, io.maxDown, 40) : null

                width: parent ? parent.width : 0
                height: Theme.px(panel.big ? 150 : 118)
                radius: Theme.px(12)
                color: Qt.alpha(Monitor.fg, 0.06)
                clip: true

                Rectangle {
                    y: parent.height / 2
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Monitor.fg, 0.12)
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath { strokeColor: "transparent"; fillColor: Qt.alpha(Monitor.fgAccent, 0.14); PathSvg { path: ioBox.lines ? ioBox.lines.upArea : "M0,0" } }
                    ShapePath { strokeColor: "transparent"; fillColor: Qt.alpha(Monitor.fg, 0.08); PathSvg { path: ioBox.lines ? ioBox.lines.downArea : "M0,0" } }
                    ShapePath {
                        strokeColor: Monitor.fgAccent; strokeWidth: Theme.px(2.6); fillColor: "transparent"
                        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                        PathSvg { path: ioBox.lines ? ioBox.lines.upLine : "M0,0" }
                    }
                    ShapePath {
                        strokeColor: Qt.alpha(Monitor.fg, 0.6); strokeWidth: Theme.px(2.6); fillColor: "transparent"
                        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                        PathSvg { path: ioBox.lines ? ioBox.lines.downLine : "M0,0" }
                    }
                }

                Dot { visible: !!ioBox.lines; color: Monitor.fgAccent; cx: ioBox.width - Theme.px(12); cy: ioBox.lines ? ioBox.lines.upY : 0 }
                Dot { visible: !!ioBox.lines; color: Qt.alpha(Monitor.fg, 0.8); cx: ioBox.width - Theme.px(12); cy: ioBox.lines ? ioBox.lines.downY : 0 }

                Legend {
                    x: Theme.px(12)
                    y: Theme.px(10)
                    spacing: Theme.px(14)
                    items: info.d && info.d.legend ? [{ t: info.d.legend[0], a: 1 }, { t: info.d.legend[1], a: 0.6 }] : []
                }
            }
        }

        // a process or an app: its CPU over time
        Component {
            id: histLook

            Rectangle {
                width: parent ? parent.width : 0
                height: Theme.px(80)
                radius: Theme.px(12)
                color: Qt.alpha(Monitor.fg, 0.06)

                Chart {
                    anchors.fill: parent
                    anchors.margins: Theme.px(6)
                    values: info.d && info.d.hist ? info.d.hist : []
                }
            }
        }
    }

    // the shape beside a page's title, one for each kind, slowly turning
    component Glyph: Item {
        id: glyph

        property string kind
        property color color
        // its outline as points on a 14 × 14 square, drawn at the UI's scale
        readonly property var points: {
            const c = 7, poly = (n, r, a0) => Array.from({ length: n }, (_, i) => [c + Math.cos(a0 + i * 2 * Math.PI / n) * r, c + Math.sin(a0 + i * 2 * Math.PI / n) * r]);
            if (kind === "cpu") return poly(4, 7.6, Math.PI / 4);                       // square
            if (kind === "mem") return poly(6, 7, 0);                                    // hexagon
            if (kind === "temp") return poly(3, 7.6, -Math.PI / 2);                      // triangle
            if (kind === "net") return [[7, 0], [11.5, 7], [7, 14], [2.5, 7]];          // narrow diamond
            if (kind === "disk") return poly(5, 7.2, -Math.PI / 2);                      // pentagon
            if (kind === "app")                                                          // four-point star
                return Array.from({ length: 8 }, (_, i) => [c + Math.cos(-Math.PI / 2 + i * Math.PI / 4) * (i % 2 ? 2.6 : 7), c + Math.sin(-Math.PI / 2 + i * Math.PI / 4) * (i % 2 ? 2.6 : 7)]);
            return [[5, 0], [9, 0], [9, 5], [14, 5], [14, 9], [9, 9], [9, 14], [5, 14], [5, 9], [0, 9], [0, 5], [5, 5]];   // a cross, an app
        }
        readonly property string path: points.map((p, i) => (i ? "L" : "M") + (p[0] * Theme.scale).toFixed(2) + "," + (p[1] * Theme.scale).toFixed(2)).join(" ") + " Z"

        width: Theme.px(14)
        height: width

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath { strokeColor: glyph.color; strokeWidth: 1; joinStyle: ShapePath.RoundJoin; fillColor: glyph.color; PathSvg { path: glyph.path } }
        }

        RotationAnimation on rotation { running: glyph.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 8000 }
    }

    // a pulsing dot where a line ends
    component Dot: Item {
        id: dot

        property color color: Look.accent
        property real cx: 0
        property real cy: 0

        x: cx
        y: cy

        Rectangle { x: -Theme.px(8); y: x; width: Theme.px(16); height: width; radius: width / 2; color: Qt.alpha(dot.color, 0.25) }
        Rectangle { x: -Theme.px(4); y: x; width: Theme.px(8); height: width; radius: width / 2; color: dot.color }
    }

    // a list on a page: its heading and rows (in the popup as many as fit, `list.panel`)
    component InfoList: Column {
        id: infoList

        property var list: null
        readonly property var rows: !list ? [] : list.panel && !panel.big ? list.rows.slice(0, list.panel) : list.rows

        visible: rows.length > 0
        width: parent.width
        spacing: Theme.px(8)

        Text {
            text: infoList.list ? infoList.list.title : ""
            font.family: Look.font
            font.pixelSize: Theme.px(12)
            color: Qt.alpha(Monitor.fg, 0.62)
        }

        RankRows { rows: infoList.rows }
    }

    // a key on a chart: a dot (a share of the page's colour) and words for each
    component Legend: Row {
        id: legend

        property var items: []        // [{ t, a }]

        spacing: Theme.px(18)

        Repeater {
            model: legend.items.length

            Row {
                required property int index
                readonly property var it: legend.items[index] || ({ t: "", a: 1 })

                spacing: Theme.px(7)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.px(8)
                    height: width
                    radius: width / 2
                    color: parent.it.a === 1 ? Monitor.fgAccent : Qt.alpha(Monitor.fg, parent.it.a)
                }

                FlowText { target: parent.it.t; font.family: Look.font; font.pixelSize: Theme.px(12); color: Monitor.fg }
            }
        }
    }

    // facts in two columns: a label, and a value that glides
    component Facts: Grid {
        id: facts

        property var items: []        // [{ lbl, val }]

        width: parent.width
        columns: 2
        rowSpacing: Theme.px(14)
        columnSpacing: Theme.px(12)

        Repeater {
            model: facts.items.length

            Column {
                required property int index
                readonly property var it: facts.items[index] || ({ lbl: "", val: "" })

                width: (facts.width - facts.columnSpacing) / 2
                spacing: Theme.px(3)

                Text { width: parent.width; elide: Text.ElideRight; text: parent.it.lbl; font.family: Look.font; font.pixelSize: Theme.px(12); color: Qt.alpha(Monitor.fg, 0.62) }
                FlowText { width: parent.width; elide: Text.ElideRight; target: parent.it.val; font.family: Look.font; font.pixelSize: Theme.px(17); font.weight: Font.Medium; color: Monitor.fg }
            }
        }
    }

    // a ranked list: name, a thin bar, the value; a row that is a bubble opens it
    component RankRows: Column {
        id: ranks

        property var rows: []         // [{ id?, name, frac 0..1 (no bar without), val? }]

        width: parent.width

        Repeater {
            model: ranks.rows.length

            Item {
                id: rankRow

                required property int index
                readonly property var it: ranks.rows[index] || ({ name: "" })
                readonly property bool bar: it.frac !== undefined
                readonly property real nameW: bar ? Math.min(Theme.px(160), width * 0.36) : width - Theme.px(16)

                width: ranks.width
                height: Theme.px(30)

                Rectangle {
                    x: -Theme.px(8)
                    width: parent.width + Theme.px(16)
                    height: parent.height
                    radius: Theme.radiusSmall
                    color: Qt.alpha(Monitor.fg, rankArea.containsMouse && rankRow.it.id ? 0.08 : 0)

                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Text {
                    width: rankRow.nameW
                    anchors.verticalCenter: parent.verticalCenter
                    text: rankRow.it.name
                    elide: Text.ElideRight
                    font.family: Look.font
                    font.pixelSize: Theme.px(13)
                    color: Monitor.fg
                }

                Rectangle {
                    visible: rankRow.bar
                    x: rankRow.nameW + Theme.px(14)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - x - rankVal.implicitWidth - Theme.px(14))
                    height: Theme.px(4)
                    radius: height / 2
                    color: Qt.alpha(Monitor.fg, 0.1)

                    Rectangle {
                        width: parent.width * B.clamp(rankRow.it.frac || 0, 0, 1)
                        height: parent.height
                        radius: height / 2
                        color: Monitor.fgAccent

                        Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                    }
                }

                FlowText {
                    id: rankVal

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    target: rankRow.it.val || ""
                    font.family: Look.font
                    font.pixelSize: Theme.px(13)
                    color: Monitor.fg
                }

                MouseArea {
                    id: rankArea

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !!rankRow.it.id
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Monitor.openId(rankRow.it.id)
                }
            }
        }
    }

    // A history as the scan dot: the last samples laid across the width and a
    // dot running over them once per sample, only the stretch just behind it
    // drawn, fading out backwards.
    component Chart: Item {
        id: chart

        property var values: []
        property var toFrac: function (v) { return B.clamp(v, 0, 100) / 100; }    // 0 bottom .. 1 top
        property int span: 40              // samples across the width
        property color lineColor: Monitor.fgAccent
        readonly property int used: Math.min(span, values.length - 1)      // a process's history is shorter
        readonly property var comet: used >= 3
            ? B.comet(values.slice(-used), values.slice(-used - 1, -1), Monitor.sweep, width, height, chart.toFrac, 0.32, 8, 14) : null

        clip: true

        Repeater {
            model: 8

            Shape {
                id: tailPart

                required property int index

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: Qt.alpha(chart.lineColor, (tailPart.index + 1) / 8); strokeWidth: Theme.px(2.6); fillColor: "transparent"
                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: chart.comet ? chart.comet.segs[tailPart.index] : "M0,0" }
                }
            }
        }

        Dot { visible: !!chart.comet; color: chart.lineColor; cx: chart.comet ? chart.comet.x : 0; cy: chart.comet ? chart.comet.y : 0 }
    }
}
