pragma Singleton
import QtQuick
import Quickshell
import qs.core

// The Bubble monitor's colours and fonts, from the theme. From lukpednoi's
// Anserin (https://github.com/lukpednoi/Anserin, AGPL-3.0-or-later): the
// design's tokens in BubbleMonitor.qml, mapped onto Fableland's Theme.
Singleton {
    readonly property color bg: Theme.base
    readonly property color panel: Theme.surface0
    readonly property color line: Theme.surface1
    readonly property color line2: Theme.surface2
    readonly property color text: Theme.text
    readonly property color muted: Theme.subtext
    readonly property color ink: Theme.crust
    readonly property color accent: lift(Theme.accent)
    readonly property color hot: lift(Theme.red)
    readonly property color warm: lift(Theme.yellow)
    readonly property color sky: lift(Theme.secondary)
    readonly property color mint: lift(Theme.teal)
    readonly property color white: Qt.lighter(Theme.text, 1.12)      // the open apps' bubbles
    readonly property color bolt: Qt.tint(Theme.text, Qt.alpha(Theme.secondary, 0.35))
    readonly property string font: Theme.font

    // A data colour bright enough to read on the dark and to carry dark ink:
    // some generated palettes make it deep.
    function lift(c) {
        const l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return l >= 0.5 ? c : Qt.hsla(c.hslHue < 0 ? 0 : c.hslHue, Math.min(1, c.hslSaturation + 0.1), Math.max(c.hslLightness, 0.72), 1);
    }

    function kindColor(kind) {
        return kind === "dev" ? accent : kind === "sys" ? muted : text;
    }

    function metricColor(key) {
        return key === "cpu" ? accent : key === "mem" ? text : key === "temp" ? warm : key === "disk" ? mint : sky;
    }
}
