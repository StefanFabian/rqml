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
import Ros2
import RQml.Elements
import RQml.Fonts
import "interfaces"

Rectangle {
    id: parameterEditor
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(350, 500)
    color: palette.base

    property QtObject d: QtObject {
        id: internalState
        property var acquiredNodes: []
        property var expandedState: ({})
        property int totalNodes: 0
        property int totalParams: 0
        property var treeElements: []
        property var knownNodeStates: ({})

        function buildParameterTree(treeParams) {
            let rootNode = { __children: {}, __param: null };
            let paramCount = 0;
            for (let paramName in treeParams) {
                paramCount++;
                const parts = paramName.split('.');
                let current = rootNode;
                for (let j = 0; j < parts.length - 1; j++) {
                    const p = parts[j];
                    if (!current.__children[p]) current.__children[p] = { __children: {}, __param: null };
                    current = current.__children[p];
                }
                const leaf = parts[parts.length - 1];
                if (!current.__children[leaf]) current.__children[leaf] = { __children: {}, __param: null };
                current.__children[leaf].__param = treeParams[paramName];
            }
            return { rootNode: rootNode, paramCount: paramCount };
        }

        function compressTree(groupName, node) {
            let currentName = groupName;
            let currentNode = node;
            while (true) {
                let childrenKeys = Object.keys(currentNode.__children);
                if (childrenKeys.length === 1 && !currentNode.__param && currentName !== "") {
                    let childKey = childrenKeys[0];
                    if (!currentNode.__children[childKey].__param) {
                        currentName = currentName + "." + childKey;
                        currentNode = currentNode.__children[childKey];
                        continue;
                    }
                }
                break;
            }
            return { compressedName: currentName, compressedNode: currentNode };
        }

        function flattenTree(groupName, node, parentFullPath, depth, nodeName, filterText, showStarredOnly) {
            let compressed = internalState.compressTree(groupName, node);
            let currentName = compressed.compressedName;
            let currentNode = compressed.compressedNode;

            let fullPath = parentFullPath + (parentFullPath === nodeName ? "/" : ".") + currentName;
            if (currentName === "") fullPath = nodeName;

            let childrenObj = currentNode.__children;
            let childrenKeys = Object.keys(childrenObj).sort();

            let hasVisibleChildren = false;
            let hasStarredDescendant = false;
            let items = [];
            let currentParamCount = 0;

            if (currentNode.__param) {
                currentParamCount++;
                let p = currentNode.__param;
                let paramFullPath = fullPath;
                let isStarred = context.quickAccess.indexOf(paramFullPath) !== -1;
                if (isStarred) hasStarredDescendant = true;

                let matchesFilter = filterText === "" || p.name.toLowerCase().indexOf(filterText) !== -1 || nodeName.toLowerCase().indexOf(filterText) !== -1;
                let visible = matchesFilter && (!showStarredOnly || isStarred);

                if (visible) {
                    hasVisibleChildren = true;
                    items.push({
                        rowType: "param",
                        displayName: currentName,
                        fullPath: paramFullPath,
                        depth: depth,
                        expanded: false,
                        starred: isStarred,
                        value: p.value !== null ? p.value : "",
                        paramType: p.type,
                        readOnly: p.descriptor.readOnly,
                        description: p.descriptor.description,
                        integerRange: p.descriptor.integerRange || {},
                        floatingPointRange: p.descriptor.floatingPointRange || {},
                        nodeName: nodeName,
                        paramName: p.name
                    });
                }
            }

            let childItems = [];
            for (let k = 0; k < childrenKeys.length; k++) {
                let childRes = internalState.flattenTree(childrenKeys[k], childrenObj[childrenKeys[k]], fullPath, depth + 1, nodeName, filterText, showStarredOnly);
                currentParamCount += childRes.paramCount;
                if (childRes.hasVisibleChildren) hasVisibleChildren = true;
                if (childRes.hasStarredDescendant) hasStarredDescendant = true;
                if (childRes.items.length > 0) {
                    childItems = childItems.concat(childRes.items);
                }
            }

            let isExpanded = !!internalState.expandedState[fullPath];
            if (filterText !== "" || showStarredOnly) isExpanded = true;

            let groupItem = null;
            if (currentName !== "" && Object.keys(childrenObj).length > 0) {
                let isStarredGroup = context.quickAccess.indexOf(fullPath) !== -1;
                if (isStarredGroup) hasStarredDescendant = true;

                let groupMatches = filterText === "" || fullPath.toLowerCase().indexOf(filterText) !== -1;
                let groupVisible = hasVisibleChildren || (groupMatches && !showStarredOnly);

                if (groupVisible) {
                    hasVisibleChildren = true;
                    groupItem = {
                        rowType: "group",
                        displayName: currentName + (currentParamCount > 0 ? " (" + currentParamCount + ")" : ""),
                        fullPath: fullPath,
                        depth: depth,
                        expanded: isExpanded,
                        starred: isStarredGroup,
                        nodeName: nodeName,
                        paramName: ""
                    };
                }
            }

            let resultItems = [];
            if (groupItem) {
                resultItems.push(groupItem);
                if (isExpanded || filterText !== "" || showStarredOnly) {
                    resultItems = resultItems.concat(items).concat(childItems);
                }
            } else {
                resultItems = resultItems.concat(items).concat(childItems);
            }

            return {
                items: resultItems,
                hasVisibleChildren: hasVisibleChildren,
                hasStarredDescendant: hasStarredDescendant,
                paramCount: currentParamCount
            };
        }

        function rebuildModel() {
            let currentScrollY = treeView.contentY;

            let newModel = [];
            let _totalNodes = 0;
            let _totalParams = 0;
            const nodes = ParameterService.nodes || [];
            const filterText = filterTextField.text.toLowerCase();
            const showStarredOnly = context.showStarredOnly ?? false;

            for (let i = 0; i < nodes.length; i++) {
                const nodeName = nodes[i];
                let isNodeExpanded = !!internalState.expandedState[nodeName];

                const data = ParameterService.getNodeData(nodeName);
                let treeParams = data && data.loaded ? data.parameters : {};

                let treeRes = internalState.buildParameterTree(treeParams);
                let rootNode = treeRes.rootNode;
                let paramCount = treeRes.paramCount;

                if (paramCount > 0) {
                    _totalNodes++;
                    _totalParams += paramCount;
                }

                let childrenKeys = Object.keys(rootNode.__children).sort();
                let nodeChildItems = [];
                let nodeHasVisibleChildren = false;
                let nodeHasStarred = false;

                if (filterText !== "" || showStarredOnly) isNodeExpanded = true;

                for (let k = 0; k < childrenKeys.length; k++) {
                    let childRes = internalState.flattenTree(childrenKeys[k], rootNode.__children[childrenKeys[k]], nodeName, 1, nodeName, filterText, showStarredOnly);
                    if (childRes.hasVisibleChildren) nodeHasVisibleChildren = true;
                    if (childRes.hasStarredDescendant) nodeHasStarred = true;
                    if (childRes.items.length > 0) {
                        nodeChildItems = nodeChildItems.concat(childRes.items);
                    }
                }

                let nodeIsStarred = context.quickAccess.indexOf(nodeName) !== -1;
                if (nodeIsStarred) nodeHasStarred = true;

                let nodeMatches = filterText === "" || nodeName.toLowerCase().indexOf(filterText) !== -1;
                let nodeVisible = (nodeMatches || nodeHasVisibleChildren) && (!showStarredOnly || nodeHasStarred || nodeHasVisibleChildren);

                if (nodeVisible) {
                    let title = nodeName + (data && data.loaded ? " (" + paramCount + ")" : "");

                    newModel.push({
                        rowType: "node",
                        displayName: title,
                        fullPath: nodeName,
                        depth: 0,
                        expanded: isNodeExpanded,
                        starred: nodeIsStarred,
                        nodeName: nodeName,
                        paramName: ""
                    });

                    if (isNodeExpanded && data) {
                        if (data.loaded) {
                            for (let c = 0; c < nodeChildItems.length; c++) {
                                newModel.push(nodeChildItems[c]);
                            }
                        } else if (data.loading) {
                            newModel.push({
                                rowType: "loading",
                                displayName: "Loading...",
                                fullPath: nodeName + "/loading",
                                depth: 1,
                                expanded: false,
                                starred: false,
                                nodeName: nodeName,
                                paramName: ""
                            });
                        }
                    }
                }
            }
            internalState.totalNodes = _totalNodes || nodes.length;
            internalState.totalParams = _totalParams;

            internalState.treeElements = newModel;
            parameterEditor.dChanged();

            // Restore scroll state securely by waiting for the view layout
            Qt.callLater(function() {
                if (currentScrollY > 0 && currentScrollY <= Math.max(0, treeView.contentHeight - treeView.height)) {
                    treeView.contentY = currentScrollY;
                } else if (currentScrollY > 0) {
                     treeView.positionViewAtEnd()
                }
            });
        }
    }

    Component.onCompleted: {
        if (context.quickAccess === undefined)
            context.quickAccess = [];
        if (context.showStarredOnly === undefined)
            context.showStarredOnly = false;
        ParameterService.discoverNodes();
    }

    Component.onDestruction: {
        for (let i = 0; i < parameterEditor.d.acquiredNodes.length; i++) {
            ParameterService.release(parameterEditor.d.acquiredNodes[i]);
        }
        parameterEditor.d.acquiredNodes = [];
    }

    Connections {
        target: ParameterService
        function onParametersChanged(nodeName) {
            let nodeData = ParameterService.getNodeData(nodeName);
            if (!nodeData) {
                parameterEditor.d.rebuildModel();
                return;
            }

            let state = parameterEditor.d.knownNodeStates[nodeName] || { loaded: false, loading: false, paramCount: 0 };

            let loadedChanged = state.loaded !== nodeData.loaded;
            let loadingChanged = state.loading !== nodeData.loading;

            let currentParamCount = Object.keys(nodeData.parameters || {}).length;
            let paramCountChanged = state.paramCount !== currentParamCount;

            if (parameterEditor.d.treeElements) {
                let elems = parameterEditor.d.treeElements;
                for (let i = 0; i < elems.length; i++) {
                    let el = elems[i];
                    if (el.nodeName === nodeName && el.rowType === "param") {
                        if (nodeData.parameters[el.paramName]) {
                            el.value = nodeData.parameters[el.paramName].value;
                        }
                    }
                }
            }

            if (loadedChanged || loadingChanged || paramCountChanged) {
                let st = parameterEditor.d.knownNodeStates;
                st[nodeName] = {
                    loaded: nodeData.loaded,
                    loading: nodeData.loading,
                    paramCount: currentParamCount
                };
                parameterEditor.d.knownNodeStates = st;
                parameterEditor.d.rebuildModel();
            }
        }
        function onNodesChanged() {
            parameterEditor.d.rebuildModel();
        }
        function onParameterSetResult(nodeName, paramName, success, reason) {
            if (!success) {
                Ros2.warn("Failed to set parameter " + paramName + " on node " + nodeName + ": " + reason);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: filterTextField
                Layout.fillWidth: true
                placeholderText: qsTr("Filter parameters...")
                selectByMouse: true
                padding: 8
                onTextChanged: searchDebounceTimer.start()
            }

            IconToggleButton {
                iconOn: IconFont.iconStar
                iconOff: IconFont.iconStar
                tooltipTextOn: qsTr("Show only starred parameters")
                tooltipTextOff: qsTr("Show all parameters")
                checked: context.showStarredOnly ?? false
                Layout.preferredHeight: filterTextField.height
                Layout.preferredWidth: filterTextField.height
                onToggled: {
                    if (checked === context.showStarredOnly) return;
                    context.showStarredOnly = checked;
                    parameterEditor.d.rebuildModel();
                }
            }

            RefreshButton {
                ToolTip.text: qsTr("Discover Nodes")
                ToolTip.visible: hovered
                Layout.preferredHeight: filterTextField.height
                Layout.preferredWidth: filterTextField.height
                onClicked: {
                    animate = true;
                    ParameterService.discoverNodes();
                    animate = false;
                }
            }
        }

        ListView {
            id: treeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                active: true
            }

            property var stateContext: parameterEditor.d

            model: parameterEditor.d.treeElements

            delegate: Rectangle {
                id: rowRect
                required property var modelData
                required property int index

                property var paramValue: modelData.rowType === "param" ? modelData.value : null

                Connections {
                    target: ParameterService
                    function onParametersChanged(nodeName) {
                        if (modelData.rowType === "param" && nodeName === modelData.nodeName) {
                            let nodeData = ParameterService.getNodeData(nodeName);
                            if (nodeData && nodeData.parameters[modelData.paramName]) {
                                rowRect.paramValue = nodeData.parameters[modelData.paramName].value;
                            }
                        }
                    }
                }

                width: treeView.width - (treeView.ScrollBar.vertical.visible ? treeView.ScrollBar.vertical.width : 0)
                height: Math.max(36, rowLayout.implicitHeight + 8)

                color: {
                    if (hoverHandler.hovered) return Qt.darker(palette.alternateBase, 1.1)
                    return index % 2 == 0 ? palette.base : Qt.darker(palette.base, 1.02)
                }

                HoverHandler {
                    id: hoverHandler
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: {
                        if (modelData.rowType === "node" || modelData.rowType === "group") {
                            rowRect.expandCollapseToggle();
                        }
                    }
                }

                function expandCollapseToggle() {
                    const fp = modelData.fullPath;
                    const nodeName = modelData.nodeName;
                    const isNode = modelData.rowType === "node";
                    const isExp = modelData.expanded;

                    let stateCtx = ListView.view.stateContext;

                    if (stateCtx.expandedState[fp]) {
                        delete stateCtx.expandedState[fp];
                    } else {
                        stateCtx.expandedState[fp] = true;
                    }

                    if (!isExp && isNode) {
                        if (stateCtx.acquiredNodes.indexOf(nodeName) === -1) {
                            stateCtx.acquiredNodes.push(nodeName);
                            ParameterService.acquire(nodeName);
                        }
                    }

                    stateCtx.rebuildModel();
                }

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin: 8 + modelData.depth * 24
                    anchors.rightMargin: 8
                    spacing: 8

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                        flat: true
                        text: modelData.expanded ? IconFont.iconChevronDown : IconFont.iconChevronRight
                        visible: modelData.rowType === "node" || modelData.rowType === "group"
                        implicitWidth: visible ? 24 : 0
                        onClicked: rowRect.expandCollapseToggle()
                    }

                    Label {
                        text: modelData.displayName
                        font.bold: modelData.rowType === "node" || modelData.rowType === "group"
                        font.pixelSize: modelData.rowType === "node" ? 14 : 13
                        opacity: modelData.readOnly ? 0.6 : 1.0
                        Layout.fillWidth: modelData.rowType !== "param"
                        Layout.preferredWidth: modelData.rowType === "param" ? 220 : -1
                        elide: Text.ElideRight
                        ToolTip.visible: (hoverHandler.hovered && modelData.description && modelData.description !== "") ? true : false
                        ToolTip.text: modelData.description || ""
                        ToolTip.delay: 500
                    }

                    Loader {
                        id: editorLoader
                        visible: modelData.rowType === "param"
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        sourceComponent: getEditorComponent(modelData.paramType)

                        Binding {
                            target: editorLoader.item
                            property: "modelData"
                            value: modelData
                            restoreMode: Binding.RestoreBinding
                        }
                        Binding {
                            target: editorLoader.item
                            property: "paramValue"
                            value: rowRect.paramValue
                            restoreMode: Binding.RestoreBinding
                        }
                    }

                    IconButton {
                        text: IconFont.iconStar
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        opacity: modelData.starred ? 1.0 : (hoverHandler.hovered ? 0.6 : 0.1)
                        visible: modelData.rowType !== "loading"
                        onClicked: {
                            let qa = context.quickAccess.slice();
                            let idx = qa.indexOf(modelData.fullPath);
                            if (idx !== -1) {
                                qa.splice(idx, 1);
                            } else {
                                qa.push(modelData.fullPath);
                            }
                            context.quickAccess = qa;
                            parameterEditor.d.rebuildModel();
                        }
                    }
                }

                function setParamValue(newValue) {
                    ParameterService.setParameter(modelData.nodeName, modelData.paramName, newValue, modelData.paramType);
                }

                function getEditorComponent(type) {
                    if (type === ParameterService.typeBool) return boolEditor;
                    if (type === ParameterService.typeInteger) return intEditor;
                    if (type === ParameterService.typeDouble) return doubleEditor;
                    if (type === ParameterService.typeString) return stringEditor;
                    if (type >= ParameterService.typeByteArray && type <= ParameterService.typeStringArray) return arrayEditor;
                    return null;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: qsTr("Load All")
                onClicked: {
                    for (let i = 0; i < ParameterService.nodes.length; ++i) {
                        const nodeName = ParameterService.nodes[i];
                        parameterEditor.d.expandedState[nodeName] = true;

                        if (parameterEditor.d.acquiredNodes.indexOf(nodeName) === -1) {
                            parameterEditor.d.acquiredNodes.push(nodeName);
                            ParameterService.acquire(nodeName);
                        }
                    }
                    parameterEditor.d.rebuildModel();
                }
            }

            Label {
                text: parameterEditor.d.totalNodes > 0
                    ? qsTr("%1 parameters across %2 nodes").arg(parameterEditor.d.totalParams).arg(parameterEditor.d.totalNodes)
                    : qsTr("No nodes discovered")
                font.italic: true
                opacity: 0.7
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    Timer {
        id: searchDebounceTimer
        interval: 300
        repeat: false
        onTriggered: {
            parameterEditor.d.rebuildModel();
        }
    }

    Dialog {
        id: arrayEditDialog
        title: qsTr("Edit Array Parameter")
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: Math.min(parent.width * 0.8, 600)
        height: Math.min(parent.height * 0.6, 400)
        anchors.centerIn: parent
        modal: true

        property var paramModel: null

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: arrayEditDialog.paramModel ? arrayEditDialog.paramModel.fullPath : ""
                font.bold: true
                font.family: "Monospace"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    id: arrayTextArea
                    wrapMode: TextEdit.Wrap
                    font.family: "Monospace"
                    selectByMouse: true
                    background: Rectangle {
                        color: palette.base
                        border.color: palette.mid
                    }
                }
            }
        }

        function openDialog(model) {
            paramModel = model;
            arrayTextArea.text = JSON.stringify(model.value, null, 2);
            open();
        }

        onAccepted: {
            if (!paramModel) return;
            try {
                let parsed = JSON.parse(arrayTextArea.text);
                if (!Array.isArray(parsed)) throw new Error("JSON is not an array");
                ParameterService.setParameter(paramModel.nodeName, paramModel.paramName, parsed, paramModel.paramType);
            } catch (e) {
                Ros2.warn("Invalid array JSON: " + e);
            }
        }
    }

    Component {
        id: boolEditor
        CheckBox {
            property var modelData: ({})
            property var paramValue: null
            property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
            onLocalParamValueChanged: if (localParamValue !== undefined) checked = localParamValue

            checked: modelData.value ?? false
            enabled: !(modelData.readOnly ?? false)
            onClicked: {
                ParameterService.setParameter(modelData.nodeName, modelData.paramName, checked, modelData.paramType);
            }
        }
    }

    Component {
        id: intEditor
        RowLayout {
            spacing: 8
            property var modelData: ({})
            property var paramValue: null
            property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
            property var range: modelData.integerRange || {}
            property bool hasRange: range.from !== undefined && range.to !== undefined && range.from < range.to

            onLocalParamValueChanged: {
                intField.value = localParamValue;
                intField.text = Number(localParamValue).toFixed(0);
                if (hasRange) intSlider.value = localParamValue;
            }

            Slider {
                id: intSlider
                visible: parent.hasRange
                from: parent.hasRange ? parent.range.from : 0
                to: parent.hasRange ? parent.range.to : 1
                stepSize: (parent.hasRange && parent.range.step > 0) ? parent.range.step : 1
                value: modelData.value
                enabled: !modelData.readOnly
                Layout.fillWidth: true
                onPressedChanged: {
                    if (!pressed) {
                        ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType);
                    }
                }
                onMoved: {
                    intField.text = Number(value).toFixed(0);
                    intField.value = value;
                }
            }

            IntegerInputField {
                id: intField
                value: modelData.value
                enabled: !modelData.readOnly
                from: parent.hasRange ? parent.range.from : null
                to: parent.hasRange ? parent.range.to : null
                Layout.preferredWidth: parent.hasRange ? 80 : -1
                Layout.fillWidth: !parent.hasRange
                onEditingFinished: {
                    if (parent.hasRange) intSlider.value = value;
                    ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType);
                }
            }
        }
    }

    Component {
        id: doubleEditor
        RowLayout {
            spacing: 8
            property var modelData: ({})
            property var paramValue: null
            property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
            property var range: modelData.floatingPointRange || {}
            property bool hasRange: range.from !== undefined && range.to !== undefined && range.from < range.to

            onLocalParamValueChanged: {
                doubleField.value = localParamValue;
                doubleField.text = localParamValue.toPrecision(doubleField.decimals);
                if (hasRange) doubleSlider.value = localParamValue;
            }

            Slider {
                id: doubleSlider
                visible: parent.hasRange
                from: parent.hasRange ? parent.range.from : 0
                to: parent.hasRange ? parent.range.to : 1
                stepSize: (parent.hasRange && parent.range.step > 0) ? parent.range.step : 0
                value: modelData.value
                enabled: !modelData.readOnly
                Layout.fillWidth: true
                onPressedChanged: {
                    if (!pressed) {
                        ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType);
                    }
                }
                onMoved: {
                    doubleField.text = value.toPrecision(doubleField.decimals);
                    doubleField.value = value;
                }
            }

            DecimalInputField {
                id: doubleField
                value: modelData.value
                enabled: !modelData.readOnly
                from: parent.hasRange ? parent.range.from : null
                to: parent.hasRange ? parent.range.to : null
                Layout.preferredWidth: parent.hasRange ? 80 : -1
                Layout.fillWidth: !parent.hasRange
                onEditingFinished: {
                    if (parent.hasRange) doubleSlider.value = value;
                    ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType);
                }
            }
        }
    }

    Component {
        id: stringEditor
        TextField {
            property var modelData: ({})
            property var paramValue: null
            property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
            objectName: "stringEditor_" + (modelData.paramName ?? "")
            onLocalParamValueChanged: if (localParamValue !== undefined) text = localParamValue

            text: modelData.value ?? ""
            enabled: !(modelData.readOnly ?? false)
            selectByMouse: true
            ToolTip.text: text
            ToolTip.visible: hovered && implicitWidth > width
            onEditingFinished: {
                ParameterService.setParameter(modelData.nodeName, modelData.paramName, text, modelData.paramType);
            }
        }
    }

    Component {
        id: arrayEditor
        RowLayout {
            spacing: 4
            property var modelData: ({})
            property var paramValue: null
            property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
            onLocalParamValueChanged: if (localParamValue !== undefined) arrayValueLabel.text = JSON.stringify(localParamValue)

            TruncatedLabel {
                id: arrayValueLabel
                Layout.fillWidth: true
                text: JSON.stringify(modelData.value)
                color: palette.text
                opacity: 0.8
                font.family: "Monospace"
            }
            IconButton {
                text: IconFont.iconEdit
                enabled: !modelData.readOnly
                onClicked: {
                    arrayEditDialog.openDialog(modelData);
                }
            }
        }
    }
}
