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
import RQml.Fonts

RoundButton {
    id: control

    property bool animate

    font.family: IconFont.name
    font.pixelSize: 18
    implicitWidth: implicitHeight
    radius: 4
    text: IconFont.iconRefresh

    contentItem: Label {
        id: reloadIcon

        anchors.centerIn: control
        font: control.font
        height: width
        horizontalAlignment: Text.AlignHCenter
        text: control.text
        verticalAlignment: Text.AlignVCenter
        width: Math.min(control.width - control.padding, control.height - control.padding)

        SequentialAnimation {
            id: reloadRotationAnimator

            loops: Animation.Infinite
            running: false

            RotationAnimation {
                duration: 600
                easing.type: Easing.InOutQuad
                from: 0
                target: reloadIcon
                to: 360
            }
            PauseAnimation {
                duration: 400
            }
            // Check if we should rotate another time
            ScriptAction {
                script: {
                    if (control.animate)
                        return;
                    reloadRotationAnimator.running = false;
                }
            }
        }
    }

    onAnimateChanged: {
        if (!animate)
            return;
        reloadRotationAnimator.running = true;
    }
}
