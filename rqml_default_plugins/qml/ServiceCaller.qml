import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Utils

Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(350, 350)

    anchors.fill: parent
    color: palette.base

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8

        GridLayout {
            Layout.fillWidth: true
            columns: 2

            FuzzySelector {
                id: serviceSelect
                function refresh() {
                    let services = InterfaceFilter.filterServices(Ros2.queryServices(), context.showDefaultServices ?? false);
                    if (!!context.service) {
                        const index = services.indexOf(context.service);
                        if (index != -1)
                            services.splice(index, 1);
                        services.unshift(context.service);
                    }
                    model = services;
                }

                Layout.fillWidth: true
                objectName: "serviceTopicSelector"
                placeholderText: qsTr("Service Topic")
                text: context.service ?? ""

                Component.onCompleted: refresh()
                onTextChanged: {
                    if (text === context.service)
                        return;
                    context.service = text;
                    typeSelect.refresh();
                }
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
                function refresh() {
                    let types = !!context.service ? Ros2.getServiceTypes(context.service) : [];
                    if (types.length == 0)
                        types = context.type ? [context.type] : [];
                    typeSelect.model = types;
                    if (context.type && types.includes(context.type)) {
                        typeSelect.text = context.type;
                    } else {
                        typeSelect.text = types.length > 0 ? types[0] : "";
                    }
                }

                Layout.fillWidth: true
                objectName: "serviceTypeSelector"
                placeholderText: qsTr("Service Type")
                text: context.type ?? ""

                Component.onCompleted: refresh()
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
            objectName: "serviceTabBar"

            TabButton {
                text: qsTr("Request")
            }
            TabButton {
                enabled: d.response !== null || d.isActive
                text: qsTr("Response")
            }
        }
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: tabBar.currentIndex

            // Request Tab
            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true

                MessageContentEditor {
                    id: requestEditor
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    objectName: "serviceRequestEditor"
                    readonly: false

                    model: MessageItemModel {
                        id: requestModel
                        Component.onCompleted: message = context.request ?? null
                        onModified: {
                            if (message == context.request)
                                return;
                            context.request = message;
                        }
                    }

                    onSubmitted: {
                        if (d.isActive || !sendButton.enabled)
                            return;
                        sendButton.clicked();
                        holdToDropButton.forceActiveFocus(Qt.ShortcutFocusReason);
                    }
                }
                Button {
                    enabled: !!context.type
                    implicitWidth: 120
                    objectName: "serviceResetButton"
                    text: qsTr("Reset")

                    onClicked: {
                        context.request = Ros2.createEmptyServiceRequest(context.type);
                        requestModel.message = context.request;
                    }
                }
            }

            // Response Tab
            Item {
                Layout.fillHeight: true
                Layout.fillWidth: true

                Rectangle {
                    anchors.fill: parent
                    color: root.palette.base
                    visible: !responseEditor.visible

                    Label {
                        anchors.centerIn: parent
                        text: d.response === null ? "Waiting for response..." : "Service call failed."
                    }
                }
                MessageContentEditor {
                    id: responseEditor
                    anchors.fill: parent
                    readonly: true
                    visible: !!d.client && !!d.response

                    model: MessageItemModel {
                        message: d.response || null

                        onMessageChanged: responseEditor.expandRecursively()
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
                objectName: "serviceStatusLabel"
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
            CheckBox {
                id: showDefaultServicesCheck
                checked: context.showDefaultServices ?? false
                objectName: "showDefaultServicesCheckbox"
                text: qsTr("Show default services")

                onCheckedChanged: {
                    if (context.showDefaultServices !== checked) {
                        context.showDefaultServices = checked;
                        serviceSelect.refresh();
                    }
                }
            }
            Button {
                id: sendButton
                enabled: tabBar.currentIndex != 0 || (d.client?.ready ?? false)
                implicitWidth: 120
                objectName: "serviceSendButton"
                text: tabBar.currentIndex != 0 ? qsTr("Back") : qsTr("Send")
                visible: !d.isActive

                Keys.onPressed: event => keyGuard.filter(event)
                onClicked: {
                    keyGuard.arm();
                    if (tabBar.currentIndex != 0) {
                        tabBar.currentIndex = 0;
                        return;
                    }
                    d.resetState();
                    const seq = d.requestSeq;
                    d.isActive = true;
                    tabBar.currentIndex = 1;
                    d.client.sendRequestAsync(requestEditor.model.message, function (response) {
                            if (seq !== d.requestSeq)
                                return;
                            tabBar.currentIndex = 1;
                            d.response = response;
                            d.isActive = false;
                        });
                }
            }
            HoldButton {
                id: holdToDropButton
                objectName: "serviceHoldDropButton"
                text: qsTr("Hold to drop")
                visible: d.isActive

                onActivated: {
                    // Send takes the focus while a held key may still auto-repeat.
                    keyGuard.arm();
                    d.resetState();
                    tabBar.currentIndex = 0;
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
        property bool isActive: false
        // Bumped on reset so responses to abandoned requests can ignore themselves.
        property int requestSeq: 0
        property var response: null

        function resetState() {
            requestSeq++;
            isActive = false;
            response = null;
        }

        onClientChanged: {
            resetState();
            if (client && (!requestModel.message || requestModel.message["#messageType"] !== context.type + "_Request")) {
                context.request = Ros2.createEmptyServiceRequest(context.type);
                requestModel.message = context.request;
            }
        }

        // Send/Back and Hold to drop replace each other, hand over the keyboard focus.
        onIsActiveChanged: {
            if (isActive && sendButton.activeFocus)
                holdToDropButton.forceActiveFocus(Qt.TabFocusReason);
            else if (!isActive && holdToDropButton.activeFocus)
                sendButton.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    // Poll until the service advertises the expected type, allowing late-starting services.
    Timer {
        interval: 500
        repeat: true
        running: !!context.service && !!context.type && !d.client

        onTriggered: d._tick++
    }
    KeyActivationGuard {
        id: keyGuard
    }
}
