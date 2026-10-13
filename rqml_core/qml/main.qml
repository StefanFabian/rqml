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
import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import com.kdab.dockwidgets 2.0 as KDDW
import Ros2
import QtQml.Models
import RQml.Elements
import "UsageHints.js" as UsageHints
import "."

ApplicationWindow {
    id: mainWindow

    property string currentShortcutHint: UsageHints.getHint("")

    color: active ? palette.active.window : palette.inactive.window
    height: 480
    minimumHeight: 320
    minimumWidth: 480
    title: "RQml" + (RQml.devMode ? " [DEV MODE]" : "")
    visible: true
    width: 640

    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")

            Action {
                shortcut: "Ctrl+S"
                text: qsTr("Save config")

                onTriggered: {
                    RQml.save();
                }
            }
            Action {
                shortcut: "Ctrl+Shift+S"
                text: qsTr("Save config as…")

                onTriggered: {
                    saveConfigDialog.openAndFocus();
                }
            }
            Action {
                shortcut: "Ctrl+O"
                text: qsTr("Load config")

                onTriggered: {
                    openConfigDialog.recent = false;
                    openConfigDialog.openAndFocus();
                }
            }
            Action {
                shortcut: "Ctrl+R"
                text: qsTr("Recent configs")

                onTriggered: {
                    openConfigDialog.recent = true;
                    openConfigDialog.openAndFocus();
                }
            }
            MenuSeparator {
            }
            Action {
                text: qsTr("Reload current config")

                onTriggered: {
                    RQml.load(RQml.currentConfig.path);
                }
            }
            Action {
                id: selectNextPluginAction
                shortcut: "Ctrl+Tab"
                text: qsTr("Select next plugin")

                onTriggered: {
                    RQml.selectNextPlugin();
                }
            }
            Action {
                id: selectPreviousPluginAction
                shortcut: "Ctrl+Shift+Tab"
                text: qsTr("Select previous plugin")

                onTriggered: {
                    RQml.selectPreviousPlugin();
                }
            }
            Action {
                id: closeSelectedPluginAction
                shortcut: "Ctrl+W"
                text: qsTr("Close selected plugin")

                onTriggered: {
                    RQml.closeFocusedPlugin();
                }
            }
            Action {
                id: closeAllPluginsAction
                shortcut: "Ctrl+Shift+W"
                text: qsTr("Close All")

                onTriggered: {
                    KDDW.Singletons.dockRegistry.clear();
                }
            }
            Action {
                text: qsTr("Settings")

                onTriggered: {
                    settingsDialog.open();
                }
            }
            MenuSeparator {
            }
            Action {
                shortcut: "Ctrl+Q"
                text: qsTr("&Quit")

                onTriggered: {
                    Qt.quit();
                }
            }
        }
        MenuSeparator {
        }
        Menu {
            id: pluginsMenu
            title: qsTr("&Plugins")

            Action {
                shortcut: "Ctrl+P"
                text: qsTr("Search plugins…")

                onTriggered: {
                    openPluginDialog.openAndFocus();
                }
            }
            MenuSeparator {
            }
            Instantiator {
                model: {
                    let groups = new Set();
                    RQml.plugins.forEach(plugin => {
                            if (plugin.group) {
                                groups.add(plugin.group);
                            }
                        });
                    return Array.from(groups);
                }

                onObjectAdded: (index, object) => pluginsMenu.insertMenu(index + 2, object)
                onObjectRemoved: (index, object) => pluginsMenu.removeMenu(index + 2, object)

                Menu {
                    title: modelData

                    Repeater {
                        model: RQml.plugins.filter(plugin => plugin.group === modelData)

                        MenuItem {
                            text: modelData.name

                            onTriggered: {
                                let instance = RQml.createPlugin(modelData.id);
                                if (!instance)
                                    return;
                                rootDockingArea.addDockWidget(instance, KDDW.KDDockWidgets.Location_OnRight);
                            }
                        }
                    }
                }
            }
            Repeater {
                model: RQml.plugins.filter(plugin => plugin.group === "")

                MenuItem {
                    text: modelData.name

                    onTriggered: {
                        let instance = RQml.createPlugin(modelData.id);
                        if (!instance)
                            return;
                        rootDockingArea.addDockWidget(instance, KDDW.KDDockWidgets.Location_OnRight);
                    }
                }
            }
        }
        Menu {
            title: qsTr("&Help")

            Action {
                checkable: true
                checked: RQml.devMode
                text: qsTr("Dev Mode")

                onToggled: RQml.devMode = checked
            }
            Action {
                enabled: RQml.canCreateDesktopEntry()
                text: qsTr("Create Desktop Entry")

                onTriggered: {
                    RQml.createDesktopEntry();
                }
            }
            Action {
                text: qsTr("About")

                onTriggered: {
                    aboutDialog.open();
                }
            }
        }
    }

    Component.onCompleted: {
        if (!Ros2.isInitialized()) {
            Ros2.init("rqml");
        }
    }

    // Action shortcuts only fire while the main window is active. Mirror the plugin selection ones
    // application wide so they also work from floating plugin windows.
    Instantiator {
        model: [selectNextPluginAction, selectPreviousPluginAction, closeSelectedPluginAction, closeAllPluginsAction]

        delegate: Shortcut {
            required property var modelData

            context: Qt.ApplicationShortcut
            enabled: !mainWindow.active
            sequence: modelData.shortcut

            onActivated: modelData.trigger()
        }
    }
    Row {
        id: noPluginsLoadedRow
        anchors.centerIn: parent
        spacing: -Qt.application.font.pixelSize * 2

        ColumnLayout {
            id: noPluginsLoadedMessage
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Qt.application.font.pixelSize * 2
            spacing: Qt.application.font.pixelSize / 2

            Label {
                font.bold: true
                font.pixelSize: Qt.application.font.pixelSize * 1.6
                text: qsTr("No plugins loaded.")
            }
            Label {
                font.pixelSize: Qt.application.font.pixelSize * 1.2
                text: qsTr("Load plugins from the 'Plugins' menu.")
            }
        }
        Image {
            fillMode: Image.PreserveAspectFit
            height: Qt.application.font.pixelSize * 12
            mipmap: true
            source: "qrc:/assets/mascot/magnifying_glass.png"
        }
    }
    Hint {
        anchors.horizontalCenter: noPluginsLoadedRow.horizontalCenter
        anchors.top: noPluginsLoadedRow.bottom
        anchors.topMargin: 32
        text: qsTr("Hint: %1").arg(mainWindow.currentShortcutHint)
        width: Math.min(implicitWidth, noPluginsLoadedRow.width)
    }
    Timer {
        interval: 30000
        repeat: true
        running: true

        onTriggered: {
            mainWindow.currentShortcutHint = UsageHints.getHint(mainWindow.currentShortcutHint);
        }
    }
    KDDW.DockingArea {
        id: rootDockingArea
        anchors.fill: parent
        // Each main layout needs a unique id
        uniqueName: "MainLayout-1"
    }
    AboutDialog {
        id: aboutDialog
    }
    SettingsDialog {
        id: settingsDialog
    }
    OpenConfigDialog {
        id: openConfigDialog
    }
    OpenPluginDialog {
        id: openPluginDialog
    }
    SaveConfigDialog {
        id: saveConfigDialog
    }
}
