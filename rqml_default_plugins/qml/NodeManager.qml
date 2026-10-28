import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import "elements"

Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(500, 450)

    anchors.fill: parent
    color: palette.base

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            objectName: "nmTabBar"

            Component.onCompleted: currentIndex = context.currentTab ?? 0
            onCurrentIndexChanged: context.currentTab = currentIndex

            TabButton {
                text: qsTr("Nodes")
            }
            TabButton {
                text: qsTr("Lifecycle")
            }
            TabButton {
                text: qsTr("Containers")
            }
            TabButton {
                text: qsTr("Graph")
            }
        }
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: tabBar.currentIndex

            NodesTab {
                id: nodesTab
            }
            LifecycleTab {
                toasts: toastManager
            }
            ContainersTab {
                toasts: toastManager
            }
            NodeGraphTab {
                onInspectNodeRequested: fullName => {
                    tabBar.currentIndex = 0;
                    nodesTab.showNode(fullName);
                }
            }
        }
    }
    ToastManager {
        id: toastManager
        z: 100
    }
}
