import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements

Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(350, 500)

    anchors.fill: parent
    color: palette.base

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            // Switching the client would orphan the running goal.
            enabled: !d.goalHandle || !!d.result

            FuzzySelector {
                id: topicSelect
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

                Layout.fillWidth: true
                objectName: "actionTopicSelector"
                placeholderText: qsTr("Action Topic")
                text: context.topic ?? ""

                Component.onCompleted: refresh()
                onTextChanged: {
                    if (text === context.topic)
                        return;
                    context.topic = text;
                    typeSelect.refresh();
                }
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

                Layout.fillWidth: true
                objectName: "actionTypeSelector"
                placeholderText: qsTr("Action Type")
                text: context.type ?? ""

                Component.onCompleted: refresh()
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
            Layout.fillWidth: true
            objectName: "actionTabBar"

            TabButton {
                text: qsTr("Request")
            }
            TabButton {
                enabled: !!d.goalHandle || d.result
                text: qsTr("Feedback")
            }
            TabButton {
                enabled: !!d.goalHandle || d.result
                text: qsTr("Result")
            }
        }
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: tabBar.currentIndex

            // Request Tab
            MessageContentEditor {
                id: requestEditor
                Layout.fillHeight: true
                Layout.fillWidth: true
                objectName: "actionRequestEditor"
                readonly: false

                model: MessageItemModel {
                    id: requestModel
                    Component.onCompleted: {
                        if (!!context.request)
                            message = context.request;
                        else if (!!context.type)
                            message = Ros2.createEmptyActionGoal(context.type);
                    }
                    onModified: {
                        if (message == context.request)
                            return;
                        context.request = message;
                    }
                }

                onSubmitted: {
                    if (d.goalPending || d.goalRunning || !sendButton.enabled)
                        return;
                    sendButton.clicked();
                    // Key focus reason so the style highlights the button, Cancel once the goal is accepted.
                    sendButton.forceActiveFocus(Qt.ShortcutFocusReason);
                }
            }

            // Feedback Tab
            Item {
                Layout.fillHeight: true
                Layout.fillWidth: true

                Rectangle {
                    anchors.fill: parent
                    color: root.palette.base
                    visible: !feedbackLayout.visible

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
                        Layout.fillHeight: true
                        Layout.preferredWidth: 120
                        clip: true
                        model: d.feedbackMessages
                        objectName: "actionFeedbackList"

                        delegate: ItemDelegate {
                            required property int index
                            required property var message

                            highlighted: ListView.isCurrentItem
                            text: index
                            width: feedbackList.width

                            onClicked: feedbackList.currentIndex = index
                        }
                    }
                    MessageContentEditor {
                        id: feedbackEditor
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        objectName: "actionFeedbackEditor"
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
                Layout.fillHeight: true
                Layout.fillWidth: true

                Rectangle {
                    anchors.fill: parent
                    color: root.palette.base
                    visible: !resultEditor.visible

                    Label {
                        anchors.centerIn: parent
                        text: {
                            if (!d.result)
                                return "No result available yet.";
                            if (!d.result.result)
                                return d.result.message;
                            return "";
                        }
                    }
                }
                MessageContentEditor {
                    id: resultEditor
                    anchors.fill: parent
                    readonly: true
                    visible: d.client && d.goalHandle && d.result?.result || false

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
                Layout.fillWidth: true
                objectName: "actionStatusLabel"
                text: {
                    if (!d.client)
                        return "None";
                    if (d.goalRunning) {
                        if (d.canceling)
                            return "Canceling...";
                        return "Processing goal.";
                    }
                    if (d.client.ready)
                        return "Ready";
                    return "Connecting...";
                }
            }
            Button {
                id: sendButton
                // Cancel stays available when the server dies so the hold-to-drop path is reachable.
                enabled: d.goalRunning || (d.client?.ready ?? false)
                objectName: "actionSendCancelButton"
                text: {
                    if (d.goalRunning)
                        return "Cancel";
                    if (tabBar.currentIndex != 0)
                        return "Back";
                    return "Send Goal";
                }
                visible: !d.awaitingResult

                Keys.onPressed: event => keyGuard.filter(event)
                onClicked: {
                    keyGuard.arm();
                    if (d.goalHandle && d.goalHandle.isActive) {
                        d.goalHandle.cancel();
                        d.cancelRequested = true;
                        return;
                    }
                    if (tabBar.currentIndex > 0) {
                        tabBar.currentIndex = 0;
                        return;
                    }
                    d.resetState();
                    const seq = d.goalSeq;
                    tabBar.currentIndex = 1;
                    d.goalPending = true;
                    d.client.sendGoalAsync(requestEditor.model.message, {
                            "onGoalResponse": function (goalHandle) {
                                if (seq !== d.goalSeq) {
                                    // Goal was abandoned before acceptance; nothing in the UI can cancel it later.
                                    goalHandle?.cancel();
                                    return;
                                }
                                d.goalPending = false;
                                if (!goalHandle) {
                                    Ros2.warn("Goal rejected by server");
                                    d.result = {
                                        "message": "Goal rejected by server"
                                    };
                                    tabBar.currentIndex = 2;
                                    return;
                                }
                                Ros2.debug("Goal accepted by server, waiting for result");
                                d.goalHandle = goalHandle;
                            },
                            "onFeedback": function (goalHandle, feedback) {
                                if (seq !== d.goalSeq)
                                    return;
                                if (!d.goalHandle || goalHandle.goalId != d.goalHandle.goalId) {
                                    Ros2.warn("Received feedback for old goal handle. Ignoring.");
                                    return;
                                }
                                const displayingLatest = feedbackList.currentIndex == d.feedbackMessages.count - 1;
                                d.feedbackMessages.append({
                                        "message": feedback
                                    });
                                if (displayingLatest)
                                    feedbackList.currentIndex = d.feedbackMessages.count - 1;
                            },
                            "onResult": function (result) {
                                if (seq !== d.goalSeq)
                                    return;
                                tabBar.currentIndex = 2;
                                d.result = result;
                            }
                        });
                }
            }
            HoldButton {
                id: holdDropButton
                objectName: "actionHoldDropButton"
                text: qsTr("Hold to drop")
                visible: d.awaitingResult

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

        // Canceling or finished but no result yet: Cancel is useless and this hangs if the server died.
        readonly property bool awaitingResult: canceling || goalRunning && !goalHandle.isActive
        property bool cancelRequested: false
        readonly property bool canceling: goalRunning && (cancelRequested || goalHandle.status === ActionGoalStatus.Canceling)
        property var client: {
            if (!context.topic || !context.type || !Ros2.isValidTopic(context.topic))
                return null;
            return Ros2.createActionClient(context.topic, context.type);
        }
        property var feedbackMessages: ListModel {
        }
        property var goalHandle: null
        // Sent but not yet accepted or rejected.
        property bool goalPending: false
        readonly property bool goalRunning: !!goalHandle && !result
        // Bumped on reset so callbacks of abandoned goals can ignore themselves.
        property int goalSeq: 0
        property var result: null

        function resetState() {
            goalSeq++;
            goalHandle = null;
            goalPending = false;
            cancelRequested = false;
            feedbackMessages.clear();
            result = null;
        }

        // Cancel and Hold to drop replace each other, hand over the keyboard focus.
        onAwaitingResultChanged: {
            if (awaitingResult && sendButton.activeFocus)
                holdDropButton.forceActiveFocus(Qt.TabFocusReason);
            else if (!awaitingResult && holdDropButton.activeFocus)
                sendButton.forceActiveFocus(Qt.TabFocusReason);
        }
        onClientChanged: resetState()
    }
    KeyActivationGuard {
        id: keyGuard
    }
}
