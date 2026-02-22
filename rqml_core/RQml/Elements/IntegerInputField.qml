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

TextField {
    selectByMouse: true
    property var from: null
    property var to: null
    property var value: 0
    text: Number(value).toFixed(0)
    onEditingFinished: {
        if (text.length == 0) {
            text = Qt.binding(() => Number(value).toFixed(0));
            return;
        }
        let newValue = parseInt(text);
        if (isNaN(newValue)) {
            text = Qt.binding(() => Number(value).toFixed(0));
            return;
        }
        if (from != null && newValue < from) {
            newValue = from;
            text = Qt.binding(() => Number(value).toFixed(0));
        } else if (to != null && newValue > to) {
            newValue = to;
            text = Qt.binding(() => Number(value).toFixed(0));
        }
        if (newValue == value)
            return;
        value = newValue;
    }
    validator: RegularExpressionValidator {
        regularExpression: /^-?[0-9]*$/
    }
}
