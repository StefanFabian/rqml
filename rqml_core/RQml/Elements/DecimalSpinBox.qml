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

    readonly property int decimalFactor: Math.pow(10, decimals)
    property int decimals: 1
    property alias editable: spinBox.editable
    property double from: 0
    property alias implicitHeight: spinBox.implicitHeight
    property alias implicitWidth: spinBox.implicitWidth
    property real stepSize: 0.1
    property string suffix: ""
    property double to: 100
    property double value: 0

    function decimalToInt(decimal) {
        return Math.round(decimal * decimalFactor);
    }

    onValueChanged: {
        spinBox.value = decimalToInt(value);
    }

    SpinBox {
        id: spinBox

        editable: true
        from: decimalToInt(root.from)
        height: parent.height
        stepSize: decimalToInt(root.stepSize)
        textFromValue: function (value, locale) {
            return Number(value / decimalFactor).toLocaleString(locale, 'f', root.decimals) + root.suffix;
        }
        to: decimalToInt(root.to)
        value: decimalToInt(root.value)
        valueFromText: function (text, locale) {
            const numberText = root.suffix && text.endsWith(root.suffix) ? text.substr(0, text.length - root.suffix.length) : text;
            return Math.round(Number.fromLocaleString(locale, numberText) * decimalFactor);
        }
        width: parent.width

        validator: DoubleValidator {
            bottom: Math.min(spinBox.from, spinBox.to)
            decimals: root.decimals
            notation: DoubleValidator.StandardNotation
            top: Math.max(spinBox.from, spinBox.to)
        }

        onValueModified: {
            root.value = value / decimalFactor;
        }
    }
}
