import QtQuick
import QtTest
import "../qml" as Dialogs

Item {
    id: root
    height: 600
    width: 800

    QtObject {
        id: configRqml

        property var configs: [{
                "path": "/tmp/robot/image_raw_monitor.rqml"
            }, {
                "path": "/tmp/robot/controller_manager.rqml"
            }, {
                "path": "/tmp/camera/raw_image_tools.rqml"
            }]
        property string lastLoadedPath: ""
        property var recentConfigs: configs

        function load(path) {
            lastLoadedPath = path;
        }
    }
    QtObject {
        id: pluginRqml

        property string createdPluginId: ""
        property var plugins: [{
                "id": "image_view",
                "name": "Image View",
                "group": "Raw Sensors"
            }, {
                "id": "controller_manager",
                "name": "Controller Manager",
                "group": "Robot Control"
            }, {
                "id": "service_caller",
                "name": "Service Caller",
                "group": "Robot Tools"
            }]

        function canCreatePlugin(id) {
            return id !== "service_caller";
        }
        function createPlugin(id) {
            createdPluginId = id;
            return {
                "instanceId": id
            };
        }
    }
    QtObject {
        id: rootDockingAreaMock

        property var addedInstances: []

        function addDockWidget(instance, location) {
            addedInstances.push({
                    "instance": instance,
                    "location": location
                });
        }
    }
    Component {
        id: openConfigDialogComponent
        Dialogs.OpenConfigDialog {
            property QtObject mainWindow: root

            parent: root
        }
    }
    Component {
        id: openPluginDialogComponent
        Dialogs.OpenPluginDialog {
            property QtObject mainWindow: root
            property var rootDockingArea: rootDockingAreaMock

            parent: root
        }
    }
    TestCase {
        id: testCase

        property var configDialog: null
        property var pluginDialog: null

        function cleanup() {
            TestContextBridge.setContextProperty("RQml", null);
            if (configDialog) {
                configDialog.destroy();
                configDialog = null;
            }
            if (pluginDialog) {
                pluginDialog.destroy();
                pluginDialog = null;
            }
            configRqml.lastLoadedPath = "";
            pluginRqml.createdPluginId = "";
            rootDockingAreaMock.addedInstances = [];
        }
        function createConfigDialog() {
            TestContextBridge.setContextProperty("RQml", configRqml);
            configDialog = openConfigDialogComponent.createObject(root);
            verify(configDialog !== null, "OpenConfigDialog should be created");
            configDialog.open();
            wait(0);
            return configDialog;
        }
        function createPluginDialog() {
            TestContextBridge.setContextProperty("RQml", pluginRqml);
            pluginDialog = openPluginDialogComponent.createObject(root);
            verify(pluginDialog !== null, "OpenPluginDialog should be created");
            pluginDialog.open();
            wait(0);
            return pluginDialog;
        }
        function findChildByObjectName(parent, objectName) {
            if (!parent)
                return null;
            if (parent.objectName === objectName)
                return parent;
            var children = parent.children || [];
            for (var i = 0; i < children.length; ++i) {
                var found = findChildByObjectName(children[i], objectName);
                if (found)
                    return found;
            }
            if (parent.contentItem && parent.contentItem !== parent) {
                var contentFound = findChildByObjectName(parent.contentItem, objectName);
                if (contentFound)
                    return contentFound;
            }
            return null;
        }
        function setFilterText(field, text) {
            field.text = text;
            wait(0);
        }
        function test_openConfigDialogFiltersAcrossTermsAndFields() {
            var dialog = createConfigDialog();
            var filterInput = findChildByObjectName(dialog, "openConfigDialogFilterInput");
            var list = findChildByObjectName(dialog, "openConfigDialogList");
            verify(filterInput !== null);
            verify(list !== null);
            setFilterText(filterInput, "img robot");
            compare(list.model.count, 1);
            compare(list.model.get(0).name, "image_raw_monitor");
        }
        function test_openConfigDialogRanksBestMatchFirstAndEnterLoads() {
            var dialog = createConfigDialog();
            var filterInput = findChildByObjectName(dialog, "openConfigDialogFilterInput");
            var list = findChildByObjectName(dialog, "openConfigDialogList");
            verify(filterInput !== null);
            verify(list !== null);
            setFilterText(filterInput, "raw img");
            verify(list.model.count >= 2);
            compare(list.model.get(0).name, "image_raw_monitor");
            filterInput.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(configRqml.lastLoadedPath, "/tmp/robot/image_raw_monitor.rqml");
        }
        function test_openPluginDialogFiltersAcrossWhitespaceTerms() {
            var dialog = createPluginDialog();
            var filterInput = findChildByObjectName(dialog, "openPluginDialogFilterInput");
            var list = findChildByObjectName(dialog, "openPluginDialogList");
            verify(filterInput !== null);
            verify(list !== null);
            setFilterText(filterInput, "img sens");
            compare(list.model.count, 1);
            compare(list.model.get(0).id, "image_view");
        }
        function test_openPluginDialogKeyboardSelectionUsesFilteredResult() {
            var dialog = createPluginDialog();
            var filterInput = findChildByObjectName(dialog, "openPluginDialogFilterInput");
            var list = findChildByObjectName(dialog, "openPluginDialogList");
            verify(filterInput !== null);
            verify(list !== null);
            setFilterText(filterInput, "ctrl robot");
            compare(list.model.count, 1);
            compare(list.model.get(0).id, "controller_manager");
            filterInput.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(pluginRqml.createdPluginId, "controller_manager");
            compare(rootDockingAreaMock.addedInstances.length, 1);
        }

        name: "FuzzySearchDialogsTest"
        when: windowShown
    }
}
