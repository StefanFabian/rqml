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

    readonly property int count: toastModel.count
    property int dismissDuration: 5000
    property int maxToasts: 5

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
    function removeToastById(id) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).toastId === id) {
                toastModel.remove(i);
                break;
            }
        }
    }
    function show(message, level) {
        if (toastModel.count >= root.maxToasts) {
            toastModel.remove(0);
        }
        let toastId = createToastId();
        while (getToastById(toastId) !== null)
            toastId = createToastId();
        toastModel.append({
            "toastId": toastId,
            "message": message,
            "level": level || "info"
        });
    }

    anchors.bottom: parent.bottom
    anchors.margins: 12
    anchors.right: parent.right
    height: toastListView.contentHeight
    width: Math.min(parent ? parent.width * 0.8 : 400, 420)

    ListModel {
        id: toastModel

    }
    ListView {
        id: toastListView

        anchors.fill: parent
        interactive: false
        model: toastModel
        spacing: 12

        add: Transition {
            NumberAnimation {
                duration: 250
                from: 0
                property: "opacity"
                to: 1
            }
            NumberAnimation {
                duration: 250
                from: 0.9
                property: "scale"
                to: 1
            }
        }
        delegate: Rectangle {
            id: toastItemDelegate

            required property string level
            required property string message
            required property string toastId

            clip: true
            color: root.getToastColor(toastItemDelegate.level)
            height: toastLayout.implicitHeight + progressBar.height + 24
            radius: 8
            width: toastListView.width

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
                    color: "white"
                    font.family: IconFont.name
                    font.pixelSize: 20
                    text: root.getToastIcon(toastItemDelegate.level)
                }
                Label {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    text: toastItemDelegate.message
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
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

                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.leftMargin: parent.radius
                color: Qt.rgba(1, 1, 1, 0.3)
                height: 4
                width: parent.width

                NumberAnimation on width {
                    id: progressAnim

                    duration: root.dismissDuration
                    from: toastItemDelegate.width
                    paused: toastHover.hovered
                    running: true
                    to: 0

                    onStopped: {
                        if (progressBar.width === 0) {
                            root.removeToastById(toastItemDelegate.toastId);
                        }
                    }
                }
            }
        }
        move: Transition {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
                properties: "y"
            }
        }
        remove: Transition {
            NumberAnimation {
                duration: 200
                property: "opacity"
                to: 0
            }
            NumberAnimation {
                duration: 200
                property: "scale"
                to: 0.9
            }
        }
    }
}
