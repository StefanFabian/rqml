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
  implicitHeight: 48
  implicitWidth: 48
  font.family: IconFont.name
  font.pixelSize: 20
  text: IconFont.iconRefresh
  radius: 4
  property bool animate
  onAnimateChanged: {
    if (!animate) return
    reloadRotationAnimator.running = true
  }
  contentItem: Label {
    id: reloadIcon
    anchors.centerIn: control
    width: Math.min(control.width - control.padding, control.height - control.padding)
    height: width
    font.family: control.font.family
    font.pointSize: 1000
    text: control.text
    minimumPointSize: 4
    fontSizeMode: Text.Fit
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    SequentialAnimation {
      id: reloadRotationAnimator
      loops: Animation.Infinite
      running: false

      RotationAnimation {
        target: reloadIcon
        from: 0; to: 360
        duration: 600
        easing.type: Easing.InOutQuad
      }
      PauseAnimation { duration: 400 }
      // Check if we should rotate another time
      ScriptAction {
        script: {
          if (control.animate) return
          reloadRotationAnimator.running = false
        }
      }
    }
  }
}
