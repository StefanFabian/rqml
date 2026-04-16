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
import QtQuick.Layouts
import RQml.Utils

Dialog {
    id: root

    property bool recent: false

    function openAndFocus() {
        open();
        // reset filter and selection
        filterInput.text = "";
        configsList.currentIndex = 0;
        d.updateFilteredModel();
        filterInput.forceActiveFocus();
    }

    focus: true
    height: Math.min(mainWindow.height * 0.6, 480)
    padding: 12
    standardButtons: Dialog.NoButton
    title: recent ? qsTr("Recent Configurations") : qsTr("Configurations")
    width: Math.min(mainWindow.width * 0.8, 640)
    x: (parent.width - width) / 2
    y: 0

    QtObject {
        id: d
        function loadSelected() {
            if (configsList.currentIndex >= 0 && configsList.currentIndex < filteredModel.count) {
                const item = filteredModel.get(configsList.currentIndex);
                if (item && item.path) {
                    RQml.load(item.path);
                    root.close();
                }
            }
        }
        function updateFilteredModel() {
            filteredModel.clear();
            const query = filterInput.text;
            let input = recent ? RQml.recentConfigs : RQml.configs;
            input = input || [];
            const matches = [];
            input.forEach(cfg => {
                    const name = cfg.path.split("/").pop().split(".").slice(0, -1).join(".");
                    const path = cfg.path;
                    const score = FuzzySearch.scoreFields([name, path], query);
                    if (score < 0)
                        return;
                    matches.push({
                            "name": name,
                            "path": path,
                            "score": score
                        });
                });
            if (FuzzySearch.splitTerms(query).length > 0) {
                matches.sort((a, b) => {
                        if (b.score !== a.score)
                            return b.score - a.score;
                        if (a.name !== b.name)
                            return a.name.localeCompare(b.name);
                        return a.path.localeCompare(b.path);
                    });
            }
            matches.forEach(item => filteredModel.append({
                            "name": item.name,
                            "path": item.path
                        }));
            // clamp selection within bounds
            configsList.currentIndex = Math.min(Math.max(0, filteredModel.count > 0 ? 0 : -1), filteredModel.count - 1);
        }
    }
    ListModel {
        id: filteredModel
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        TextField {
            id: filterInput
            Layout.fillWidth: true
            focus: true
            objectName: "openConfigDialogFilterInput"
            placeholderText: qsTr("Type to filter configs…")

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    configsList.moveDown();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    configsList.moveUp();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    d.loadSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
            onTextChanged: d.updateFilteredModel()
        }
        ListView {
            id: configsList
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
            model: filteredModel
            objectName: "openConfigDialogList"

            delegate: ItemDelegate {
                highlighted: index === configsList.currentIndex
                text: (model.name || model.path)
                width: configsList.width

                contentItem: Column {
                    spacing: 2
                    width: parent.width - 16
                    x: 8

                    Label {
                        Layout.topMargin: 4
                        elide: Text.ElideRight
                        font.bold: true
                        text: model.name || model.path
                        width: parent.width
                    }
                    Label {
                        Layout.bottomMargin: 4
                        elide: Text.ElideMiddle
                        font.pixelSize: Math.round(Qt.application.font.pixelSize * 0.9)
                        opacity: 0.7
                        text: model.path
                        width: parent.width
                    }
                }

                onClicked: {
                    configsList.currentIndex = index;
                    d.loadSelected();
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    configsList.moveDown();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    configsList.moveUp();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    d.loadSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }
    }
}
