import QtQuick
import qs.plugins.bubble

// Water up to `level` with rolling waves (water.frag): one thread of the CPU's page.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the Water component of BubbleMonitor.qml at 1909479.
ShaderEffect {
    id: water

    property real level: 0
    property bool moving: true
    property int period: 2600
    property real radius: 6
    property real fillLevel: Math.max(0.04, Math.min(1, level))
    property real waveAmp: fillLevel < 0.99 ? 1.6 + 1.4 * Math.sin(fillLevel * Math.PI) : 0
    property vector2d itemSize: Qt.vector2d(width, height)
    property real phase: 0
    property color color1: Qt.lighter(Monitor.fgAccent, 1.15)
    property color color2: Monitor.fgAccent
    property color backColor: Qt.alpha(Monitor.fgAccent, 0.35)

    Behavior on fillLevel {
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    NumberAnimation on phase {
        running: water.visible && water.moving
        loops: Animation.Infinite
        from: 0
        to: Math.PI * 2
        duration: water.period
    }

    fragmentShader: Qt.resolvedUrl("water.frag.qsb")
}
