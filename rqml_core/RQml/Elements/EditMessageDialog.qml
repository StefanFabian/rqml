/*
 * Copyright (C) 2025  Stefan Fabian
 *
 * This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import RQml.Utils

Dialog {
    id: control

    property alias message: messageModel.message
    property alias messageType: messageModel.messageType
    property bool readonly: false

    standardButtons: readonly ? Dialog.Close : Dialog.Ok | Dialog.Cancel
    title: "Edit Message Content"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        TabBar {
            id: tabBar
            Layout.fillWidth: true

            TabButton {
                objectName: "editMessageDialogVisualTabButton"
                text: qsTr("Visual")
            }
            TabButton {
                objectName: "editMessageDialogJsonTabButton"
                text: qsTr("JSON")
            }
        }
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: tabBar.currentIndex

            MessageContentEditor {
                id: messageContentEditor
                Layout.fillHeight: true
                Layout.fillWidth: true
                readonly: control.readonly

                model: MessageItemModel {
                    id: messageModel
                    onMessageChanged: {
                        messageContentEditor.expandRecursively();
                    }
                    onModified: {
                        textArea.text = Qt.binding(() => JSON.stringify(MessageUtils.toJavaScriptObject(control.message) ?? {}, null, 2));
                    }
                }
            }
            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true
                spacing: 8

                ScrollView {
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    TextArea {
                        id: textArea
                        anchors.fill: parent
                        objectName: "editMessageDialogJsonTextArea"
                        readOnly: control.readonly
                        text: JSON.stringify(MessageUtils.toJavaScriptObject(control.message) ?? {}, null, 2)
                        wrapMode: TextEdit.NoWrap

                        onEditingFinished: {
                            if (control.readonly)
                                return;
                            try {
                                control.message = JSON.parse(text);
                            } catch (e)
                            // ignore parse errors
                            {
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }
                    IconTextButton {
                        id: copyJsonButton
                        iconText: IconFont.iconCopy
                        objectName: "editMessageDialogCopyJsonButton"
                        text: qsTr("Copy JSON")

                        onClicked: RQml.copyTextToClipboard(textArea.text)
                    }
                }
            }
        }
    }
}
