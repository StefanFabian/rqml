import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements

Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(350, 500)
    color: palette.base

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8

        GridLayout {
            Layout.fillWidth: true
            columns: 2

            FuzzySelector {
                id: serviceSelect
                Layout.fillWidth: true
                placeholderText: qsTr("Service Topic")
                text: context.service ?? ""
                onTextChanged: {
                    if (text === context.service)
                        return;
                    context.service = text;
                    typeSelect.refresh();
                }
                function refresh() {
                    let services = Ros2.queryServices();
                    if (!!context.service) {
                        const index = services.indexOf(context.service);
                        if (index != -1)
                            services.splice(index, 1);
                        services.unshift(context.service);
                    }
                    model = services;
                }
                Component.onCompleted: refresh()
            }
            RefreshButton {
                id: refreshServicesButton
                onClicked: {
                    animate = true;
                    serviceSelect.refresh();
                    animate = false;
                }
            }
            FuzzySelector {
                id: typeSelect
                Layout.fillWidth: true
                placeholderText: qsTr("Service Type")
                text: context.type ?? ""
                onTextChanged: {
                    if (text === context.type)
                        return;
                    context.type = text;
                    if (!context.type)
                        return;
                    if (requestModel.message && requestModel.message["#messageType"] === context.type + "_Request")
                        return;
                    tabBar.currentIndex = 0;
                }
                function refresh() {
                    let types = Ros2.getServiceTypes(context.service);
                    if (types.length == 0)
                        types = context.type ? [context.type] : [];
                    typeSelect.model = types;
                    if (context.type && types.includes(context.type)) {
                        typeSelect.text = context.type
                    } else {
                        typeSelect.text = types.length > 0 ? types[0] : "";
                    }
                }
                Component.onCompleted: refresh()
            }
            RefreshButton {
                onClicked: {
                    animate = true;
                    typeSelect.refresh();
                    animate = false;
                }
            }
        }
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            TabButton {
                text: qsTr("Request")
            }
            TabButton {
                text: qsTr("Response")
                enabled: d.response !== null || d.isActive
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // Request Tab
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                MessageContentEditor {
                    id: requestEditor
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: MessageItemModel {
                        id: requestModel
                        onModified: {
                            if (message == context.request)
                                return;
                            context.request = message;
                        }
                        Component.onCompleted: message = context.request ?? null
                    }
                    readonly: false
                }
                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        enabled: !!context.type
                        implicitWidth: 120
                        text: qsTr("Reset")
                        onClicked: {
                            context.request = Ros2.createEmptyServiceRequest(context.type);
                            requestModel.message = context.request;
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    } // Spacer

                    Button {
                        enabled: (d.client?.ready && !d.isActive) ?? false
                        implicitWidth: 120
                        text: qsTr("Send")
                        onClicked: {
                            d.resetState();
                            d.isActive = true;
                            tabBar.currentIndex = 1;
                            d.client.sendRequestAsync(requestEditor.model.message, function (response) {
                                tabBar.currentIndex = 1;
                                d.response = response;
                                d.isActive = false;
                            });
                        }
                    }
                }
            }

            // Response Tab
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle {
                        visible: !responseEditor.visible
                        anchors.fill: parent
                        color: root.palette.base
                        Label {
                            anchors.centerIn: parent
                            text: d.response === null ? "Waiting for response..." : "Service call failed."
                        }
                    }
                    MessageContentEditor {
                        id: responseEditor
                        anchors.fill: parent
                        visible: !!d.client && !!d.response
                        readonly: true
                        model: MessageItemModel {
                            message: d.response || null
                            onMessageChanged: responseEditor.expandRecursively()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    } // Spacer

                    Button {
                        implicitWidth: 120
                        text: qsTr("Back")
                        onClicked: tabBar.currentIndex = 0
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Status: "
            }
            Label {
                id: statusText
                Layout.fillWidth: true
                text: {
                    if (!d.client)
                        return "Not connected";
                    if (d.isActive)
                        return "Waiting for response...";
                    if (d.client.ready)
                        return "Ready";
                    return "Connecting...";
                }
            }
        }
    }

    QtObject {
        id: d
        // Incremented by the timer to re-evaluate the client binding without changing service/type.
        property int _tick: 0
        property var client: {
            _tick;
            if (!context.service || !context.type || !Ros2.isValidTopic(context.service))
                return null;
            const types = Ros2.getServiceTypes(context.service);
            if (types.length > 0 && !types.includes(context.type))
                return null;
            return Ros2.createServiceClient(context.service, context.type);
        }
        onClientChanged: {
            resetState();
            if (client && (!requestModel.message || requestModel.message["#messageType"] !== context.type + "_Request")) {
                context.request = Ros2.createEmptyServiceRequest(context.type);
                requestModel.message = context.request;
            }
        }
        property bool isActive: false
        property var response: null

        function resetState() {
            isActive = false;
            response = null;
        }
    }

    // Poll until the service advertises the expected type, allowing late-starting services.
    Timer {
        interval: 500
        repeat: true
        running: !!context.service && !!context.type && !d.client
        onTriggered: d._tick++
    }
}
