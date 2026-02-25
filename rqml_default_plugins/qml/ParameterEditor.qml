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
import QtQuick.Dialogs
import Ros2
import RQml.Elements
import RQml.Fonts
import RQml.Utils
import "interfaces"

Rectangle {
    id: parameterEditor
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(350, 500)
    color: palette.base

    property alias saveDialog: saveFileDialog
    property alias loadDialog: loadFileDialog

    property QtObject d: QtObject {
        id: internalState
        property var acquiredNodes: []
        property var expandedState: ({})
        property int totalNodes: 0
        property int totalParams: 0
        property var treeElements: []
        property var knownNodeStates: ({})

        function saveGroupParams(nodeName, fullPath, filePath) {
            let data = ParameterService.getNodeData(nodeName);
            if (!data || !data.loaded) return;
            let groupParams = {};

            let relativePath = fullPath || "";
            if (relativePath.startsWith(nodeName + "/")) {
                relativePath = relativePath.substring(nodeName.length + 1);
            } else if (relativePath === nodeName) {
                relativePath = "";
            }

            let prefix = relativePath ? relativePath + "." : "";

            for (let paramName in data.parameters) {
                if (!relativePath || paramName.startsWith(prefix)) {
                    let key = relativePath ? paramName.substring(prefix.length) : paramName;

                    let p = data.parameters[paramName];
                    let val = p.value;

                    // Force casting to JS primitives because QVariants might be ignored by JSON.stringify
                    if (p.type === ParameterService.typeBool) val = !!val;
                    else if (p.type === ParameterService.typeInteger) val = Number(val);
                    else if (p.type === ParameterService.typeDouble) val = Number(val);
                    else if (p.type === ParameterService.typeString) val = String(val);
                    else if (p.type >= ParameterService.typeByteArray) {
                        val = MessageUtils.toJavaScriptObject(val);
                        if (!Array.isArray(val)) {
                            // Fallback if not an array for some reason
                            val = [val];
                        }
                    }

                    // Create nested ROS 2 standard format
                    let parts = key.split(".");
                    let current = groupParams;
                    for (let j = 0; j < parts.length - 1; j++) {
                        if (!current[parts[j]]) current[parts[j]] = {};
                        current = current[parts[j]];
                    }
                    current[parts[parts.length - 1]] = val;
                }
            }

            if (filePath.endsWith(".json")) {
                let success = RQml.writeFile(filePath, JSON.stringify(groupParams, null, 2));
                if (!success) console.warn("Failed to save JSON to", filePath);
            } else if (filePath.endsWith(".yaml") || filePath.endsWith(".yml")) {
                let success = Ros2.io.writeYaml(filePath, groupParams);
                if (!success) console.warn("Failed to save YAML to", filePath);
            }
        }

        function loadGroupParams(nodeName, fullPath, filePath) {
            let groupParams = null;
            if (filePath.endsWith(".json")) {
                let text = RQml.readFile(filePath);
                if (text) {
                    try { groupParams = JSON.parse(text); } catch (e) { console.warn("Failed to parse JSON", e); }
                }
            } else if (filePath.endsWith(".yaml") || filePath.endsWith(".yml")) {
                let result = Ros2.io.readYaml(filePath);
                if (result && typeof result === "object") {
                    groupParams = result;
                }
            }
            if (!groupParams) {
                console.warn("Failed to load parameters from", filePath);
                return;
            }

            // Flatten the loaded parameters
            let flatParams = {};
            function flatten(obj, pfx) {
                let kList = [];
                for (let k in obj) kList.push(k);

                for (let i = 0; i < kList.length; i++) {
                    let k = kList[i];
                    if (obj[k] !== null && typeof obj[k] === "object" && !Array.isArray(obj[k])) {
                        flatten(obj[k], pfx + k + ".");
                    } else {
                        flatParams[pfx + k] = obj[k];
                    }
                }
            }
            flatten(groupParams, "");

            let data = ParameterService.getNodeData(nodeName);
            if (!data || !data.loaded) return;

            let relativePath = fullPath || "";
            if (relativePath.startsWith(nodeName + "/")) {
                relativePath = relativePath.substring(nodeName.length + 1);
            } else if (relativePath === nodeName) {
                relativePath = "";
            }

            let targetPrefix = relativePath ? relativePath + "." : "";

            for (let incomingKey in flatParams) {
                let valToSet = flatParams[incomingKey];

                // If it's a specific group context
                let paramName = targetPrefix + incomingKey;
                if (data.parameters[paramName]) {
                     ParameterService.setParameter(nodeName, paramName, valToSet, data.parameters[paramName].type);
                } else if (data.parameters[incomingKey]) {
                     ParameterService.setParameter(nodeName, incomingKey, valToSet, data.parameters[incomingKey].type);
                } else {
                     // Check if there is ros__parameters root namespace, standard for ros2 param dump
                     let nakedKey = incomingKey.replace(/^.+?\.ros__parameters\./, "");
                     if (data.parameters[nakedKey]) {
                         ParameterService.setParameter(nodeName, nakedKey, valToSet, data.parameters[nakedKey].type);
                     } else if (data.parameters[targetPrefix + nakedKey]) {
                         ParameterService.setParameter(nodeName, targetPrefix + nakedKey, valToSet, data.parameters[targetPrefix + nakedKey].type);
                     }
                }
            }
        }

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
                let childrenKeys = [];
                for (let k in currentNode.__children) childrenKeys.push(k);

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

        function flattenTree(groupName, node, parentFullPath, depth, nodeName, filterText, showStarredOnly, parentIsStarred) {
            let compressed = internalState.compressTree(groupName, node);
            let currentName = compressed.compressedName;
            let currentNode = compressed.compressedNode;

            let fullPath = parentFullPath + (parentFullPath === nodeName ? "/" : ".") + currentName;
            if (currentName === "") fullPath = nodeName;

            let childrenObj = currentNode.__children;
            let childrenKeys = [];
            for (let k in childrenObj) childrenKeys.push(k);
            childrenKeys.sort();

            let hasVisibleChildren = false;
            let hasStarredDescendant = false;
            let items = [];
            let currentParamCount = 0;

            let isGroupStarred = context.quickAccess.indexOf(fullPath) !== -1;
            let effectivelyStarred = parentIsStarred || isGroupStarred;

            if (currentNode.__param) {
                currentParamCount++;
                let p = currentNode.__param;
                let paramFullPath = fullPath;
                let isStarred = context.quickAccess.indexOf(paramFullPath) !== -1;
                if (isStarred || effectivelyStarred) hasStarredDescendant = true;

                let matchesFilter = filterText === "" || p.name.toLowerCase().indexOf(filterText) !== -1 || nodeName.toLowerCase().indexOf(filterText) !== -1;
                let visible = matchesFilter && (!showStarredOnly || isStarred || effectivelyStarred);

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
                let childRes = internalState.flattenTree(childrenKeys[k], childrenObj[childrenKeys[k]], fullPath, depth + 1, nodeName, filterText, showStarredOnly, effectivelyStarred);
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
            let childrenCount = 0;
            for (let c in childrenObj) childrenCount++;

            if (currentName !== "" && childrenCount > 0) {
                if (isGroupStarred || effectivelyStarred) hasStarredDescendant = true;

                let groupMatches = filterText === "" || fullPath.toLowerCase().indexOf(filterText) !== -1;
                let groupVisible = hasVisibleChildren || (groupMatches && (!showStarredOnly || effectivelyStarred));

                if (groupVisible) {
                    hasVisibleChildren = true;
                    groupItem = {
                        rowType: "group",
                        displayName: currentName + (currentParamCount > 0 ? " (" + currentParamCount + ")" : ""),
                        fullPath: fullPath,
                        depth: depth,
                        expanded: isExpanded,
                        starred: isGroupStarred,
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

                let childrenKeys = [];
                for (let k in rootNode.__children) childrenKeys.push(k);
                childrenKeys.sort();

                let nodeChildItems = [];
                let nodeHasVisibleChildren = false;
                let nodeHasStarred = false;

                if (filterText !== "" || showStarredOnly) isNodeExpanded = true;

                let nodeIsStarred = context.quickAccess.indexOf(nodeName) !== -1;
                if (nodeIsStarred) nodeHasStarred = true;

                for (let k = 0; k < childrenKeys.length; k++) {
                    let childRes = internalState.flattenTree(childrenKeys[k], rootNode.__children[childrenKeys[k]], nodeName, 1, nodeName, filterText, showStarredOnly, nodeIsStarred);
                    if (childRes.hasVisibleChildren) nodeHasVisibleChildren = true;
                    if (childRes.hasStarredDescendant) nodeHasStarred = true;
                    if (childRes.items.length > 0) {
                        nodeChildItems = nodeChildItems.concat(childRes.items);
                    }
                }

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

            let currentParamCount = 0;
            if (nodeData.parameters) {
                for (let k in nodeData.parameters) currentParamCount++;
            }
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
        FileDialog {
            id: saveFileDialog
            objectName: "saveFileDialog"
            title: qsTr("Save Parameters")
            fileMode: FileDialog.SaveFile
            nameFilters: ["JSON/YAML Files (*.json *.yaml *.yml)", "All Files (*)"]
            property string activeNode: ""
            property string activePath: ""
            onAccepted: {
                let path = saveFileDialog.selectedFile.toString();
                if (path.startsWith("file://")) path = path.slice(7);
                parameterEditor.d.saveGroupParams(activeNode, activePath, path);
            }
        }

        FileDialog {
            id: loadFileDialog
            objectName: "loadFileDialog"
            title: qsTr("Load Parameters")
            fileMode: FileDialog.OpenFile
            nameFilters: ["JSON/YAML Files (*.json *.yaml *.yml)", "All Files (*)"]
            property string activeNode: ""
            property string activePath: ""
            onAccepted: {
                let path = loadFileDialog.selectedFile.toString();
                if (path.startsWith("file://")) path = path.slice(7);
                parameterEditor.d.loadGroupParams(activeNode, activePath, path);
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
                        objectName: "reloadButton_" + (modelData.nodeName || "")
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        flat: true
                        text: IconFont.iconRefresh
                        visible: modelData.rowType === "node"
                        tooltipText: qsTr("Reload parameters...")
                        onClicked: {
                            ParameterService.refresh(modelData.nodeName);
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        flat: true
                        text: IconFont.iconSave
                        visible: modelData.rowType === "node" || modelData.rowType === "group"
                        tooltipText: qsTr("Save parameters...")
                        onClicked: {
                            saveFileDialog.activeNode = modelData.nodeName;
                            saveFileDialog.activePath = modelData.rowType === "group" ? modelData.fullPath : "";
                            saveFileDialog.open();
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        flat: true
                        text: IconFont.iconLoad
                        visible: modelData.rowType === "node" || modelData.rowType === "group"
                        tooltipText: qsTr("Load parameters...")
                        onClicked: {
                            loadFileDialog.activeNode = modelData.nodeName;
                            loadFileDialog.activePath = modelData.rowType === "group" ? modelData.fullPath : "";
                            loadFileDialog.open();
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        flat: true
                        text: IconFont.iconStar
                        visible: modelData.rowType !== "loading"
                        opacity: modelData.starred ? 1.0 : (hovered ? 0.7 : 0.2)
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
        height: Math.min(parent.height * 0.8, 500)
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

            Label {
                text: qsTr("Items: %1").arg(arrayListModel.count)
            }

            ListModel {
                id: arrayListModel
            }

            ListView {
                id: arrayListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: arrayListModel

                ScrollBar.vertical: ScrollBar { active: true }

                delegate: RowLayout {
                    width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)

                    Label {
                        text: "[" + index + "]"
                        font.family: "Monospace"
                        Layout.preferredWidth: 50
                    }

                    TextField {
                        Layout.fillWidth: true
                        text: model.value !== undefined ? String(model.value) : ""
                        selectByMouse: true
                        onEditingFinished: {
                            let pType = arrayEditDialog.paramModel.paramType;
                            let parsed = text;
                            if (pType === ParameterService.typeIntegerArray) parsed = parseInt(text, 10) || 0;
                            else if (pType === ParameterService.typeDoubleArray) parsed = parseFloat(text) || 0.0;
                            else if (pType === ParameterService.typeBoolArray) parsed = (text.toLowerCase() === "true" || text === "1");

                            arrayListModel.setProperty(index, "value", parsed);
                        }
                    }

                    IconButton {
                        text: IconFont.iconTrash
                        tooltipText: qsTr("Remove Item")
                        onClicked: {
                            arrayListModel.remove(index);
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: qsTr("Add Item")
                    onClicked: {
                        arrayListModel.append({ "value": "" });
                        arrayListView.positionViewAtEnd();
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Clear All")
                    onClicked: {
                        arrayListModel.clear();
                    }
                }
            }
        }

        function openDialog(model, arrValue) {
            paramModel = model;
            let tempArray = [];

            let sourceVal = arrValue !== undefined ? arrValue : model.value;
            let jsObj = MessageUtils.toJavaScriptObject(sourceVal);

            if (Array.isArray(jsObj)) {
                tempArray = jsObj;
            } else if (jsObj !== null && jsObj !== undefined) {
                tempArray = [jsObj]; // Fallback
            }

            arrayListModel.clear();
            for (let i = 0; i < tempArray.length; i++) {
                arrayListModel.append({ "value": tempArray[i] });
            }

            open();
        }

        onAccepted: {
            if (!paramModel) return;
            let pType = paramModel.paramType;
            let finalArray = [];
            for (let i = 0; i < arrayListModel.count; i++) {
                let v = arrayListModel.get(i).value;
                if (pType === ParameterService.typeIntegerArray) finalArray.push(parseInt(v, 10) || 0);
                else if (pType === ParameterService.typeDoubleArray) finalArray.push(parseFloat(v) || 0.0);
                else if (pType === ParameterService.typeBoolArray) finalArray.push(v === "true" || v === true || v === "1");
                else finalArray.push(String(v));
            }

            ParameterService.setParameter(paramModel.nodeName, paramModel.paramName, finalArray, paramModel.paramType);
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
            property bool hasFrom: range.from !== undefined && range.from !== null && !isNaN(range.from)
            property bool hasTo: range.to !== undefined && range.to !== null && !isNaN(range.to)
            property bool hasRange: hasFrom && hasTo && range.from < range.to

            onLocalParamValueChanged: {
                if (localParamValue !== undefined && localParamValue !== null) {
                    intField.value = localParamValue;
                    intField.text = Number(localParamValue).toFixed(0);
                    if (hasRange) intSlider.value = localParamValue;
                }
            }

            Label {
                objectName: "minLabel_" + (modelData.paramName ?? "")
                text: parent.hasRange ? parent.range.from : (parent.hasFrom ? qsTr("Min: ") + parent.range.from : "")
                visible: parent.hasRange || parent.hasFrom
                Layout.alignment: Qt.AlignVCenter
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

            Label {
                objectName: "maxLabel_" + (modelData.paramName ?? "")
                text: parent.hasRange ? parent.range.to : (parent.hasTo ? qsTr("Max: ") + parent.range.to : "")
                visible: parent.hasRange || parent.hasTo
                Layout.alignment: Qt.AlignVCenter
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
            property bool hasFrom: range.from !== undefined && range.from !== null && !isNaN(range.from)
            property bool hasTo: range.to !== undefined && range.to !== null && !isNaN(range.to)
            property bool hasRange: hasFrom && hasTo && range.from < range.to

            onLocalParamValueChanged: {
                if (localParamValue !== undefined && localParamValue !== null) {
                    doubleField.value = localParamValue;
                    doubleField.text = Number(localParamValue).toPrecision(doubleField.decimals ?? 2);
                    if (hasRange) doubleSlider.value = localParamValue;
                }
            }

            Label {
                objectName: "minLabel_" + (modelData.paramName ?? "")
                text: parent.hasRange ? parent.range.from : (parent.hasFrom ? qsTr("Min: ") + parent.range.from : "")
                visible: parent.hasRange || parent.hasFrom
                Layout.alignment: Qt.AlignVCenter
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

            Label {
                objectName: "maxLabel_" + (modelData.paramName ?? "")
                text: parent.hasRange ? parent.range.to : (parent.hasTo ? qsTr("Max: ") + parent.range.to : "")
                visible: parent.hasRange || parent.hasTo
                Layout.alignment: Qt.AlignVCenter
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

            function formatArray(val) {
                if (val === null || val === undefined) return "[]";

                let jsObj = MessageUtils.toJavaScriptObject(val);
                if (!Array.isArray(jsObj)) {
                    return JSON.stringify(jsObj);
                }

                let len = jsObj.length;
                if (len === 0) return "[]";

                let preview = [];
                let maxPreview = Math.min(len, 10);
                for (let i = 0; i < maxPreview; i++) {
                    preview.push(JSON.stringify(jsObj[i]));
                }

                if (len > 10) {
                    return "[" + preview.join(", ") + ", ... (" + len + " items)]";
                }
                return "[" + preview.join(", ") + "]";
            }

            onLocalParamValueChanged: {
                if (localParamValue !== undefined && localParamValue !== null) {
                    arrayValueLabel.text = formatArray(localParamValue);
                }
            }

            TruncatedLabel {
                id: arrayValueLabel
                Layout.fillWidth: true
                text: formatArray(localParamValue)
                color: palette.text
                opacity: 0.8
                font.family: "Monospace"
            }
            IconButton {
                text: IconFont.iconEdit
                enabled: !modelData.readOnly
                onClicked: {
                    arrayEditDialog.openDialog(modelData, localParamValue);
                }
            }
        }
    }
}
