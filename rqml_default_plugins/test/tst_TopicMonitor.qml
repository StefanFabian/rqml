import QtQuick
import QtTest
import Ros2

Item {
    id: root

    property var context: contextObj
    property var plugin: pluginLoader.item

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 768
    width: 1024

    QtObject {
        id: contextObj

        property var monitoredTopics: []
    }
    Utils {
        id: helpers
    }
    Loader {
        id: pluginLoader
        function reload() {
            source = "";
            source = "../qml/TopicMonitor.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        function init() {
            Ros2.reset();
            Ros2.registerTopic("/test_topic", "std_msgs/msg/String");
            contextObj.monitoredTopics = [];
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000, "Loader should be ready");
            wait(100);
        }
        function test_add_and_remove_topic() {
            var topicSelector = find("topicMonitorTopicSelector");
            var addButton = find("topicMonitorAddButton");
            var listView = find("topicMonitorListView");
            verify(topicSelector !== null);
            verify(addButton !== null);
            verify(listView !== null);
            topicSelector.text = "/test_topic";
            tryVerify(function () {
                    return addButton.enabled;
                }, 1000, "Add button should enable for a known topic");
            mouseClick(addButton);
            tryCompare(listView, "count", 1, 2000, "Should have one monitored topic");
            compare(contextObj.monitoredTopics.length, 1, "Context should persist monitored topics");
            compare(contextObj.monitoredTopics[0].topic, "/test_topic");
            compare(contextObj.monitoredTopics[0].type, "std_msgs/msg/String");
            var deleteButton = null;
            tryVerify(function () {
                    deleteButton = find("topicMonitorDeleteButton_0");
                    return deleteButton !== null;
                }, 2000, "Delete button should exist");
            mouseClick(deleteButton);
            tryCompare(listView, "count", 0, 2000, "Topic should be removed");
            compare(contextObj.monitoredTopics.length, 0, "Context should be updated after removal");
        }
        function test_enter_adds_topic() {
            var topicSelector = find("topicMonitorTopicSelector");
            var listView = find("topicMonitorListView");
            verify(topicSelector !== null);
            verify(listView !== null);
            topicSelector.text = "/test_topic";
            tryCompare(topicSelector, "currentIndex", 0, 1000, "Topic should be selected");
            mouseClick(topicSelector);
            keyClick(Qt.Key_Return);
            tryCompare(listView, "count", 1, 2000, "Pressing enter should add the topic");
            compare(contextObj.monitoredTopics.length, 1);
        }
        function test_pause_and_view_latest_message() {
            var topicSelector = find("topicMonitorTopicSelector");
            var addButton = find("topicMonitorAddButton");
            topicSelector.text = "/test_topic";
            tryVerify(function () {
                    return addButton.enabled;
                }, 1000);
            mouseClick(addButton);
            var sub = null;
            tryVerify(function () {
                    sub = Ros2.findSubscription("/test_topic");
                    return sub !== null;
                }, 2000, "Subscription should be created");
            var msg = Ros2.createEmptyMessage("std_msgs/msg/String");
            msg.data = "hello monitor";
            sub.injectMessage(msg);
            sub.frequency = 8.5;
            sub.bandwidth = 2048;
            var frequencyLabel = null;
            var bandwidthLabel = null;
            tryVerify(function () {
                    frequencyLabel = find("topicMonitorFrequencyLabel_0");
                    bandwidthLabel = find("topicMonitorBandwidthLabel_0");
                    return frequencyLabel !== null && bandwidthLabel !== null;
                }, 2000);
            tryCompare(frequencyLabel, "text", "8.5 Hz", 2500);
            tryCompare(bandwidthLabel, "text", "2.0 KiB/s", 2500);
            var pauseButton = find("topicMonitorPauseButton_0");
            verify(pauseButton !== null, "Pause button should exist");
            mouseClick(pauseButton);
            tryCompare(contextObj.monitoredTopics[0], "paused", true, 2000, "Paused state should persist");
            compare(sub.enabled, false, "Subscription should be disabled when paused");
            sub.frequency = 0;
            sub.bandwidth = 0;
            wait(1200);
            compare(frequencyLabel.text, "8.5 Hz", "Paused rows should keep the last displayed frequency");
            compare(bandwidthLabel.text, "2.0 KiB/s", "Paused rows should keep the last displayed bandwidth");
            var viewButton = find("topicMonitorViewButton_0");
            verify(viewButton !== null, "View button should exist");
            mouseClick(viewButton);
            var dialog = null;
            var jsonTextArea = null;
            tryVerify(function () {
                    dialog = find("topicMonitorMessageDialog");
                    return dialog !== null && dialog.visible;
                }, 3000, "Latest-message dialog should be visible");
            tryVerify(function () {
                    return dialog.message && dialog.message.data === "hello monitor";
                }, 2000, "Readonly dialog should show the latest message");
            var jsonTabButton = find("editMessageDialogJsonTabButton");
            verify(jsonTabButton !== null, "JSON tab button should exist");
            mouseClick(jsonTabButton);
            tryVerify(function () {
                    jsonTextArea = find("editMessageDialogJsonTextArea");
                    return jsonTextArea !== null && jsonTextArea.text.indexOf("\"data\": \"hello monitor\"") !== -1;
                }, 3000, "JSON view should show the latest message");
            var copyJsonButton = find("editMessageDialogCopyJsonButton");
            verify(copyJsonButton !== null);
            RQml.resetClipboard();
            mouseClick(copyJsonButton);
            compare(RQml.clipboard, jsonTextArea.text, "Copy JSON button should copy the readonly JSON");
        }
        function test_plugin_loads() {
            verify(plugin !== null, "TopicMonitor plugin should load");
        }
        function test_restored_topic_syncs_live_type() {
            contextObj.monitoredTopics = [{
                    "topic": "/test_topic",
                    "type": "std_msgs/msg/Bool",
                    "paused": false
                }];
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000, "Loader should be ready after restoring a topic");
            var listView = find("topicMonitorListView");
            verify(listView !== null);
            tryCompare(listView, "count", 1, 2000, "Restored topic should be shown");
            var sub = null;
            tryVerify(function () {
                    sub = Ros2.findSubscription("/test_topic");
                    return sub !== null;
                }, 2000, "Subscription should be created for restored topic");
            tryCompare(sub, "messageType", "std_msgs/msg/String", 2000, "Subscription should resolve the live topic type");
            tryCompare(contextObj.monitoredTopics[0], "type", "std_msgs/msg/String", 2000, "Persisted entry should self-heal to the live topic type");
            var typeLabel = null;
            tryVerify(function () {
                    typeLabel = find("topicMonitorTypeLabel_0");
                    return typeLabel !== null;
                }, 2000, "Type label should exist");
            tryCompare(typeLabel, "text", "std_msgs/msg/String", 2000, "Visible row type should update to the live topic type");
            var msg = Ros2.createEmptyMessage("std_msgs/msg/String");
            msg.data = "restored message";
            sub.injectMessage(msg);
            var viewButton = find("topicMonitorViewButton_0");
            verify(viewButton !== null, "View button should exist for restored topic");
            mouseClick(viewButton);
            var dialog = null;
            tryVerify(function () {
                    dialog = find("topicMonitorMessageDialog");
                    return dialog !== null && dialog.visible;
                }, 3000, "Latest-message dialog should be visible for restored topic");
            compare(dialog.messageType, "std_msgs/msg/String", "Dialog should use the live resolved topic type");
            tryVerify(function () {
                    return dialog.message && dialog.message.data === "restored message";
                }, 2000, "Dialog should show the restored topic's latest message");
        }

        name: "TopicMonitorTest"
        when: windowShown
    }
}
