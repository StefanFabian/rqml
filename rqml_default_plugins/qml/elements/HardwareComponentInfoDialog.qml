import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements

Dialog {
    id: root

    property var component: null

    function openHardwareComponentInfo(component) {
        root.component = component;
        root.open();
    }

    anchors.centerIn: parent
    height: Math.min(parent.height * 0.8, implicitHeight)
    standardButtons: Dialog.Close
    title: qsTr("Hardware Component Information")
    width: 600

    QtObject {
        id: d

        property var attributes: {
            if (!root.component)
                return [];
            return [
                {
                    "name": "Name",
                    "data": root.component.name
                },
                {
                    "name": "State",
                    "data": root.component.state.label
                },
                {
                    "name": "Type",
                    "data": root.component.type
                },
                {
                    "name": "Is Async",
                    "data": root.component.is_async
                },
                {
                    "name": "R/W Rate",
                    "data": root.component.rw_rate
                },
                {
                    "name": "Class Type",
                    "data": root.component.class_type
                },
                {
                    "name": "Plugin Name",
                    "data": root.component.plugin_name
                }
            ];
        }
    }
    ScrollView {
        id: scrollView

        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        anchors.fill: parent

        GridLayout {
            id: mainLayout

            columns: 2
            rowSpacing: 8
            width: scrollView.availableWidth

            Repeater {
                model: d.attributes

                Label {
                    Layout.column: 0
                    Layout.rightMargin: 8
                    Layout.row: index + 2
                    font.bold: true
                    text: modelData.name + ":"
                }
            }
            Repeater {
                model: d.attributes

                TruncatedLabel {
                    Layout.column: 1
                    Layout.fillWidth: true
                    Layout.row: index + 2
                    elide: Text.ElideMiddle
                    text: modelData.data ?? qsTr("N/A")
                }
            }
            ListView {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight + headerItem.implicitHeight
                clip: true
                delegate: interfaceDelegate
                headerPositioning: ListView.OverlayHeader
                model: root.component?.command_interfaces ?? []

                header: ListHeader {
                    text: "Command Interfaces"
                }
            }
            ListView {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight + headerItem.implicitHeight
                clip: true
                delegate: interfaceDelegate
                headerPositioning: ListView.OverlayHeader
                model: root.component?.state_interfaces ?? []

                header: ListHeader {
                    text: "State Interfaces"
                }
            }
            Component {
                id: interfaceDelegate

                Rectangle {
                    color: index % 2 === 0 ? "transparent" : root.palette.alternateBase
                    height: 32
                    width: mainLayout.width

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8

                        TruncatedLabel {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: model.name
                        }
                        TruncatedLabel {
                            Layout.preferredWidth: 80
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                            text: model.data_type
                        }
                        Label {
                            Layout.preferredWidth: 80
                            color: model.is_available ? root.palette.highlight : root.palette.text
                            font.bold: model.is_available
                            horizontalAlignment: Text.AlignHCenter
                            text: model.is_available ? qsTr("Available") : qsTr("Not Available")
                        }
                        Label {
                            Layout.preferredWidth: 80
                            color: model.is_claimed ? root.palette.highlight : root.palette.text
                            font.bold: model.is_claimed
                            horizontalAlignment: Text.AlignHCenter
                            text: model.is_claimed ? qsTr("Claimed") : qsTr("Unclaimed")
                        }
                    }
                }
            }
        }
    }
}
