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

    onValueChanged: {
        let formatted = Number(value).toFixed(0);
        if (text !== formatted)
            text = formatted;
    }

    onEditingFinished: {
        if (text.length == 0) {
            text = Number(value).toFixed(0);
            return;
        }
        let newValue = parseInt(text);
        if (isNaN(newValue)) {
            text = Number(value).toFixed(0);
            return;
        }
        if (from !== null && from !== undefined && newValue < from) {
            newValue = from;
        } else if (to !== null && to !== undefined && newValue > to) {
            newValue = to;
        }

        if (newValue === value) {
            // Re-sync text even if value didn't change (e.g., input was "007" for value 7)
            let formatted = Number(value).toFixed(0);
            if (text !== formatted) text = formatted;
            return;
        }
        value = newValue;
    }

    validator: RegularExpressionValidator {
        regularExpression: /^-?[0-9]*$/
    }
}
