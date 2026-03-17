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

ColumnLayout {
    id: root
    property alias editable: spinBox.editable
    property double from: 0
    property double to: 100
    property double value: 0
    property int decimals: 1
    property real stepSize: 0.1
    property string suffix: ""
    readonly property int decimalFactor: Math.pow(10, decimals)
    property alias implicitWidth: spinBox.implicitWidth
    property alias implicitHeight: spinBox.implicitHeight

    onValueChanged: {
        spinBox.value = decimalToInt(value);
    }

    function decimalToInt(decimal) {
        return Math.round(decimal * decimalFactor);
    }

    SpinBox {
        id: spinBox
        from: decimalToInt(root.from)
        to: decimalToInt(root.to)
        value: decimalToInt(root.value)
        stepSize: decimalToInt(root.stepSize)
        editable: true
        width: parent.width
        height: parent.height

        onValueModified: {
            root.value = value / decimalFactor;
        }

        validator: DoubleValidator {
            bottom: Math.min(spinBox.from, spinBox.to)
            top: Math.max(spinBox.from, spinBox.to)
            decimals: root.decimals
            notation: DoubleValidator.StandardNotation
        }

        textFromValue: function (value, locale) {
            return Number(value / decimalFactor).toLocaleString(locale, 'f', root.decimals) + root.suffix;
        }

        valueFromText: function (text, locale) {
            const numberText = root.suffix && text.endsWith(root.suffix) ? text.substr(0, text.length - root.suffix.length) : text;
            return Math.round(Number.fromLocaleString(locale, numberText) * decimalFactor);
        }
    }
}
