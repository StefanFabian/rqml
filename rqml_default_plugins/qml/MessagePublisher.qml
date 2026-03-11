import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import RQml.Utils

Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(350, 500)
    color: palette.base

    Component.onCompleted: {
        if (context.messages === undefined)
            context.messages = [];

        for (let i = 0; i < context.messages.length; i++) {
            const msg = context.messages[i];
            messagesListModel.append(msg);
        }
    }

    function addMessageEntry(topic, type, rate) {
        const entry = {
            topic: topic,
            type: type,
            content: MessageUtils.toJavaScriptObject(Ros2.createEmptyMessage(type)),
            enabled: false,
            rate: rate
        };
        let values = Array.from(context.messages);
        values.push(entry);
        context.messages = values;
        messagesListModel.append(entry);
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

    function removeEntry(index) {
        let values = Array.from(context.messages);
        values.splice(index, 1);
        context.messages = values;
        messagesListModel.remove(index);
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
                Layout.fillWidth: true
                placeholderText: qsTr("Topic")
                onTextChanged: typeSelect.refresh()
                function refresh() {
                    model = Ros2.queryTopics();
                    if (!text) text = model.length > 0 ? model[0] : "";
                }
                Component.onCompleted: refresh()
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
                Layout.fillWidth: true
                placeholderText: qsTr("Message Type")
                function refresh() {
                    model = Ros2.getTopicTypes(topicSelect.text);
                    if (model.length > 0) text = model[0];
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

            Button {
                text: "Add Message"
                onClicked: root.addMessageEntry(topicSelect.text, typeSelect.text, 1)
                enabled: Ros2.isValidTopic(topicSelect.text)
            }
        }
        ListView {
            id: messagesListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: messagesListModel
            delegate: Rectangle {
                width: messagesListView.width
                height: 48
                color: index % 2 == 1 ? root.palette.alternateBase : root.palette.base
                RowLayout {
                    anchors.fill: parent

                    Timer {
                        interval: model.rate > 0 ? 1000 / model.rate : 0
                        repeat: true
                        running: model.enabled && model.rate > 0
                        property var publisher: Ros2.createPublisher(model.topic, model.type)
                        onTriggered: {
                            publisher.publish(model.content);
                        }
                    }

                    CheckBox {
                        id: enabledCheckBox
                        Layout.rowSpan: 2
                        checked: model.enabled
                        onCheckedChanged: {
                            if (checked == model.enabled)
                                return;
                            root.updateEntry(model.index, {
                                enabled: checked
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
                                text: model.type.replace("/msg/", "/")
                                font.pointSize: 9
                                font.italic: true
                            }
                        }

                        TruncatedLabel {
                            Layout.fillWidth: true
                            Layout.columnSpan: 4
                            elide: Text.ElideRight
                            text: JSON.stringify(MessageUtils.stripEmptyFields(model.content) ?? {})
                        }
                    }
                    DecimalSpinBox {
                        id: rateSpinBox
                        implicitWidth: 128
                        to: 999
                        editable: true
                        value: model.rate
                        onValueChanged: {
                            if (value == model.rate)
                                return;
                            root.updateEntry(model.index, {
                                rate: value
                            });
                            model.rate = value;
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 48
                        implicitHeight: 48
                        text: IconFont.iconEdit
                        font.family: IconFont.name
                        font.pixelSize: 20
                        onClicked: editDialog.open()
                        ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
                        ToolTip.visible: hovered || pressed
                        ToolTip.text: qsTr("Edit message content")
                    }

                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 48
                        implicitHeight: 48
                        text: IconFont.iconTrash
                        font.family: IconFont.name
                        font.pixelSize: 20
                        onClicked: removeEntry(model.index)
                        ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
                        ToolTip.visible: hovered || pressed
                        ToolTip.text: qsTr("Delete message entry")
                    }

                    EditMessageDialog {
                        id: editDialog
                        anchors.centerIn: Overlay.overlay
                        width: 600
                        height: Math.max(400, (Overlay.overlay?.height ?? 0) * 0.8)
                        modal: true
                        onAboutToShow: {
                            message = model.content;
                        }
                        onAccepted: {
                            let type = message["#messageType"] || model.type;
                            root.updateEntry(model.index, {
                                content: message,
                                type: type
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
