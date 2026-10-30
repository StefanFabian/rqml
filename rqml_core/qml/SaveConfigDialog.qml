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
import QtQml.Models
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Dialog {
    id: root

    function openAndFocus() {
        open();
        nameInput.forceActiveFocus();
    }

    focus: true
    height: Math.min(mainWindow.height * 0.6, 480)
    padding: 12
    standardButtons: Dialog.NoButton
    title: qsTr("Save Configuration")
    width: Math.min(mainWindow.width * 0.6, 640)
    x: (parent.width - width) / 2
    y: 0

    QtObject {
        id: d

        function save() {
            let name = nameInput.text.trim();
            if (name.length === 0 || name.indexOf("/") !== -1) {
                return;
            }
            let directory = RQml.configDirectories[configDirectoriesList.currentIndex];
            let path = directory + "/" + name + ".rqml";
            // Check if file exists
            if (RQml.fileExists(path)) {
                let overwrite = Qt.createQmlObject('import QtQuick.Dialogs; MessageDialog { title: "Overwrite Confirmation"; text: "A configuration named \\"' + name + '\\" already exists in the selected directory. Do you want to overwrite it?"; buttons: MessageDialog.Yes | MessageDialog.Cancel; }', root);
                overwrite.buttonClicked.connect(function (button) {
                    if (button === MessageDialog.Yes) {
                        RQml.save(path);
                        nameInput.text = "";
                        root.close();
                    }
                    overwrite.destroy();
                });
                overwrite.open();
                return;
            }
            RQml.save(path);
            nameInput.text = "";
            root.close();
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        TextField {
            id: nameInput

            Layout.fillWidth: true
            focus: true
            placeholderText: qsTr("Enter name for configuration")

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    configDirectoriesList.moveDown();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    configDirectoriesList.moveUp();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    d.save();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }
        Label {
            font.bold: true
            text: qsTr("Select directory to save configuration:")
        }
        ListView {
            id: configDirectoriesList

            function moveDown() {
                let newCurrentIndex = currentIndex + 1;
                if (newCurrentIndex >= model.count)
                    newCurrentIndex = 0;
                currentIndex = newCurrentIndex;
            }
            function moveUp() {
                let newCurrentIndex = currentIndex - 1;
                if (newCurrentIndex < 0)
                    newCurrentIndex = model.count - 1;
                currentIndex = newCurrentIndex;
            }

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            currentIndex: 0
            model: RQml.configDirectories

            delegate: ItemDelegate {
                highlighted: ListView.isCurrentItem
                width: configDirectoriesList.width

                contentItem: Column {
                    spacing: 2
                    width: parent.width - 16
                    x: 8

                    Label {
                        Layout.topMargin: 4
                        elide: Text.ElideRight
                        font.bold: true
                        text: modelData.split("/").pop()
                        width: parent.width
                    }
                    Label {
                        Layout.bottomMargin: 4
                        elide: Text.ElideMiddle
                        font.pixelSize: Math.round(Qt.application.font.pixelSize * 0.9)
                        opacity: 0.7
                        text: modelData
                        width: parent.width
                    }
                }

                onClicked: {
                    configDirectoriesList.currentIndex = index;
                    nameInput.forceActiveFocus();
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    moveDown();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    moveUp();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    d.save();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }
    }
}
