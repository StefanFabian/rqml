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
    property real value: 0.0
    property int decimals: 3

    function formatValue(v) {
        return Number(v).toPrecision(decimals);
    }

    text: formatValue(value)

    onValueChanged: {
        let formatted = formatValue(value);
        if (text !== formatted)
            text = formatted;
    }

    onEditingFinished: {
        if (text.length == 0) {
            text = formatValue(value);
            return;
        }
        let newValue = parseFloat(text);
        if (isNaN(newValue)) {
            text = formatValue(value);
            return;
        }
        if (from !== null && from !== undefined && newValue < from)
            newValue = from;
        if (to !== null && to !== undefined && newValue > to)
            newValue = to;

        if (newValue === value) {
            let formatted = formatValue(value);
            if (text !== formatted)
                text = formatted;
            return;
        }
        value = newValue;
    }

    validator: RegularExpressionValidator {
        regularExpression: /^-?[0-9]*$|^-?([0-9]+\.[0-9]*)$/
    }
}
