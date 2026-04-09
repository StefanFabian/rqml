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
                id: topicSelect
                objectName: "actionTopicSelector"
                Layout.fillWidth: true
                placeholderText: qsTr("Action Topic")
                text: context.topic ?? ""
                onTextChanged: {
                    if (text === context.topic)
                        return;
                    context.topic = text;
                    typeSelect.refresh();
                }
                function refresh() {
                    let result = Ros2.queryActions();
                    if (!!context.topic) {
                        const index = result.indexOf(context.topic);
                        if (index != -1)
                            result.splice(index, 1);
                        result.unshift(context.topic);
                    }
                    model = result;
                }
                Component.onCompleted: refresh()
            }
            RefreshButton {
                objectName: "actionTopicRefreshButton"
                onClicked: {
                    animate = true;
                    topicSelect.refresh();
                    animate = false;
                }
            }

            FuzzySelector {
                id: typeSelect
                objectName: "actionTypeSelector"
                Layout.fillWidth: true
                placeholderText: qsTr("Action Type")
                text: context.type ?? ""
                onTextChanged: {
                    if (text === context.type)
                        return;
                    context.type = text;
                    if (!context.type)
                        return;
                    if (requestModel.message && requestModel.message["#messageType"] == context.type + "_Goal")
                        return;
                    requestModel.message = Ros2.createEmptyActionGoal(context.type);
                }
                function refresh() {
                    let types = !!context.topic ? Ros2.getActionTypes(context.topic) : [];
                    if (types.length == 0)
                        types = context.type ? [context.type] : [];
                    typeSelect.model = types;
                    if (context.type && types.includes(context.type)) {
                        typeSelect.text = context.type;
                    } else {
                        typeSelect.text = types.length > 0 ? types[0] : "";
                    }
                }
                Component.onCompleted: refresh()
            }
            RefreshButton {
                objectName: "actionTypeRefreshButton"
                onClicked: {
                    animate = true;
                    typeSelect.refresh();
                    animate = false;
                }
            }
        }
        TabBar {
            id: tabBar
            objectName: "actionTabBar"
            Layout.fillWidth: true
            TabButton {
                text: qsTr("Request")
            }
            TabButton {
                text: qsTr("Feedback")
                enabled: !!d.goalHandle
            }
            TabButton {
                text: qsTr("Result")
                enabled: !!d.goalHandle
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // Request Tab
            MessageContentEditor {
                id: requestEditor
                objectName: "actionRequestEditor"
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: MessageItemModel {
                    id: requestModel
                    onModified: {
                        if (message == context.request)
                            return;
                        context.request = message;
                    }
                    Component.onCompleted: {
                        if (!!context.request)
                            message = context.request;
                        else if (!!context.type)
                            message = Ros2.createEmptyActionGoal(context.type);
                    }
                }
                readonly: false
            }

            // Feedback Tab
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Rectangle {
                    visible: !feedbackLayout.visible
                    anchors.fill: parent
                    color: root.palette.base
                    Label {
                        anchors.centerIn: parent
                        text: "No feedback available."
                    }
                }
                RowLayout {
                    id: feedbackLayout
                    anchors.fill: parent
                    visible: d.feedbackMessages && d.feedbackMessages.count > 0 || false

                    ListView {
                        id: feedbackList
                        objectName: "actionFeedbackList"
                        Layout.fillHeight: true
                        Layout.preferredWidth: 120
                        clip: true
                        model: d.feedbackMessages

                        delegate: ItemDelegate {
                            width: feedbackList.width
                            highlighted: ListView.isCurrentItem
                            required property int index
                            required property var message
                            onClicked: feedbackList.currentIndex = index

                            text: index
                        }
                    }
                    MessageContentEditor {
                        id: feedbackEditor
                        objectName: "actionFeedbackEditor"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly: true
                        model: MessageItemModel {
                            message: feedbackList.currentItem && feedbackList.currentItem.message || null
                            onMessageChanged: feedbackEditor.expandRecursively()
                        }
                    }
                }
            }

            // Result Tab
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Rectangle {
                    visible: !resultEditor.visible
                    anchors.fill: parent
                    color: root.palette.base
                    Label {
                        anchors.centerIn: parent
                        text: "No result available yet."
                    }
                }
                MessageContentEditor {
                    id: resultEditor
                    anchors.fill: parent
                    visible: d.client && d.goalHandle && d.result
                    readonly: true
                    model: MessageItemModel {
                        message: d.result && d.result.result || null
                        onMessageChanged: resultEditor.expandRecursively()
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
                objectName: "actionStatusLabel"
                Layout.fillWidth: true
                text: {
                    if (!d.client)
                        return "None";
                    if (d.goalHandle && !d.result)
                        return "Processing goal.";
                    if (d.client.ready)
                        return "Ready";
                    return "Connecting...";
                }
            }
            Button {
                objectName: "actionSendCancelButton"
                enabled: (d.client?.ready && d.goalHandle?.status != ActionGoalStatus.Canceling) ?? false
                text: d.goalHandle && !d.result ? "Cancel" : "Send Goal"
                onClicked: {
                    if (d.goalHandle && d.goalHandle.isActive) {
                        d.goalHandle.cancel();
                        return;
                    }
                    d.resetState();
                    tabBar.currentIndex = 1;
                    d.client.sendGoalAsync(requestEditor.model.message, {
                        onGoalResponse: function (goalHandle) {
                            if (!goalHandle) {
                                Ros2.warn("Goal rejected by server");
                                return;
                            }
                            Ros2.debug("Goal accepted by server, waiting for result");
                            d.goalHandle = goalHandle;
                        },
                        onFeedback: function (goalHandle, feedback) {
                            if (!d.goalHandle || goalHandle.goalId != d.goalHandle.goalId) {
                                Ros2.warn("Received feedback for old goal handle. Ignoring.");
                                return;
                            }
                            const displayingLatest = feedbackList.currentIndex == d.feedbackMessages.count - 1;
                            d.feedbackMessages.append({
                                message: feedback
                            });
                            if (displayingLatest)
                                feedbackList.currentIndex = d.feedbackMessages.count - 1;
                        },
                        onResult: function (result) {
                            tabBar.currentIndex = 2;
                            d.result = result;
                        }
                    });
                }
            }
        }
    }

    QtObject {
        id: d
        property var client: {
            d.resetState();
            if (!context.topic || !context.type || !Ros2.isValidTopic(context.topic))
                return null;
            return Ros2.createActionClient(context.topic, context.type);
        }
        property var goalHandle: null
        property var feedbackMessages: ListModel {}
        property var result: null

        function resetState() {
            goalHandle = null;
            feedbackMessages.clear();
            result = null;
        }
    }
}
