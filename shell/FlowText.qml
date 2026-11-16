import QtQuick

// Text whose number glides to each new value (counting through the ones
// between); the words round it stay put.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the FlowText component of BubbleMonitor.qml at 1909479.
Text {
    id: flow

    property string target: ""
    readonly property var match: /-?\d+(?:\.\d+)?/.exec(target)
    readonly property real goal: match ? parseFloat(match[0]) : 0
    readonly property int decimals: match && match[0].indexOf(".") >= 0 ? match[0].length - match[0].indexOf(".") - 1 : 0
    property real shown: 0
    property bool ready: false

    Behavior on shown {
        enabled: flow.ready

        NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
    }

    onGoalChanged: shown = goal
    Component.onCompleted: {
        shown = goal;
        ready = true;
    }
    text: match ? target.slice(0, match.index) + shown.toFixed(decimals) + target.slice(match.index + match[0].length) : target
}
