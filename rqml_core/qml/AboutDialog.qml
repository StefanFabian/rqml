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

Dialog {
    id: aboutDialog

    anchors.centerIn: parent
    modal: true
    padding: 20
    standardButtons: Dialog.Ok
    title: qsTr("About RQml")
    visible: false

    ColumnLayout {
        Label {
            text: qsTr("RQml is a Qt/QML based GUI for ROS2.")
            wrapMode: Text.Wrap
        }
        Label {
            text: qsTr("Qt version: %1").arg(QtVersion)
        }
        Label {
            text: qsTr("Version: %1").arg("1.2025.120")
            wrapMode: Text.Wrap
        }
        Label {
            text: qsTr("Author: Stefan Fabian")
            wrapMode: Text.Wrap
        }
        Label {
            text: qsTr("License: GPLv3")
            wrapMode: Text.Wrap
        }
        Label {
            text: qsTr("This is free software but donations are welcome :)")
            wrapMode: Text.Wrap
        }
        Label {
            text: "<a href='https://github.com/StefanFabian/rqml'>GitHub</a>"

            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
