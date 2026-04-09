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
import "elements"
import "elements/ParameterEditor"
import "ParameterModelLogic.js" as ModelLogic

Rectangle {
    id: parameterEditor
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(350, 500)
    color: palette.base

    property alias saveDialog: saveFileDialog
    property alias loadDialog: loadFileDialog
    property alias d: internalState

    ToastManager {
        id: toastManager
        z: 100
    }

    ArrayEditDialog {
        id: arrayEditDialog
        onParameterSetFailed: function(paramName, reason) {
            toastManager.show(qsTr("Failed to set %1: %2").arg(paramName).arg(reason), "error");
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
        for (let i = 0; i < internalState.acquiredNodes.length; i++) {
            ParameterService.release(internalState.acquiredNodes[i]);
        }
        internalState.acquiredNodes = [];
    }

    Connections {
        target: ParameterService
        function onParametersChanged(nodeName) {
            let nodeData = ParameterService.getNodeData(nodeName);
            if (!nodeData) {
                internalState.rebuildModel();
                return;
            }

            // Keep the model array in sync so rebuildModel produces fresh values.
            if (internalState.treeElements) {
                let elems = internalState.treeElements;
                for (let i = 0; i < elems.length; i++) {
                    let el = elems[i];
                    if (el.nodeName === nodeName && el.rowType === "param") {
                        if (nodeData.parameters[el.paramName]) {
                            el.value = nodeData.parameters[el.paramName].value;
                        }
                    }
                }
            }

            // Bump revision so delegate paramValue bindings re-evaluate.
            internalState.parameterRevision++;

            // Rebuild tree structure when loading state changes (new/removed parameters).
            let prev = internalState.knownNodeStates[nodeName];
            if (!prev || prev.loaded !== nodeData.loaded || prev.loading !== nodeData.loading) {
                let st = internalState.knownNodeStates;
                st[nodeName] = { loaded: nodeData.loaded, loading: nodeData.loading };
                internalState.knownNodeStates = st;
                internalState.rebuildModel();
            }
        }
        function onNodesChanged() {
            internalState.rebuildModel();
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
                objectName: "filterTextField"
                Layout.fillWidth: true
                placeholderText: qsTr("Filter parameters...")
                selectByMouse: true
                padding: 8
                onTextChanged: searchDebounceTimer.start()
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

            IconToggleButton {
                objectName: "starToggleButton"
                iconOn: IconFont.iconStar
                iconOff: IconFont.iconStar
                tooltipTextOn: qsTr("Show only starred parameters")
                tooltipTextOff: qsTr("Show all parameters")
                checked: context.showStarredOnly ?? false
                Layout.preferredHeight: filterTextField.height
                Layout.preferredWidth: filterTextField.height
                onToggled: {
                    if (checked === context.showStarredOnly)
                        return;
                    context.showStarredOnly = checked;
                    internalState.rebuildModel();
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

            function ensureFileHasExtension(path) {
                // Appends .yaml if path has no extension or an unsupported one
                let m = path.match(/\.([^.]+)$/);
                if (!m)
                    return path + ".yaml";
                let ext = m[1].toLowerCase();
                if (!["json", "yaml", "yml"].includes(ext))
                    return path + ".yaml";
                return path;
            }

            onAccepted: {
                let path = saveFileDialog.selectedFile.toString();
                if (path.startsWith("file://"))
                    path = path.slice(7);
                path = ensureFileHasExtension(path);
                internalState.saveGroupParams(activeNode, activePath, path);
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
                if (path.startsWith("file://"))
                    path = path.slice(7);
                internalState.loadGroupParams(activeNode, activePath, path);
            }
        }

        ListView {
            id: treeView
            objectName: "mainTreeView"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                active: true
            }

            property var stateContext: internalState
            model: internalState.treeElements

            delegate: Rectangle {
                id: rowRect
                required property var modelData
                required property int index

                property var paramValue: {
                    // Depend on parameterRevision so this re-evaluates when values change.
                    let rev = internalState.parameterRevision;
                    if (modelData.rowType === "param") {
                        let nd = ParameterService.getNodeData(modelData.nodeName);
                        if (nd && nd.parameters[modelData.paramName])
                            return nd.parameters[modelData.paramName].value;
                    }
                    return modelData.value;
                }

                property bool isSetting: {
                    // Depend on parameterRevision so this re-evaluates when values change.
                    let rev = internalState.parameterRevision;
                    if (modelData.rowType === "param") {
                        return ParameterService.isSetting(modelData.nodeName, modelData.paramName);
                    }
                    return false;
                }

                width: treeView.width - (treeView.ScrollBar.vertical.visible ? treeView.ScrollBar.vertical.width : 0)
                height: Math.max(36, rowLayout.implicitHeight + 8)

                color: {
                    if (hoverHandler.hovered)
                        return Qt.darker(palette.alternateBase, 1.1);
                    return index % 2 == 0 ? palette.base : Qt.darker(palette.base, 1.02);
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
                        objectName: "rowExpandButton_" + modelData.fullPath
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                        flat: true
                        text: modelData.expanded ? IconFont.iconChevronDown : IconFont.iconChevronRight
                        visible: modelData.rowType === "node" || modelData.rowType === "group"
                        Layout.preferredWidth: visible ? 24 : 0
                        Layout.preferredHeight: visible ? 24 : 0
                        padding: 0
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
                        source: getEditorSource(modelData.paramType)
                        enabled: !rowRect.isSetting && !modelData.readOnly

                        BusyIndicator {
                            objectName: "busyIndicator_" + (modelData.paramName ?? "")
                            anchors.centerIn: parent
                            height: parent.height - 4
                            width: height
                            visible: rowRect.isSetting
                            running: visible
                        }

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

                        Connections {
                            target: editorLoader.item
                            ignoreUnknownSignals: true
                            function onParameterSetFailed(paramName, reason) {
                                toastManager.show(qsTr("Failed to set %1: %2").arg(paramName).arg(reason), "error");
                            }
                            function onEditRequested(model, arrValue) {
                                arrayEditDialog.openDialog(model, arrValue);
                            }
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
                        objectName: "saveParamsButton_" + (modelData.fullPath || modelData.nodeName || "")
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
                        objectName: "loadParamsButton_" + (modelData.fullPath || modelData.nodeName || "")
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
                        objectName: "rowStarButton_" + modelData.fullPath
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
                            internalState.rebuildModel();
                        }
                    }
                }

                function getEditorSource(type) {
                    if (type === ParameterService.typeBool)
                        return "elements/ParameterEditor/BoolParameterEditor.qml";
                    if (type === ParameterService.typeInteger || type === ParameterService.typeDouble)
                        return "elements/ParameterEditor/NumericParameterEditor.qml";
                    if (type === ParameterService.typeString)
                        return "elements/ParameterEditor/StringParameterEditor.qml";
                    if (type >= ParameterService.typeByteArray && type <= ParameterService.typeStringArray)
                        return "elements/ParameterEditor/ArrayParameterEditor.qml";
                    return "";
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                objectName: "loadAllButton"
                text: qsTr("Load All")
                onClicked: {
                    for (let i = 0; i < ParameterService.nodes.length; ++i) {
                        const nodeName = ParameterService.nodes[i];
                        internalState.expandedState[nodeName] = true;

                        if (internalState.acquiredNodes.indexOf(nodeName) === -1) {
                            internalState.acquiredNodes.push(nodeName);
                            ParameterService.acquire(nodeName);
                        }
                    }
                    internalState.rebuildModel();
                }
            }

            Label {
                text: internalState.totalNodes > 0 ? qsTr("%1 parameters across %2 nodes").arg(internalState.totalParams).arg(internalState.totalNodes) : qsTr("No nodes discovered")
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
            internalState.rebuildModel();
        }
    }

    QtObject {
        id: internalState
        property var acquiredNodes: []
        property var expandedState: ({})
        property int totalNodes: 0
        property int totalParams: 0
        property var treeElements: []
        property var knownNodeStates: ({})
        property int parameterRevision: 0

        function saveGroupParams(nodeName, fullPath, filePath) {
            let data = ParameterService.getNodeData(nodeName);
            if (!data || !data.loaded)
                return;
            let groupParams = {};

            let relativePath = ModelLogic.getRelativePath(nodeName, fullPath);

            let prefix = relativePath ? relativePath + "." : "";

            for (let paramName in data.parameters) {
                if (relativePath && !paramName.startsWith(prefix))
                    continue; // Skip parameters not in the current group

                let key = relativePath ? paramName.substring(prefix.length) : paramName;

                let p = data.parameters[paramName];
                let val = p.value;

                // Force casting to JS primitives because QVariants might be ignored by JSON.stringify
                if (p.type === ParameterService.typeBool)
                    val = !!val;
                else if (p.type === ParameterService.typeInteger)
                    val = Number(val);
                else if (p.type === ParameterService.typeDouble)
                    val = Number(val);
                else if (p.type === ParameterService.typeString)
                    val = String(val);
                else if (p.type >= ParameterService.typeByteArray) {
                    val = MessageUtils.toJavaScriptObject(val);
                    if (!Array.isArray(val)) {
                        val = [val];
                    }
                }

                // Create nested ROS 2 standard format
                let parts = key.split(".");
                let current = groupParams;
                for (let j = 0; j < parts.length - 1; j++) {
                    if (!current[parts[j]])
                        current[parts[j]] = {};
                    current = current[parts[j]];
                }
                current[parts[parts.length - 1]] = val;
            }

            if (filePath.endsWith(".json")) {
                let success = RQml.writeFile(filePath, JSON.stringify(groupParams, null, 2));
                if (!success)
                    toastManager.show(qsTr("Failed to save JSON to %1").arg(filePath), "error");
            } else if (filePath.endsWith(".yaml") || filePath.endsWith(".yml")) {
                let success = Ros2.io.writeYaml(filePath, groupParams);
                if (!success)
                    toastManager.show(qsTr("Failed to save YAML to %1").arg(filePath), "error");
            }
        }

        function loadGroupParams(nodeName, fullPath, filePath) {
            let groupParams = null;
            if (filePath.endsWith(".json")) {
                let text = RQml.readFile(filePath);
                if (text) {
                    try {
                        groupParams = JSON.parse(text);
                    } catch (e) {
                        toastManager.show(qsTr("Failed to parse JSON: %1").arg(e.message), "error");
                    }
                }
            } else if (filePath.endsWith(".yaml") || filePath.endsWith(".yml")) {
                let result = Ros2.io.readYaml(filePath);
                if (result && typeof result === "object") {
                    groupParams = result;
                }
            }
            if (!groupParams) {
                toastManager.show(qsTr("Failed to load parameters from %1").arg(filePath), "error");
                return;
            }

            // Flatten the loaded parameters
            let flatParams = {};
            function flatten(obj, prefix) {
                let keyList = [];
                for (let key in obj)
                    keyList.push(key);

                for (let i = 0; i < keyList.length; i++) {
                    let key = keyList[i];
                    if (obj[key] !== null && typeof obj[key] === "object" && !Array.isArray(obj[key])) {
                        flatten(obj[key], prefix + key + ".");
                    } else {
                        flatParams[prefix + key] = obj[key];
                    }
                }
            }
            flatten(groupParams, "");

            let data = ParameterService.getNodeData(nodeName);
            if (!data || !data.loaded)
                return;

            let relativePath = ModelLogic.getRelativePath(nodeName, fullPath);

            let targetPrefix = relativePath ? relativePath + "." : "";

            for (let incomingKey in flatParams) {
                let valToSet = flatParams[incomingKey];

                // Find the matching parameter
                let matchedName = null;
                let paramName = targetPrefix + incomingKey;
                if (data.parameters[paramName]) {
                    matchedName = paramName;
                } else if (data.parameters[incomingKey]) {
                    matchedName = incomingKey;
                } else {
                    // Check if there is ros__parameters root namespace, standard for ros2 param dump
                    let nakedKey = incomingKey.replace(/^.+?\.ros__parameters\./, "");
                    if (data.parameters[nakedKey]) {
                        matchedName = nakedKey;
                    } else if (data.parameters[targetPrefix + nakedKey]) {
                        matchedName = targetPrefix + nakedKey;
                    }
                }

                if (matchedName && !data.parameters[matchedName].descriptor.readOnly) {
                    ParameterService.setParameter(nodeName, matchedName, valToSet, data.parameters[matchedName].type, function(success, reason) {
                        if (!success) {
                            toastManager.show(qsTr("Failed to load %1: %2").arg(matchedName).arg(reason), "error");
                        }
                    });
                }
            }
        }

        function rebuildModel() {
            let currentScrollY = treeView.contentY;

            let newModel = [];
            let _totalNodes = 0;
            let _totalParams = 0;
            const nodes = ParameterService.nodes || [];
            const filterText = filterTextField.text.toLowerCase();
            const showStarredOnly = context.showStarredOnly ?? false;

            const stateContext = {
                filterText: filterText,
                showStarredOnly: showStarredOnly,
                quickAccess: context.quickAccess || [],
                expandedState: internalState.expandedState
            };

            for (let i = 0; i < nodes.length; i++) {
                const nodeName = nodes[i];
                let isNodeExpanded = !!internalState.expandedState[nodeName];

                const data = ParameterService.getNodeData(nodeName);
                let treeParams = data && data.loaded ? data.parameters : {};

                let treeRes = ModelLogic.buildParameterTree(treeParams);
                let rootNode = treeRes.rootNode;
                let paramCount = treeRes.paramCount;

                if (paramCount > 0) {
                    _totalNodes++;
                    _totalParams += paramCount;
                }

                let childrenKeys = [];
                for (let childKey in rootNode.__children)
                    childrenKeys.push(childKey);
                childrenKeys.sort();

                let nodeChildItems = [];
                let nodeHasVisibleChildren = false;
                let nodeHasStarred = false;

                if (filterText !== "" || showStarredOnly)
                    isNodeExpanded = true;

                let nodeIsStarred = context.quickAccess.indexOf(nodeName) !== -1;
                if (nodeIsStarred)
                    nodeHasStarred = true;

                for (let keyIndex = 0; keyIndex < childrenKeys.length; keyIndex++) {
                    let childRes = ModelLogic.flattenTree(childrenKeys[keyIndex], rootNode.__children[childrenKeys[keyIndex]], nodeName, 1, nodeName, nodeIsStarred, stateContext);
                    if (childRes.hasVisibleChildren)
                        nodeHasVisibleChildren = true;
                    if (childRes.hasStarredDescendant)
                        nodeHasStarred = true;
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
            treeView.model = newModel;

            // Restore scroll state securely by waiting for the view layout
            Qt.callLater(function () {
                if (currentScrollY > 0 && currentScrollY <= Math.max(0, treeView.contentHeight - treeView.height)) {
                    treeView.contentY = currentScrollY;
                } else if (currentScrollY > 0) {
                    treeView.positionViewAtEnd();
                }
            });
        }
    }
}
