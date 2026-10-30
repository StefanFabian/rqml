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
import RQml.Utils

// A TextField with a fuzzy-filtered dropdown.
//
// Usage:
//   FuzzySelector {
//       text: context.service
//       model: []
//       onTextChanged: context.service = text
//       Component.onCompleted: model = Ros2.queryServices()
//   }
Item {
    id: control

    // Internal state to show all items (browse mode) instead of just filtered ones.
    property bool _showAll: false

    // Index of the selected item in the original (unfiltered) model. -1 if none.
    property int currentIndex: -1

    // Text of the currently selected item (read-only).
    readonly property string currentText: currentIndex >= 0 && currentIndex < (model ? model.length : 0) ? model[currentIndex] : ""

    // Alias for text - the string shown in the edit field.
    property alias editText: control.text

    // Whether the user can type freely. When false, only selection from the dropdown is allowed.
    property bool editable: true

    // Filtered and sorted subset of model based on the current text.
    readonly property var filteredItems: {
        const pattern = control.text;
        const items = control.model || [];
        if (!pattern)
            return items.slice().sort();
        const matches = [];
        const others = [];
        for (const item of items) {
            const s = FuzzySearch.score(item, pattern);
            if (s >= 0) {
                matches.push({
                    item,
                    s
                });
            } else if (control._showAll) {
                others.push(item);
            }
        }
        matches.sort((a, b) => b.s - a.s);
        const result = matches.map(x => x.item);
        if (control._showAll) {
            others.sort();
            return result.concat(others);
        }
        return result;
    }

    // Full item list to search through.
    property var model: []
    property string placeholderText: ""

    // The current text value. Initialise from outside; updated by user typing or item selection.
    property string text: ""

    signal accepted(string text)

    // Gives the text field keyboard focus.
    function focusInput() {
        field.forceActiveFocus();
    }

    implicitHeight: field.implicitHeight
    implicitWidth: field.implicitWidth

    // When currentIndex is set programmatically, update text to match.
    onCurrentIndexChanged: {
        if (currentIndex >= 0 && currentIndex < (model ? model.length : 0)) {
            const item = model[currentIndex];
            if (text !== item)
                text = item;
        }
    }
    onFilteredItemsChanged: {
        if (filteredItems.length === 0 && popup.visible)
            popup.close();
    }

    // Sync field text when control.text is changed programmatically.
    onTextChanged: {
        if (field.text !== text)
            field.text = text;
        // Keep currentIndex in sync: find exact match in the original model.
        const items = model || [];
        const idx = items.indexOf(text);
        if (idx !== currentIndex)
            currentIndex = idx;
    }

    TextField {
        id: field

        anchors.fill: parent
        placeholderText: control.placeholderText
        readOnly: !control.editable
        rightPadding: chevron.width + 12
        selectByMouse: true

        Keys.onDownPressed: function (event) {
            if (!control.editable)
                return;
            if (!popup.visible) {
                control._showAll = true;
                if (control.filteredItems.length > 0)
                    popup.open();
            } else {
                const next = listView.currentIndex + 1;
                if (next < listView.count) {
                    listView.currentIndex = next;
                    listView.positionViewAtIndex(next, ListView.Contain);
                }
            }
            event.accepted = true;
        }
        Keys.onEscapePressed: function (event) {
            popup.close();
            event.accepted = true;
        }
        Keys.onPressed: function (event) {
            if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                return;
            if (popup.visible && listView.currentIndex >= 0 && listView.currentIndex < control.filteredItems.length) {
                control.text = control.filteredItems[listView.currentIndex];
                popup.close();
            }
            control.accepted(control.text);
            event.accepted = true;
        }
        Keys.onUpPressed: function (event) {
            if (listView.currentIndex > 0) {
                const prev = listView.currentIndex - 1;
                listView.currentIndex = prev;
                listView.positionViewAtIndex(prev, ListView.Contain);
            }
            event.accepted = true;
        }
        onActiveFocusChanged: {
            if (!activeFocus) {
                popup.close();
                return;
            }
            if (!control.editable)
                return;
            if (!popup.visible && control.filteredItems.length > 0)
                popup.open();
        }
        onTextEdited: {
            if (!control.editable)
                return;
            control._showAll = false;
            control.text = text;
            if (!popup.visible && control.filteredItems.length > 0)
                popup.open();
            listView.currentIndex = -1;
        }

        Text {
            id: chevron

            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: field.palette.text
            font.family: IconFont.name
            opacity: chevronMouseArea.pressed ? 0.7 : (chevronMouseArea.containsMouse ? 1.0 : 0.5)
            text: IconFont.iconChevronDown

            MouseArea {
                id: chevronMouseArea

                anchors.fill: parent
                hoverEnabled: true

                onClicked: {
                    if (!control.editable)
                        return;
                    if (popup.visible) {
                        popup.close();
                    } else {
                        control._showAll = true;
                        field.forceActiveFocus();
                        popup.open();
                    }
                }
            }
        }
    }
    Popup {
        id: popup

        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        focus: false
        margins: 0
        modal: false
        padding: 0
        width: control.width
        x: 0
        y: control.height

        background: Rectangle {
            border.color: control.palette.mid
            border.width: 1
            color: control.palette.base
        }
        contentItem: ListView {
            id: listView

            // Proxy properties: required properties in the delegate cut off outer scope access.
            property Item theControl: control
            property Popup thePopup: popup

            clip: true
            currentIndex: -1
            implicitHeight: Math.min(contentHeight, 300)
            model: control.filteredItems

            ScrollBar.vertical: ScrollBar {
            }
            delegate: ItemDelegate {
                required property int index
                required property string modelData

                // Keep focus in the field, which closes the popup when it loses focus.
                focusPolicy: Qt.NoFocus
                highlighted: ListView.isCurrentItem
                text: modelData
                width: ListView.view.width

                onClicked: {
                    ListView.view.theControl.text = modelData;
                    ListView.view.currentIndex = index;
                    ListView.view.thePopup.close();
                }
            }
        }

        onClosed: control._showAll = false
        onOpened: listView.currentIndex = -1
    }
}
