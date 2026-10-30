import QtQuick
import Ros2
import RQml.Utils

/**
 * Emits triggered() when it becomes active and on changes of the ROS graph while active, at most once per interval.
 */
Object {
    id: root

    //! Whether to emit, e.g. while the tab is visible.
    property bool active: true

    //! Milliseconds a graph change waits, combining bursts of changes, e.g. from a launch, into one trigger.
    property alias interval: throttle.interval

    signal triggered

    // Deferred, as a StackLayout settles the visibility of its pages after creation.
    Component.onCompleted: Qt.callLater(() => {
        if (root.active)
            root.triggered();
    })
    // A tab hidden for a while is stale.
    onActiveChanged: {
        if (active)
            triggered();
    }

    Connections {
        function onGraphChanged() {
            if (!throttle.running)
                throttle.start();
        }

        enabled: root.active
        target: Ros2
    }
    Timer {
        id: throttle

        onTriggered: root.triggered()
    }
}
