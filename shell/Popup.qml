import QtQuick
import qs.core
import qs.widgets
import qs.plugins.bubble

// This machine as bubbles drifting in space: dials for CPU, memory,
// temperature, network and disk, and the busiest processes or the open apps
// (each app's windows and everything they started, white). They drift on
// their own, knock with a soft sound and flatten when packed; behind them
// endless space with a black hole. The button top right takes it full screen,
// where processes and apps show together.
//
// Page.qml is the page, Field.qml its field of bubbles, InfoPanel.qml an open
// bubble's page; Monitor.qml holds the state and FullScreen.qml takes the page
// to the whole screen and back.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the System page's Bubble style, BubbleMonitor.qml at
// 1909479, descended from ilyamiro's Serpantinum. Here it is a popup of its own.
PopupPage {
    implicitWidth: Theme.px(1260)
    implicitHeight: Theme.px(860)
    placement: "center"

    Component.onCompleted: Monitor.active = true
    Component.onDestruction: {
        Monitor.active = false;
        Monitor.release();
        Monitor.closeNow();
        Monitor.quitFull();
    }

    // the page's place: empty while it is full screen
    Item {
        id: home

        anchors.fill: parent

        Page {
            id: page

            anchors.fill: parent
            onFullToggled: fullScreen.toggle()
        }
    }

    FullScreen {
        id: fullScreen

        page: page
        home: home
    }
}
