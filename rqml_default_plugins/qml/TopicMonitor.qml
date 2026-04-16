import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts

Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(720, 360)
    property string latestDialogTopic: ""

    function addTopicEntry(topic) {
        const normalizedTopic = String(topic ?? "").trim();
        if (!Ros2.isValidTopic(normalizedTopic) || d.hasEntry(normalizedTopic))
            return;
        const type = d.resolveType(normalizedTopic);
        if (!type)
            return;
        const entry = {
            "topic": normalizedTopic,
            "type": type,
            "paused": false
        };
        const values = Array.from(context.monitoredTopics ?? []);
        values.push(entry);
        context.monitoredTopics = values;
        monitorListModel.append(entry);
    }
    function openLatestMessageDialog(topic, type, message) {
        latestDialogTopic = topic;
        latestMessageDialog.messageType = type;
        latestMessageDialog.message = message ? message : Ros2.createEmptyMessage(type);
        latestMessageDialog.open();
    }
    function removeEntry(index) {
        const values = Array.from(context.monitoredTopics ?? []);
        values.splice(index, 1);
        context.monitoredTopics = values;
        monitorListModel.remove(index);
    }
    function updateEntry(index, update) {
        const values = Array.from(context.monitoredTopics ?? []);
        for (let key in update)
            values[index][key] = update[key];
        context.monitoredTopics = values;
    }

    anchors.fill: parent
    color: palette.base

    Component.onCompleted: {
        if (context.monitoredTopics === undefined)
            context.monitoredTopics = [];
        for (let i = 0; i < context.monitoredTopics.length; ++i) {
            const entry = context.monitoredTopics[i];
            monitorListModel.append({
                    "topic": entry.topic,
                    "type": entry.type || d.resolveType(entry.topic),
                    "paused": entry.paused ?? false
                });
        }
    }

    ListModel {
        id: monitorListModel
        dynamicRoles: true
    }
    EditMessageDialog {
        id: latestMessageDialog
        anchors.centerIn: Overlay.overlay
        height: Math.min(600, (Overlay.overlay?.height ?? root.height) * 0.8)
        modal: true
        objectName: "topicMonitorMessageDialog"
        readonly: true
        title: latestDialogTopic ? qsTr("Latest Message: %1").arg(latestDialogTopic) : qsTr("Latest Message")
        width: Math.min(800, (Overlay.overlay?.width ?? root.width) * 0.8)
    }
    QtObject {
        id: d
        function formatBandwidth(bytesPerSecond) {
            const value = Number(bytesPerSecond ?? 0);
            if (!isFinite(value) || value <= 0)
                return "-";
            if (value < 1024)
                return value.toFixed(0) + " B/s";
            if (value < 1024 * 1024)
                return (value / 1024).toFixed(value < 10 * 1024 ? 1 : 0) + " KiB/s";
            return (value / (1024 * 1024)).toFixed(1) + " MiB/s";
        }
        function formatFrequency(hz) {
            const value = Number(hz ?? 0);
            if (!isFinite(value) || value <= 0)
                return "-";
            if (value < 1)
                return value.toFixed(2) + " Hz";
            if (value < 10)
                return value.toFixed(1) + " Hz";
            return value.toFixed(0) + " Hz";
        }
        function hasEntry(topic) {
            for (let i = 0; i < monitorListModel.count; ++i) {
                if (monitorListModel.get(i).topic === topic)
                    return true;
            }
            return false;
        }
        function resolveType(topic) {
            const topicTypes = Ros2.getTopicTypes(topic);
            return topicTypes.length > 0 ? topicTypes[0] : "";
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            FuzzySelector {
                id: topicSelector
                function refresh() {
                    const topics = Ros2.queryTopics().slice().sort();
                    if (text) {
                        const existingIndex = topics.indexOf(text);
                        if (existingIndex !== -1)
                            topics.splice(existingIndex, 1);
                        topics.unshift(text);
                    }
                    model = topics;
                }

                Layout.fillWidth: true
                objectName: "topicMonitorTopicSelector"
                placeholderText: qsTr("Select a topic to monitor")

                Component.onCompleted: refresh()
                onAccepted: function (acceptedText) {
                    root.addTopicEntry(acceptedText);
                }
            }
            RefreshButton {
                objectName: "topicMonitorRefreshButton"

                onClicked: {
                    animate = true;
                    topicSelector.refresh();
                    animate = false;
                }
            }
            IconTextButton {
                enabled: Ros2.isValidTopic(topicSelector.text) && !!d.resolveType(topicSelector.text) && !d.hasEntry(topicSelector.text)
                iconText: IconFont.iconAdd
                objectName: "topicMonitorAddButton"
                text: qsTr("Add Topic")

                onClicked: root.addTopicEntry(topicSelector.text)
            }
        }
        Rectangle {
            Layout.fillWidth: true
            color: palette.alternateBase
            implicitHeight: headerLayout.implicitHeight + 12
            radius: 6

            RowLayout {
                id: headerLayout
                anchors.fill: parent
                anchors.margins: 6
                spacing: 8

                Item {
                    Layout.preferredWidth: 40
                }
                Label {
                    Layout.fillWidth: true
                    font.bold: true
                    text: qsTr("Topic")
                }
                Label {
                    Layout.preferredWidth: 120
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("Frequency")
                }
                Label {
                    Layout.preferredWidth: 140
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("Bandwidth")
                }
                Item {
                    Layout.preferredWidth: 144
                }
            }
        }
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: monitorListModel.count === 0 ? 0 : 1

            Hint {
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Add a topic to begin monitoring.")
                verticalAlignment: Text.AlignVCenter
            }
            ListView {
                id: monitorListView
                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                model: monitorListModel
                objectName: "topicMonitorListView"
                spacing: 8

                ScrollBar.vertical: ScrollBar {
                }
                delegate: Rectangle {
                    id: delegateRoot

                    property real displayedBandwidth: 0
                    property real displayedFrequency: 0
                    required property int index
                    required property var model

                    color: index % 2 === 0 ? root.palette.base : root.palette.alternateBase
                    implicitHeight: contentColumn.implicitHeight + 12
                    radius: 6
                    width: monitorListView.width

                    Component.onCompleted: {
                        displayedFrequency = topicSubscription.frequency;
                        displayedBandwidth = topicSubscription.bandwidth;
                    }

                    ColumnLayout {
                        id: contentColumn
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                    font.bold: true
                                    objectName: "topicMonitorTopicLabel_" + model.index
                                    text: model.topic
                                }
                                Caption {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    objectName: "topicMonitorTypeLabel_" + model.index
                                    text: model.type
                                }
                            }
                            Label {
                                Layout.preferredWidth: 120
                                horizontalAlignment: Text.AlignRight
                                objectName: "topicMonitorFrequencyLabel_" + model.index
                                text: d.formatFrequency(delegateRoot.displayedFrequency)
                            }
                            Label {
                                Layout.preferredWidth: 140
                                horizontalAlignment: Text.AlignRight
                                objectName: "topicMonitorBandwidthLabel_" + model.index
                                text: d.formatBandwidth(delegateRoot.displayedBandwidth)
                            }
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                objectName: "topicMonitorViewButton_" + model.index
                                text: IconFont.iconMessage
                                tooltipText: qsTr("View latest message")

                                onClicked: root.openLatestMessageDialog(model.topic, model.type, topicSubscription.message)
                            }
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                objectName: "topicMonitorPauseButton_" + model.index
                                text: model.paused ? IconFont.iconPlay : IconFont.iconPause
                                tooltipText: model.paused ? qsTr("Resume topic") : qsTr("Pause topic")

                                onClicked: {
                                    const paused = !model.paused;
                                    root.updateEntry(model.index, {
                                            "paused": paused
                                        });
                                    model.paused = paused;
                                }
                            }
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                objectName: "topicMonitorDeleteButton_" + model.index
                                text: IconFont.iconTrash
                                tooltipText: qsTr("Remove topic")

                                onClicked: root.removeEntry(model.index)
                            }
                        }
                    }
                    Subscription {
                        id: topicSubscription
                        enabled: !model.paused
                        messageType: model.type
                        objectName: "topicMonitorSubscription_" + model.index
                        throttleRate: 1
                        topic: model.topic
                    }
                    Timer {
                        interval: 500
                        repeat: true
                        running: !model.paused

                        onTriggered: {
                            delegateRoot.displayedFrequency = topicSubscription.frequency;
                            delegateRoot.displayedBandwidth = topicSubscription.bandwidth;
                        }
                    }
                }
            }
        }
    }
}
