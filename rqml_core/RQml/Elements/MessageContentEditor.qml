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
import "../Fonts"

TreeView {
    id: control

    property bool readonly: false

    // Return/Enter reached a row without being consumed by its input, e.g. Return in a single-line
    // field or Ctrl+Return in a multi-line one.
    signal submitted

    clip: true
    columnWidthProvider: function (column) {
        if (column === 0)
            return explicitColumnWidth(column) || implicitColumnWidth(column);
        return Math.max(160, width - columnWidth(0) - columnSpacing);
    }
    flickableDirection: Flickable.AutoFlickIfNeeded

    delegate: TreeViewDelegate {
        id: delegate

        contentItem: {
            // model has properties:
            // objectName, index, row, column, model, hasModelChildren, isArrayElement, edit, display, statusTip, whatsThis, decoration, type, toolTip
            if (model.edit == null) {
                let text = String(model.display ?? "");
                return labelComponent.createObject(delegate, {
                    "text": model.isArrayElement ? "[" + text + "]" : text
                });
            }
            if (control.readonly) {
                return labelComponent.createObject(delegate, {
                    "text": model.type === "array" || model.type === "compound" ? "" : String(model.display ?? "")
                });
            }
            let layout = rowLayoutComponent.createObject(delegate);
            let component = null;
            switch (model.type) {
            case "array":
                component = addRowButtonComponent.createObject(layout, {
                    "model": model
                });
                break;
            case "compound":
                component = null;
                break;
            case "bool":
                component = checkboxComponent.createObject(layout, {
                    "checked": !!model.edit
                });
                component.checkedChanged.connect(function () {
                    if (model.edit == component.checked)
                        return;
                    model.edit = component.checked;
                    component.checked = model.edit;
                });
                break;
            case "uint8":
            case "uint16":
            case "uint32":
            case "uint64":
                {
                    const size = model.type.substring(4);
                    const maxValue = size === "8" ? 255 : size === "16" ? 65535 : size === "32" ? 4294967295.0 : 18446744073709551615.0;
                    component = integerFieldComponent.createObject(layout, {
                        "from": 0,
                        "to": maxValue,
                        "value": model.edit ?? 0
                    });
                    component.valueChanged.connect(function () {
                        model.edit = component.value;
                    });
                    break;
                }
            case "int8":
            case "int16":
            case "int32":
            case "int64":
                {
                    const size = model.type.substring(3);
                    const minValue = size === "8" ? -128 : size === "16" ? -32768 : size === "32" ? -2147483648 : -9223372036854775808.0;
                    const maxValue = size === "8" ? 127 : size === "16" ? 32767 : size === "32" ? 2147483647 : 9223372036854775807.0;
                    component = integerFieldComponent.createObject(layout, {
                        "from": minValue,
                        "to": maxValue,
                        "value": model.edit ?? 0
                    });
                    component.valueChanged.connect(function () {
                        model.edit = component.value;
                    });
                    break;
                }
            case "float":
            case "double":
                component = doubleFieldComponent.createObject(layout, {
                    "value": model.edit ?? 0.0
                });
                component.valueChanged.connect(function () {
                    model.edit = component.value;
                });
                break;
            case "string":
            case "wstring":
                if (model.edit.length > 40) {
                    component = textArea.createObject(layout, {
                        "text": String(model.edit ?? "")
                    });
                    component.textChanged.connect(function () {
                        if (model.edit == component.text)
                            return;
                        model.edit = component.text;
                        component.text = model.edit;
                    });
                } else {
                    component = textFieldComponent.createObject(layout, {
                        "text": String(model.edit ?? "")
                    });
                    component.textChanged.connect(function () {
                        if (model.edit == component.text)
                            return;
                        model.edit = component.text;
                        component.text = model.edit;
                    });
                }
                break;
            default:
                component = textFieldComponent.createObject(layout, {
                    "text": String(model.edit ?? "DEFAULT")
                });
                component.textChanged.connect(function () {
                    if (model.edit == component.text)
                        return;
                    model.edit = component.text;
                    component.text = model.edit;
                });
            }
            if (model.isArrayElement) {
                const deleteButton = deleteRowButtonComponent.createObject(layout, {
                    "model": model
                });
            }
            return layout;
        }
        implicitHeight: 48

        // Runs before the delegate's button handling, which presses the row on Return with some
        // platform themes (e.g. GTK).
        Keys.onPressed: event => {
            if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                return;
            event.accepted = true;
            control.submitted();
        }
    }

    Component {
        id: labelComponent

        TruncatedLabel {
        }
    }
    Component {
        id: rowLayoutComponent

        RowLayout {
            implicitHeight: 48
        }
    }
    Component {
        id: addRowButtonComponent

        Button {
            property var model

            // Themes where only Space presses buttons would let Return bubble up and submit.
            Keys.priority: Keys.AfterItem
            Layout.alignment: Qt.AlignRight
            Layout.rightMargin: 8
            font.family: IconFont.name
            font.pixelSize: 24
            implicitHeight: 48
            implicitWidth: 48
            text: IconFont.iconAdd

            Keys.onPressed: event => event.accepted = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            onClicked: {
                const childCount = control.model.rowCount(model.treeIndex);
                control.model.insertRow(childCount, model.treeIndex);
            }
        }
    }
    Component {
        id: deleteRowButtonComponent

        Button {
            property var model

            // Themes where only Space presses buttons would let Return bubble up and submit.
            Keys.priority: Keys.AfterItem
            Layout.alignment: Qt.AlignRight
            Layout.rightMargin: 8
            font.family: IconFont.name
            font.pixelSize: 20
            implicitHeight: 48
            implicitWidth: 48
            text: IconFont.iconTrash

            Keys.onPressed: event => event.accepted = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            onClicked: {
                control.model.removeRow(model.treeIndex.row, model.treeIndex.parent);
            }
        }
    }
    Component {
        id: textArea

        TextArea {
            Layout.fillWidth: true
        }
    }
    Component {
        id: textFieldComponent

        TextField {
            Layout.fillWidth: true
        }
    }
    Component {
        id: checkboxComponent

        CheckBox {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
        }
    }
    Component {
        id: integerFieldComponent

        IntegerInputField {
            id: numberField

            Layout.fillWidth: true
        }
    }
    Component {
        id: doubleFieldComponent

        DecimalInputField {
            id: doubleField

            Layout.fillWidth: true
        }
    }
}
