.pragma library

function getRelativePath(nodeName, fullPath) {
    let relativePath = fullPath || "";
    if (relativePath.startsWith(nodeName + "/")) {
        relativePath = relativePath.substring(nodeName.length + 1);
    } else if (relativePath === nodeName) {
        relativePath = "";
    }
    return relativePath;
}

function buildParameterTree(treeParams) {
    let rootNode = {
        __children: {},
        __param: null
    };
    let paramCount = 0;
    for (let paramName in treeParams) {
        paramCount++;
        const parts = paramName.split('.');
        let current = rootNode;
        for (let j = 0; j < parts.length - 1; j++) {
            const pathPart = parts[j];
            if (!current.__children[pathPart])
                current.__children[pathPart] = {
                    __children: {},
                    __param: null
                };
            current = current.__children[pathPart];
        }
        const leaf = parts[parts.length - 1];
        if (!current.__children[leaf])
            current.__children[leaf] = {
                __children: {},
                __param: null
            };
        current.__children[leaf].__param = treeParams[paramName];
    }
    return {
        rootNode: rootNode,
        paramCount: paramCount
    };
}

function compressTree(groupName, node) {
    let currentName = groupName;
    let currentNode = node;
    while (true) {
        let childrenKeys = [];
        for (let childKey in currentNode.__children)
            childrenKeys.push(childKey);

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
    return {
        compressedName: currentName,
        compressedNode: currentNode
    };
}

function flattenTree(groupName, node, parentFullPath, depth, nodeName, parentIsStarred, state) {
    let filterText = state.filterText;
    let showStarredOnly = state.showStarredOnly;

    let compressed = compressTree(groupName, node);
    let currentName = compressed.compressedName;
    let currentNode = compressed.compressedNode;

    let fullPath = parentFullPath + (parentFullPath === nodeName ? "/" : ".") + currentName;
    if (currentName === "")
        fullPath = nodeName;

    let childrenObj = currentNode.__children;
    let childrenKeys = [];
    for (let childKey in childrenObj)
        childrenKeys.push(childKey);
    childrenKeys.sort();

    let hasVisibleChildren = false;
    let hasStarredDescendant = false;
    let items = [];
    let currentParamCount = 0;

    let isGroupStarred = state.quickAccess.indexOf(fullPath) !== -1;
    let effectivelyStarred = parentIsStarred || isGroupStarred;

    if (currentNode.__param) {
        currentParamCount++;
        let param = currentNode.__param;
        let paramFullPath = fullPath;
        let isStarred = state.quickAccess.indexOf(paramFullPath) !== -1;
        if (isStarred || effectivelyStarred)
            hasStarredDescendant = true;

        let matchesFilter = filterText === "" || param.name.toLowerCase().indexOf(filterText) !== -1 || nodeName.toLowerCase().indexOf(filterText) !== -1;
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
                value: param.value !== null ? param.value : "",
                paramType: param.type,
                readOnly: param.descriptor.readOnly,
                description: param.descriptor.description,
                integerRange: (function (r) {
                    if (Array.isArray(r) && r.length > 0) return { from: r[0].from_value, to: r[0].to_value, step: r[0].step };
                    if (r && r.from_value !== undefined) return { from: r.from_value, to: r.to_value, step: r.step };
                    return r || {};
                })(param.descriptor.integerRange),
                floatingPointRange: (function (r) {
                    if (Array.isArray(r) && r.length > 0) return { from: r[0].from_value, to: r[0].to_value, step: r[0].step };
                    if (r && r.from_value !== undefined) return { from: r.from_value, to: r.to_value, step: r.step };
                    return r || {};
                })(param.descriptor.floatingPointRange),
                nodeName: nodeName,
                paramName: param.name
            });
        }
    }

    let childItems = [];
    for (let keyIndex = 0; keyIndex < childrenKeys.length; keyIndex++) {
        let childRes = flattenTree(childrenKeys[keyIndex], childrenObj[childrenKeys[keyIndex]], fullPath, depth + 1, nodeName, effectivelyStarred, state);
        currentParamCount += childRes.paramCount;
        if (childRes.hasVisibleChildren)
            hasVisibleChildren = true;
        if (childRes.hasStarredDescendant)
            hasStarredDescendant = true;
        if (childRes.items.length > 0) {
            childItems = childItems.concat(childRes.items);
        }
    }

    let isExpanded = !!state.expandedState[fullPath];
    if (filterText !== "" || showStarredOnly)
        isExpanded = true;

    let groupItem = null;
    let childrenCount = 0;
    for (let childKey in childrenObj)
        childrenCount++;

    if (currentName !== "" && childrenCount > 0) {
        if (isGroupStarred || effectivelyStarred)
            hasStarredDescendant = true;

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
