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

Slider {
    id: control
    property real currentValue: 0
    property real currentValueVisualPosition: {
        const percent = Math.min(1, Math.max(0, (currentValue - from) / (to - from)));
        return LayoutMirroring.enabled ? 1 - percent : percent;
    }
    stepSize: (to - from) / 1000

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        implicitWidth: 200
        implicitHeight: 8
        width: control.availableWidth
        height: implicitHeight
        radius: 4
        color: "#bdbebf"
        clip: true

        Rectangle {
            width: Math.max(control.visualPosition, control.currentValueVisualPosition) * parent.width
            height: parent.height
            color: "#4cce54"
            radius: parent.radius
        }

        Rectangle {
            width: Math.min(control.visualPosition, control.currentValueVisualPosition) * parent.width
            height: parent.height
            color: "#35833a"
            radius: parent.radius
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        implicitWidth: 8
        implicitHeight: 26
        radius: 4
        color: control.pressed ? "#15b3af" : "#21be2b"
    }
}
