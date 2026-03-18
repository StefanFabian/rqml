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
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Fonts

Item {
    id: root
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 12
    width: Math.min(parent ? parent.width * 0.8 : 400, 420)
    height: toastListView.contentHeight

    property int maxToasts: 5
    property int dismissDuration: 5000
    readonly property int count: toastModel.count

    function show(message, level) {
        if (toastModel.count >= root.maxToasts) {
            toastModel.remove(0);
        }
        let toastId = createToastId();
        while (getToastById(toastId) !== null)
            toastId = createToastId();
        toastModel.append({
            toastId: toastId,
            message: message,
            level: level || "info"
        });
    }

    function createToastId() {
        return Math.random().toString(36).substring(7);
    }

    function getToastById(id) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).toastId === id) {
                return toastModel.get(i);
            }
        }
        return null;
    }

    function removeToastById(id) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).toastId === id) {
                toastModel.remove(i);
                break;
            }
        }
    }

    function getToastColor(level) {
        switch (level) {
        case "error":
            return Material.color(Material.Red, Material.Shade800);
        case "warning":
            return Material.color(Material.Orange, Material.Shade800);
        default:
            return Material.color(Material.BlueGrey, Material.Shade800);
        }
    }

    function getToastIcon(level) {
        switch (level) {
        case "error":
            return IconFont.iconError;
        case "warning":
            return IconFont.iconWarning;
        default:
            return IconFont.iconInfo;
        }
    }

    ListModel {
        id: toastModel
    }

    ListView {
        id: toastListView
        anchors.fill: parent
        model: toastModel
        spacing: 12
        interactive: false

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 250
            }
            NumberAnimation {
                property: "scale"
                from: 0.9
                to: 1
                duration: 250
            }
        }

        move: Transition {
            NumberAnimation {
                properties: "y"
                duration: 250
                easing.type: Easing.OutCubic
            }
        }

        remove: Transition {
            NumberAnimation {
                property: "opacity"
                to: 0
                duration: 200
            }
            NumberAnimation {
                property: "scale"
                to: 0.9
                duration: 200
            }
        }

        delegate: Rectangle {
            id: toastItemDelegate

            required property string toastId
            required property string message
            required property string level

            width: toastListView.width
            height: toastLayout.implicitHeight + progressBar.height + 24
            radius: 8
            clip: true

            color: root.getToastColor(toastItemDelegate.level)

            HoverHandler {
                id: toastHover
            }

            RowLayout {
                id: toastLayout
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    font.family: IconFont.name
                    font.pixelSize: 20
                    color: "white"
                    text: root.getToastIcon(toastItemDelegate.level)
                }

                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "white"
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    verticalAlignment: Text.AlignVCenter
                    text: toastItemDelegate.message
                }

                IconButton {
                    id: closeButton
                    Layout.alignment: Qt.AlignVCenter
                    flat: true
                    radius: width / 2
                    text: "\u2715"
                    onClicked: root.removeToastById(toastItemDelegate.toastId)
                }
            }

            Rectangle {
                id: progressBar
                anchors.left: parent.left
                anchors.leftMargin: parent.radius
                anchors.bottom: parent.bottom
                height: 4
                color: Qt.rgba(1, 1, 1, 0.3)
                width: parent.width

                NumberAnimation on width {
                    id: progressAnim
                    from: toastItemDelegate.width
                    to: 0
                    duration: root.dismissDuration
                    running: true
                    paused: toastHover.hovered
                    onStopped: {
                        if (progressBar.width === 0) {
                            root.removeToastById(toastItemDelegate.toastId);
                        }
                    }
                }
            }
        }
    }
}
