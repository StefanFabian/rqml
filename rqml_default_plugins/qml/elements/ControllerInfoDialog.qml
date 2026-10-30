import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements

Dialog {
    id: root

    property var controller: null

    function openControllerInfo(controller) {
        root.controller = controller;
        root.open();
    }

    anchors.centerIn: parent
    height: Math.min(parent.height * 0.8, implicitHeight)
    standardButtons: Dialog.Close
    title: qsTr("Controller Information")
    width: 600

    QtObject {
        id: d

        property var attributes: {
            if (!root.controller || root.controller.state == "unloaded")
                return [];
            return [
                {
                    "name": "Type",
                    "data": root.controller.type
                },
                {
                    "name": "Is Async",
                    "data": root.controller.is_async
                },
                {
                    "name": "Update Rate",
                    "data": root.controller.update_rate
                },
                {
                    "name": "Is Chainable",
                    "data": root.controller.is_chainable
                },
                {
                    "name": "Is Chained",
                    "data": root.controller.is_chained
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
            width: scrollView.availableWidth

            Label {
                font.bold: true
                text: qsTr("Name:")
            }
            Label {
                Layout.fillWidth: true
                text: root.controller?.name ?? qsTr("N/A")
            }
            Label {
                font.bold: true
                text: qsTr("State:")
            }
            Label {
                text: root.controller?.state ?? qsTr("N/A")
            }
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
            Repeater {
                model: {
                    if (!root.controller || root.controller.state == "unloaded")
                        return [];
                    return [
                        {
                            "name": "Claimed Interfaces",
                            "data": root.controller.claimed_interfaces
                        },
                        {
                            "name": "Required Command Interfaces",
                            "data": root.controller.required_command_interfaces
                        },
                        {
                            "name": "Required State Interfaces",
                            "data": root.controller.required_state_interfaces
                        },
                        {
                            "name": "Exported State Interfaces",
                            "data": root.controller.exported_state_interfaces
                        },
                        {
                            "name": "Reference Interfaces",
                            "data": root.controller.reference_interfaces
                        }
                    ];
                }

                ListView {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight + headerItem.implicitHeight
                    clip: true
                    headerPositioning: ListView.OverlayHeader
                    model: modelData.data
                    spacing: 8

                    delegate: TruncatedLabel {
                        elide: Text.ElideMiddle
                        height: 24
                        text: model.display
                        width: mainLayout.width
                    }
                    header: ListHeader {
                        text: modelData.name
                    }
                }
            }
            ListView {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight + headerItem.implicitHeight
                clip: true
                headerPositioning: ListView.OverlayHeader
                model: root.controller?.chain_connections ?? []
                visible: root.controller?.state != "unloaded"

                delegate: Rectangle {
                    color: index % 2 === 0 ? "transparent" : palette.alternateBase
                    height: layout.implicitHeight
                    width: mainLayout.width

                    RowLayout {
                        id: layout

                        property var reference_interfaces: model.reference_interfaces

                        anchors.fill: parent

                        TruncatedLabel {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: model.name
                        }
                        Column {
                            Layout.fillWidth: true

                            Repeater {
                                model: reference_interfaces

                                TruncatedLabel {
                                    elide: Text.ElideMiddle
                                    height: 24
                                    text: model.display
                                    width: parent.width
                                }
                            }
                        }
                    }
                }
                header: ListHeader {
                    text: "Chain Connections"
                }
            }
        }
    }
}
