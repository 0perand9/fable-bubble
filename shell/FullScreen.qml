import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.plugins.bubble
import "BubbleLogic.js" as B

// Full screen and back. Going: the page moves out of the popup into this
// window at the same spot and is sucked like a cloth into its full-screen
// button, the parts nearest the button first (cloth.vert, drawing the page
// live); then the page takes the whole screen, and ink spreads from the button
// until it covers the screen, the full-screen monitor showing wherever it has
// reached (ink.frag). Coming back runs it backwards. The popup stays open
// underneath meanwhile, empty.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the full-screen part of BubbleMonitor.qml at 1909479.
// There the page left Anserin's side panel; here it leaves Fableland's popup.
Scope {
    id: root

    required property Item page          // what travels
    required property Item home          // its place in the popup

    property bool leaving: false
    property real t: 0                   // 0 in the popup … 1 full screen
    property rect slot: Qt.rect(0, 0, 1, 1)      // where the page is on the screen (set going full)
    // the middle of the full-screen button, in the page
    readonly property point button: Qt.point(slot.width - Theme.px(32), Theme.px(32))

    function toggle() {
        if (Monitor.full)
            leave();
        else
            enter();
    }

    function enter() {
        // the popup's window covers the screen, as this one does: its coordinates are the screen's
        const at = home.mapToItem(null, 0, 0);
        slot = Qt.rect(at.x, at.y, home.width, home.height);
        Monitor.goFull();
        page.parent = clothHolder;
        page.forceActiveFocus();
        run(0, 1, 1800);
    }

    function leave() {
        if (leaving || t < 1)
            return;
        Monitor.closeNow();
        leaving = true;
        run(1, 0, 1500);
    }

    function run(from, to, duration) {
        travel.stop();
        travel.from = from;
        travel.to = to;
        travel.duration = duration;
        travel.start();
    }

    // Halfway the page changes size: whole screen on the way out (the cloth
    // has gone into the button), its own on the way back (the ink has drawn in).
    onTChanged: {
        if (!Monitor.full)
            return;
        if (!leaving && t >= 0.5 && page.parent === clothHolder) {
            page.parent = screenHolder;
            Monitor.spread(win.width, win.height);
        } else if (leaving && t <= 0.5 && page.parent === screenHolder) {
            page.parent = clothHolder;
            Monitor.gather();
        }
    }

    NumberAnimation {
        id: travel

        target: root
        property: "t"
        onFinished: {
            if (root.t > 0)
                return;
            root.page.parent = root.home;
            Monitor.quitFull();
            root.leaving = false;
            root.page.forceActiveFocus();
        }
    }

    PanelWindow {
        id: win

        readonly property bool moving: root.t < 1 || root.leaving

        visible: Monitor.full
        screen: Ui.screen ?? Quickshell.screens[0]
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fable-bubble"
        WlrLayershell.keyboardFocus: Monitor.full ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // the page at the size of the screen: seen through the ink while that spreads, then as it is
        Item {
            id: screenHolder

            anchors.fill: parent
        }

        ShaderEffectSource {
            id: screenPicture

            anchors.fill: parent
            sourceItem: screenHolder
            hideSource: win.moving
            live: win.moving
            visible: false
        }

        // The page at its own size and place while it is the cloth (drawn only
        // through the cloth). Once it has gone to full size the cloth keeps
        // its last picture, for the little that is left of it.
        Item {
            id: clothHolder

            x: root.slot.x
            y: root.slot.y
            width: root.slot.width
            height: root.slot.height
        }

        ShaderEffectSource {
            id: clothPicture

            sourceItem: clothHolder
            hideSource: true
            live: root.page.parent === clothHolder
            visible: false
        }

        // the ink, spreading from the button once the cloth has gone in (0.5–1):
        // far enough to reach every corner even where its ragged edge lags most
        ShaderEffect {
            readonly property real spread: B.clamp((root.t - 0.5) / 0.5, 0, 1)
            readonly property point from: Qt.point(root.slot.x + root.button.x, root.slot.y + root.button.y)
            readonly property real reach: Math.max(Math.hypot(from.x, from.y), Math.hypot(width - from.x, from.y), Math.hypot(from.x, height - from.y), Math.hypot(width - from.x, height - from.y))
            property var source: screenPicture
            property vector2d res: Qt.vector2d(width, height)
            property vector2d center: Qt.vector2d(from.x, from.y)
            property real inkR: (1 - Math.pow(1 - spread, 3)) * (reach / 0.76 + 60)
            property real time: Monitor.clock % 1000
            property color inkColor: Qt.darker(Look.bg, 1.2)
            property color rimColor: Look.accent

            anchors.fill: parent
            visible: win.moving && root.t > 0.5
            fragmentShader: Qt.resolvedUrl("ink.frag.qsb")
        }

        // the cloth (0–0.6): the page on a fine mesh, sucked into its full-screen button
        ShaderEffect {
            property var source: clothPicture
            property real prog: B.clamp(root.t / 0.6, 0, 1)
            property real swirl: 1.2
            property real radius: Theme.radiusLarge
            property vector2d size: Qt.vector2d(width, height)
            property vector2d target: Qt.vector2d(root.button.x, root.button.y)

            x: root.slot.x
            y: root.slot.y
            width: root.slot.width
            height: root.slot.height
            visible: win.moving && root.t < 0.6
            mesh: GridMesh { resolution: Qt.size(44, 40) }
            vertexShader: Qt.resolvedUrl("cloth.vert.qsb")
            fragmentShader: Qt.resolvedUrl("cloth.frag.qsb")
        }

        // nothing is taken while it moves
        MouseArea {
            anchors.fill: parent
            enabled: win.moving
            acceptedButtons: Qt.AllButtons
        }
    }
}
