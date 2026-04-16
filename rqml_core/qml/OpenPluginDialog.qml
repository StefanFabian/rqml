/*
 * Copyright (C) 2026  Stefan Fabian
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
import com.kdab.dockwidgets 2.0 as KDDW
import RQml.Utils

Dialog {
    id: root
    function openAndFocus() {
        open();
        filterInput.text = "";
        d.updateFilteredModel();
        filterInput.forceActiveFocus();
    }

    focus: true
    height: Math.min(mainWindow.height * 0.6, 480)
    padding: 12
    standardButtons: Dialog.NoButton
    title: qsTr("Add Plugin")
    width: Math.min(mainWindow.width * 0.8, 640)
    x: (parent.width - width) / 2
    y: 0

    QtObject {
        id: d
        function addSelected() {
            if (pluginsList.currentIndex < 0 || pluginsList.currentIndex >= filteredModel.count)
                return;
            const item = filteredModel.get(pluginsList.currentIndex);
            if (!item || !item.enabled)
                return;
            const instance = RQml.createPlugin(item.id);
            if (!instance)
                return;
            rootDockingArea.addDockWidget(instance, KDDW.KDDockWidgets.Location_OnRight);
            root.close();
        }
        function updateFilteredModel() {
            filteredModel.clear();
            const query = filterInput.text;
            const plugins = RQml.plugins || [];
            const matches = [];
            plugins.forEach(plugin => {
                    const groupName = plugin.group || "";
                    const score = FuzzySearch.scoreFields([plugin.name, plugin.id, groupName], query);
                    if (score < 0)
                        return;
                    matches.push({
                            "id": plugin.id,
                            "name": plugin.name,
                            "group": groupName,
                            "enabled": RQml.canCreatePlugin(plugin.id),
                            "score": score
                        });
                });
            if (FuzzySearch.splitTerms(query).length > 0) {
                matches.sort((a, b) => {
                        if (b.score !== a.score)
                            return b.score - a.score;
                        if (a.name !== b.name)
                            return a.name.localeCompare(b.name);
                        return a.id.localeCompare(b.id);
                    });
            }
            matches.forEach(item => filteredModel.append({
                            "id": item.id,
                            "name": item.name,
                            "group": item.group,
                            "enabled": item.enabled
                        }));
            pluginsList.currentIndex = filteredModel.count > 0 ? 0 : -1;
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
            objectName: "openPluginDialogFilterInput"
            placeholderText: qsTr("Type to filter plugins…")

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    pluginsList.moveDown();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    pluginsList.moveUp();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    d.addSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
            onTextChanged: d.updateFilteredModel()
        }
        ListView {
            id: pluginsList
            function moveDown() {
                if (model.count <= 0)
                    return;
                let newCurrentIndex = currentIndex + 1;
                if (newCurrentIndex >= model.count)
                    newCurrentIndex = 0;
                currentIndex = newCurrentIndex;
                positionViewAtIndex(newCurrentIndex, newCurrentIndex === 0 ? ListView.Beginning : ListView.Contain);
            }
            function moveUp() {
                if (model.count <= 0)
                    return;
                let newCurrentIndex = currentIndex - 1;
                if (newCurrentIndex < 0)
                    newCurrentIndex = model.count - 1;
                currentIndex = newCurrentIndex;
                positionViewAtIndex(newCurrentIndex, newCurrentIndex === model.count - 1 ? ListView.End : ListView.Contain);
            }

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            model: filteredModel
            objectName: "openPluginDialogList"

            delegate: ItemDelegate {
                ToolTip.text: qsTr("Already open (single-instance plugin)")
                ToolTip.visible: hovered && !model.enabled
                enabled: model.enabled
                highlighted: index === pluginsList.currentIndex
                width: pluginsList.width

                contentItem: Column {
                    spacing: 2
                    width: parent.width - 16
                    x: 8

                    Label {
                        Layout.topMargin: 4
                        elide: Text.ElideRight
                        font.bold: true
                        text: model.name
                        width: parent.width
                    }
                    Label {
                        Layout.bottomMargin: 4
                        elide: Text.ElideRight
                        font.pixelSize: Math.round(Qt.application.font.pixelSize * 0.9)
                        opacity: model.enabled ? 0.7 : 0.5
                        text: model.group ? model.group : qsTr("Ungrouped")
                        width: parent.width
                    }
                }

                onClicked: {
                    pluginsList.currentIndex = index;
                    d.addSelected();
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
                    d.addSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }
    }
}
