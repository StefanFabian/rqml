import QtQuick

QtObject {

    /**
     * Finds a child object by its objectName property.
     * Recursively searches visual children, data children, and contentItems.
     */
    function findChild(parent, name) {
        if (!parent) return null;
        if (parent.objectName === name) return parent;

        // Search visual children and contentItem children
        var foundChildren = [];
        try {
            if (parent.children) {
                for (var k = 0; k < parent.children.length; k++)
                    foundChildren.push(parent.children[k]);
            }
            if (parent.contentItem && parent.contentItem.children) {
                for (var l = 0; l < parent.contentItem.children.length; l++) {
                    var c = parent.contentItem.children[l];
                    if (foundChildren.indexOf(c) === -1)
                        foundChildren.push(c);
                }
            }
            // Handle Loader
            if (parent.item && foundChildren.indexOf(parent.item) === -1) {
                foundChildren.push(parent.item);
            }
        } catch (e) {
            // Some objects might throw when accessing properties
        }

        for (var i = 0; i < foundChildren.length; i++) {
            var found = findChild(foundChildren[i], name);
            if (found) return found;
        }

        // Search non-visual data (Popups, Timers, Menus, MouseArea children, etc.)
        var data = parent.data || [];
        for (var j = 0; j < data.length; j++) {
            var dataItem = data[j];
            if (!dataItem) continue;
            if (dataItem.objectName === name) return dataItem;

            // Recurse into Popups/Menus which have contentItems
            if (dataItem.contentItem) {
                var foundInData = findChild(dataItem.contentItem, name);
                if (foundInData) return foundInData;
            }

            // Recurse into the item's own data list (Menu.actions live here,
            // nested Menus inside a MouseArea, etc.).
            try {
                var nested = dataItem.data;
                if (nested && nested.length !== undefined) {
                    for (var m = 0; m < nested.length; m++) {
                        var nestedItem = nested[m];
                        if (!nestedItem) continue;
                        if (nestedItem.objectName === name) return nestedItem;
                        var deep = findChild(nestedItem, name);
                        if (deep) return deep;
                    }
                }
            } catch (e2) {}

            // Menu.actions exposes Action objects as a list - scan them too.
            try {
                var actions = dataItem.actions;
                if (actions && actions.length !== undefined) {
                    for (var a = 0; a < actions.length; a++) {
                        var act = actions[a];
                        if (act && act.objectName === name) return act;
                    }
                }
            } catch (e3) {}
        }

        return null;
    }
}
