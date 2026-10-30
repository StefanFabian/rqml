import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import RQml.Utils

Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(350, 500)

    function addMessageEntry(topic, type, rate) {
        const entry = {
            "topic": topic,
            "type": type,
            "content": MessageUtils.toJavaScriptObject(Ros2.createEmptyMessage(type)),
            "enabled": false,
            "rate": rate
        };
        let values = Array.from(context.messages);
        values.push(entry);
        context.messages = values;
        messagesListModel.append(entry);
    }
    function removeEntry(index) {
        let values = Array.from(context.messages);
        values.splice(index, 1);
        context.messages = values;
        messagesListModel.remove(index);
    }
    function updateEntry(index, update) {
        // Not entirely sure why this is necessary here but for some reason
        // directly modifying context.messages[index] does not even update
        // the value in the context object.
        let values = Array.from(context.messages);
        for (let key in update) {
            values[index][key] = update[key];
        }
        context.messages = values;
    }

    anchors.fill: parent
    color: palette.base

    Component.onCompleted: {
        if (context.messages === undefined)
            context.messages = [];
        for (let i = 0; i < context.messages.length; i++) {
            const msg = context.messages[i];
            messagesListModel.append(msg);
        }
    }

    ListModel {
        id: messagesListModel

        dynamicRoles: true
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8

        GridLayout {
            Layout.fillWidth: true
            columns: 2

            FuzzySelector {
                id: topicSelect

                function refresh() {
                    model = Ros2.queryTopics();
                    if (!text)
                        text = model.length > 0 ? model[0] : "";
                }

                Layout.fillWidth: true
                objectName: "publisherTopicSelector"
                placeholderText: qsTr("Topic")

                Component.onCompleted: refresh()
                onTextChanged: typeSelect.refresh()
            }
            RefreshButton {
                onClicked: {
                    animate = true;
                    topicSelect.refresh();
                    animate = false;
                }
            }
            FuzzySelector {
                id: typeSelect

                function refresh() {
                    model = Ros2.getTopicTypes(topicSelect.text);
                    if (model.length > 0)
                        text = model[0];
                }

                Layout.fillWidth: true
                objectName: "publisherTypeSelector"
                placeholderText: qsTr("Message Type")

                Component.onCompleted: refresh()
            }
            RefreshButton {
                onClicked: {
                    animate = true;
                    typeSelect.refresh();
                    animate = false;
                }
            }
            Button {
                enabled: Ros2.isValidTopic(topicSelect.text)
                objectName: "addMessageButton"
                text: "Add Message"

                onClicked: root.addMessageEntry(topicSelect.text, typeSelect.text, 1)
            }
        }
        ListView {
            id: messagesListView

            Layout.fillHeight: true
            Layout.fillWidth: true
            model: messagesListModel
            objectName: "messagesListView"

            delegate: Rectangle {
                color: index % 2 == 1 ? root.palette.alternateBase : root.palette.base
                height: 48
                width: messagesListView.width

                RowLayout {
                    anchors.fill: parent

                    Timer {
                        property var publisher: Ros2.createPublisher(model.topic, model.type)

                        interval: model.rate > 0 ? 1000 / model.rate : 0
                        repeat: true
                        running: model.enabled && model.rate > 0

                        onTriggered: {
                            publisher.publish(model.content);
                        }
                    }
                    CheckBox {
                        id: enabledCheckBox

                        Layout.rowSpan: 2
                        checked: model.enabled
                        objectName: "enabledCheckBox_" + model.index

                        onCheckedChanged: {
                            if (checked == model.enabled)
                                return;
                            root.updateEntry(model.index, {
                                "enabled": checked
                            });
                            model.enabled = checked;
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true

                        RowLayout {
                            Layout.fillWidth: true

                            TruncatedLabel {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 80
                                elide: Text.ElideMiddle
                                text: model.topic
                            }
                            Label {
                                font.italic: true
                                font.pointSize: 9
                                text: model.type.replace("/msg/", "/")
                            }
                        }
                        TruncatedLabel {
                            Layout.columnSpan: 4
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: JSON.stringify(MessageUtils.stripEmptyFields(model.content) ?? {})
                        }
                    }
                    DecimalSpinBox {
                        id: rateSpinBox

                        editable: true
                        implicitWidth: 128
                        objectName: "rateSpinBox_" + model.index
                        to: 999
                        value: model.rate

                        onValueChanged: {
                            if (value == model.rate)
                                return;
                            root.updateEntry(model.index, {
                                "rate": value
                            });
                            model.rate = value;
                        }
                    }
                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
                        ToolTip.text: qsTr("Edit message content")
                        ToolTip.visible: hovered || pressed
                        font.family: IconFont.name
                        font.pixelSize: 20
                        implicitHeight: 48
                        implicitWidth: 48
                        text: IconFont.iconEdit

                        onClicked: editDialog.open()
                    }
                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
                        ToolTip.text: qsTr("Delete message entry")
                        ToolTip.visible: hovered || pressed
                        font.family: IconFont.name
                        font.pixelSize: 20
                        implicitHeight: 48
                        implicitWidth: 48
                        objectName: "deleteButton_" + model.index
                        text: IconFont.iconTrash

                        onClicked: removeEntry(model.index)
                    }
                    EditMessageDialog {
                        id: editDialog

                        anchors.centerIn: Overlay.overlay
                        height: Math.max(400, (Overlay.overlay?.height ?? 0) * 0.8)
                        modal: true
                        width: 600

                        onAboutToShow: {
                            message = model.content;
                        }
                        onAccepted: {
                            let type = message["#messageType"] || model.type;
                            root.updateEntry(model.index, {
                                "content": message,
                                "type": type
                            });
                            model.content = message;
                            model.type = type;
                        }
                    }
                }
            }
        }
    }
}
