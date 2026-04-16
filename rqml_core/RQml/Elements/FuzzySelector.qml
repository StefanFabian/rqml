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

    signal accepted(string text)

    implicitHeight: field.implicitHeight
    implicitWidth: field.implicitWidth

    // The current text value. Initialise from outside; updated by user typing or item selection.
    property string text: ""

    property string placeholderText: ""

    // Full item list to search through.
    property var model: []

    // Index of the selected item in the original (unfiltered) model. -1 if none.
    property int currentIndex: -1

    // Text of the currently selected item (read-only).
    readonly property string currentText: currentIndex >= 0 && currentIndex < (model ? model.length : 0) ? model[currentIndex] : ""

    // Whether the user can type freely. When false, only selection from the dropdown is allowed.
    property bool editable: true

    // Alias for text - the string shown in the edit field.
    property alias editText: control.text


    // Internal state to show all items (browse mode) instead of just filtered ones.
    property bool _showAll: false

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

    // When currentIndex is set programmatically, update text to match.
    onCurrentIndexChanged: {
        if (currentIndex >= 0 && currentIndex < (model ? model.length : 0)) {
            const item = model[currentIndex];
            if (text !== item)
                text = item;
        }
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

    onFilteredItemsChanged: {
        if (filteredItems.length === 0 && popup.visible)
            popup.close();
    }

    TextField {
        id: field
        anchors.fill: parent
        placeholderText: control.placeholderText
        selectByMouse: true
        readOnly: !control.editable
        rightPadding: chevron.width + 12

        onActiveFocusChanged: {
            if (!control.editable) return
            if (activeFocus && !popup.visible && control.filteredItems.length > 0)
                popup.open();
        }

        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            font.family: IconFont.name
            text: IconFont.iconChevronDown
            color: field.palette.text
            opacity: chevronMouseArea.pressed ? 0.7 : (chevronMouseArea.containsMouse ? 1.0 : 0.5)

            MouseArea {
                id: chevronMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (!control.editable) return
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

        onTextEdited: {
            if (!control.editable)
                return;
            control._showAll = false;
            control.text = text;
            if (!popup.visible && control.filteredItems.length > 0)
                popup.open();
            listView.currentIndex = -1;
        }

        Keys.onDownPressed: function (event) {
            if (!control.editable) return
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

        Keys.onUpPressed: function (event) {
            if (listView.currentIndex > 0) {
                const prev = listView.currentIndex - 1;
                listView.currentIndex = prev;
                listView.positionViewAtIndex(prev, ListView.Contain);
            }
            event.accepted = true;
        }

        Keys.onReturnPressed: function (event) {
            if (popup.visible && listView.currentIndex >= 0 && listView.currentIndex < control.filteredItems.length) {
                control.text = control.filteredItems[listView.currentIndex];
                popup.close();
            }
            control.accepted(control.text);
            event.accepted = true;
        }

        Keys.onEscapePressed: function (event) {
            popup.close();
            event.accepted = true;
        }
    }

    Popup {
        id: popup
        x: 0
        y: control.height
        width: control.width
        padding: 0
        margins: 0
        modal: false
        focus: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onOpened: listView.currentIndex = -1
        onClosed: control._showAll = false

        contentItem: ListView {
            id: listView
            implicitHeight: Math.min(contentHeight, 300)
            model: control.filteredItems
            clip: true
            currentIndex: -1
            // Proxy properties: required properties in the delegate cut off outer scope access.
            property Item theControl: control
            property Popup thePopup: popup
            property Item theField: field

            ScrollBar.vertical: ScrollBar {}

            delegate: ItemDelegate {
                required property string modelData
                required property int index
                width: ListView.view.width
                text: modelData
                highlighted: ListView.isCurrentItem

                onClicked: {
                    ListView.view.theControl.text = modelData;
                    ListView.view.currentIndex = index;
                    ListView.view.thePopup.close();
                    ListView.view.theField.forceActiveFocus();
                }
            }
        }

        background: Rectangle {
            color: control.palette.base
            border.color: control.palette.mid
            border.width: 1
        }
    }
}
