import QtQuick
import QtQuick.Shapes
import qs.plugins.bubble

// Where the bubbles drift: endless space behind them, the lightning between
// them, the world under Monitor's camera, and what the pointer does — tap a
// bubble to open its page, hold or drag one to carry it, drag the empty space
// to move, the wheel zooms 30–100 % in eased steps of 10 %.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the field of BubbleMonitor.qml at 1909479; the camera
// and state now live in Monitor.qml.
Item {
    id: field

    clip: true

    // Space, endless: a deep ground, far stars, the black hole, near stars. Each
    // layer moves a part of what the camera does (the farther, the less) and
    // grows a little with the zoom, so a drag reads as travel.
    Item {
        id: space

        // how far the world's centre is from the view's: the background's centre follows it (a part of it)
        readonly property real panX: Monitor.camX + Monitor.world.w / 2 * Monitor.camZ - field.width / 2
        readonly property real panY: Monitor.camY + Monitor.world.h / 2 * Monitor.camZ - field.height / 2
        readonly property real zoomT: (Monitor.camZ - Monitor.zoomMin) / (Monitor.zoomMax - Monitor.zoomMin)

        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: Qt.darker(Look.bg, 1.2)
        }

        StarLayer { source: "space/stars-far.png"; depth: 0.1; grow: 0.06 }

        Image {
            readonly property real k: (0.85 + 0.15 * space.zoomT) * Monitor.zoomMax

            width: 1150 * 0.7 * k
            height: 640 * 0.7 * k
            x: (field.width - width) / 2 + space.panX * 0.18
            y: (field.height - height) / 2 + space.panY * 0.18
            source: "space/black-hole.png"
            asynchronous: true
            smooth: true
        }

        StarLayer { source: "space/stars-near.png"; depth: 0.3; grow: 0.14 }
    }

    // the world, under the camera
    Item {
        width: Monitor.world.w
        height: Monitor.world.h
        transform: [
            Scale { xScale: Monitor.camZ; yScale: Monitor.camZ },
            Translate { x: Monitor.camX; y: Monitor.camY }
        ]

        Shape {
            id: lightning

            readonly property var bolts: {
                Monitor.tick;
                return Monitor.world.bolts;
            }

            anchors.fill: parent

            ShapePath {
                strokeColor: Qt.alpha(Look.sky, 0.22); strokeWidth: 7; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: (lightning.bolts.mid + lightning.bolts.strong) || "M0,0" }
            }
            ShapePath {
                strokeColor: Qt.alpha(Look.bolt, 0.35); strokeWidth: 1; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: lightning.bolts.weak || "M0,0" }
            }
            ShapePath {
                strokeColor: Qt.alpha(Look.bolt, 0.7); strokeWidth: 1.4; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: lightning.bolts.mid || "M0,0" }
            }
            ShapePath {
                strokeColor: Qt.lighter(Look.bolt, 1.05); strokeWidth: 2; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: lightning.bolts.strong || "M0,0" }
            }
        }

        Repeater {
            model: Monitor.bubbles

            Bubble {}
        }
    }

    // taps, holds, drags and the wheel
    MouseArea {
        property real wheelAcc: 0

        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        cursorShape: {
            Monitor.tick;
            return (Monitor.ms.pan || (Monitor.ms.press && Monitor.ms.press.drag)) ? Qt.ClosedHandCursor : Qt.OpenHandCursor;
        }
        onPressed: m => {
            const p = { x: m.x, y: m.y }, w = Monitor.toWorld(p), st = Monitor.ms;
            const n = Monitor.world.hit(w.x, w.y);
            st.camT = null;
            if (n)
                st.press = { id: n.id, sx: p.x, sy: p.y, wx: w.x, wy: w.y, t0: Date.now(), drag: false };
            else
                st.pan = { sx: p.x, sy: p.y, cx: Monitor.camX, cy: Monitor.camY };
        }
        onPositionChanged: m => {
            const p = { x: m.x, y: m.y }, st = Monitor.ms;
            if (st.press) {
                const w = Monitor.toWorld(p);
                st.press.wx = w.x; st.press.wy = w.y;
                if (!st.press.drag && Math.hypot(p.x - st.press.sx, p.y - st.press.sy) > 6)
                    Monitor.grab();
                if (st.press && st.press.drag)
                    Monitor.world.dragTarget = { x: w.x, y: w.y };
            } else if (st.pan) {
                Monitor.camX = st.pan.cx + p.x - st.pan.sx;
                Monitor.camY = st.pan.cy + p.y - st.pan.sy;
            }
        }
        onReleased: {
            const st = Monitor.ms;
            if (st.press) {
                if (!st.press.drag) {
                    const n = Monitor.world.find(st.press.id);
                    st.press = null;
                    if (n)
                        Monitor.openNode(n);
                } else {
                    Monitor.release();
                }
            }
            st.pan = null;
        }
        onCanceled: {
            Monitor.release();
            Monitor.ms.pan = null;
        }
        // a wheel click (or a swipe's worth) is one 10 % step
        onWheel: w => {
            wheelAcc += w.angleDelta.y;
            while (Math.abs(wheelAcc) >= 120) {
                Monitor.zoomStep({ x: w.x, y: w.y }, wheelAcc > 0 ? 1 : -1);
                wheelAcc -= wheelAcc > 0 ? 120 : -120;
            }
        }
    }

    // a layer of stars that repeats for ever, moved by `depth` of the camera's pan and grown by up to `grow` with the zoom
    component StarLayer: Item {
        id: layer

        property url source
        property real depth: 0.2
        property real grow: 0.1
        readonly property real k: 1 - layer.grow / 2 + layer.grow * space.zoomT
        readonly property real tile: 512

        anchors.fill: parent

        Item {
            anchors.fill: parent
            transform: Scale { origin.x: layer.width / 2; origin.y: layer.height / 2; xScale: layer.k; yScale: layer.k }

            Image {
                // a tile wider all round than the view, shifted by the pan modulo one tile: it never runs out
                readonly property real ox: ((space.panX * layer.depth / layer.k) % layer.tile + layer.tile) % layer.tile
                readonly property real oy: ((space.panY * layer.depth / layer.k) % layer.tile + layer.tile) % layer.tile

                source: layer.source
                fillMode: Image.Tile
                width: layer.width / layer.k + 4 * layer.tile
                height: layer.height / layer.k + 4 * layer.tile
                x: (layer.width - width) / 2 + ox
                y: (layer.height - height) / 2 + oy
                smooth: true
            }
        }
    }
}
