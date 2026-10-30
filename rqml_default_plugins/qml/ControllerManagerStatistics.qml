/*
 * ControllerManagerStatistics.qml - Controller Manager Execution Time Monitor
 *
 * This plugin visualizes execution time statistics for controllers and hardware
 * interfaces managed by a ROS 2 controller manager. It subscribes to the
 * statistics/full topic and displays boxplots showing the distribution of
 * execution times.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Material
import Ros2
import RQml.Elements
import RQml.Fonts
import "elements"

Rectangle {
    id: root

    readonly property int _defaultMaxSamples: 1000
    readonly property string _executionTimeFilter: "/execution_time/current_value"
    readonly property string _statisticsTopicSuffix: "/statistics/full"
    readonly property int _updateIntervalMs: 500

    //--------------------------------------------------------------------------
    // Constants
    //--------------------------------------------------------------------------
    readonly property var kddockwidgets_min_size: Qt.size(500, 400)

    anchors.fill: parent
    color: palette.base

    //--------------------------------------------------------------------------
    // Initialization
    //--------------------------------------------------------------------------
    Component.onCompleted: {
        if (context.enabled === undefined)
            context.enabled = true;
        if (context.max_samples !== undefined)
            d.maxSamples = context.max_samples;
        d.refresh();
    }

    //--------------------------------------------------------------------------
    // Main Layout
    //--------------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // Controller Manager selection
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Controller Manager"
            }
            ComboBox {
                id: controllerManagerComboBox

                Layout.fillWidth: true
                model: d.controllerManagers
                objectName: "rsControllerManagerComboBox"

                onCurrentValueChanged: {
                    if (!currentValue || currentValue === context.controller_manager_namespace)
                        return;
                    context.controller_manager_namespace = currentValue;
                    d.clear();
                }
            }
            RefreshButton {
                objectName: "rsRefreshButton"

                onClicked: {
                    animate = true;
                    d.refresh();
                    animate = false;
                }
            }
        }

        // Status row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                objectName: "rsSamplesLabel"
                text: "Samples: " + d.totalSamples
            }
            Rectangle {
                color: palette.mid
                height: 16
                opacity: 0.5
                width: 1
            }
            Label {
                objectName: "rsElementsLabel"
                text: d.elementsModel.count + " elements"
            }
            Item {
                Layout.fillWidth: true
            }
            IconToggleButton {
                checked: context.enabled ?? true
                iconOff: IconFont.iconPlay
                iconOn: IconFont.iconPause
                objectName: "rsPauseToggle"
                tooltipTextOff: "Click to resume"
                tooltipTextOn: "Click to pause"

                onToggled: context.enabled = checked
            }
            IconButton {
                objectName: "rsClearButton"
                text: IconFont.iconTrash
                tooltipText: "Clear data"

                onClicked: d.clear()
            }
        }

        // Waiting indicator
        Hint {
            Layout.fillWidth: true
            objectName: "rsWaitingLabel"
            text: "Waiting for statistics topic: " + (context.controller_manager_namespace || "") + _statisticsTopicSuffix
            visible: !d.topicAvailable && !!context.controller_manager_namespace && d.messageCount === 0
        }

        // Scale indicator
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: d.elementsModel.count > 0

            Caption {
                objectName: "rsScaleMinLabel"
                text: d.formatTime(d.globalMin)
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 8
                color: palette.text
                height: 1
                opacity: 0.3
            }
            Caption {
                text: "Scale"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 8
                color: palette.text
                height: 1
                opacity: 0.3
            }
            Caption {
                objectName: "rsScaleMaxLabel"
                text: d.formatTime(d.globalMax)
            }
        }

        // Statistics list
        ListView {
            id: statsListView

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            model: d.elementsModel
            objectName: "rsStatsListView"
            spacing: 2

            ScrollBar.vertical: ScrollBar {
                policy: statsListView.contentHeight > statsListView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }
            add: Transition {
            }
            delegate: Rectangle {
                id: delegateRoot

                required property int index
                required property var model

                color: index % 2 === 0 ? palette.base : palette.alternateBase
                height: 76
                radius: 4
                width: statsListView.width - (statsListView.ScrollBar.vertical.visible ? statsListView.ScrollBar.vertical.width : 0)

                // Subtle border
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    border.color: palette.mid
                    border.width: 1
                    color: "transparent"
                    opacity: 0.3
                    radius: 3
                }
                ColumnLayout {
                    anchors.bottomMargin: 6
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.topMargin: 6
                    spacing: 4

                    // Header: label and sample count
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Title {
                            Layout.fillWidth: true
                            text: model.label
                        }
                        Caption {
                            text: "n=" + model.count
                        }
                    }

                    // Boxplot visualization with statistics labels
                    BoxPlotItem {
                        Layout.fillWidth: true
                        displayMax: d.globalMax
                        displayMin: d.globalMin
                        formatValue: d.formatTime
                        maxValue: model.max
                        medianValue: model.median
                        minValue: model.min
                        q1Value: model.q1
                        q3Value: model.q3
                    }
                }
            }
        }

        // Empty state message
        Label {
            Layout.fillHeight: true
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "No execution time data found in statistics messages."
            verticalAlignment: Text.AlignVCenter
            visible: d.elementsModel.count === 0 && d.messageCount > 0
        }

        // Sample window slider (at bottom)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Window:"
            }
            Slider {
                id: sampleSizeSlider

                Layout.fillWidth: true
                from: 100
                objectName: "rsSampleSizeSlider"
                stepSize: 100
                to: 10000
                value: context.max_samples ?? _defaultMaxSamples

                onMoved: {
                    context.max_samples = value;
                    d.setMaxSamples(value);
                }
            }
            Label {
                Layout.preferredWidth: 100
                objectName: "rsSampleWindowLabel"
                text: d.maxSamples + " samples"
            }
        }
    }

    //--------------------------------------------------------------------------
    // ROS 2 Subscription
    //--------------------------------------------------------------------------
    Subscription {
        id: statisticsSubscription

        enabled: !!(context.enabled ?? true) && topic !== ""
        messageType: "pal_statistics_msgs/msg/Statistics"
        objectName: "rsStatisticsSubscription"
        topic: context.controller_manager_namespace ? context.controller_manager_namespace + _statisticsTopicSuffix : ""

        onNewMessage: msg => d.processMessage(msg)
    }

    //--------------------------------------------------------------------------
    // Timers
    //--------------------------------------------------------------------------

    // Check if topic is available (only when waiting for first message)
    Timer {
        interval: 2000
        repeat: true
        running: !!context.controller_manager_namespace && d.messageCount === 0

        onTriggered: {
            const topic = context.controller_manager_namespace + _statisticsTopicSuffix;
            const topics = Ros2.queryTopics();
            d.topicAvailable = topics.indexOf(topic) !== -1;
        }
    }

    // Debounced UI update timer
    Timer {
        id: updateTimer

        interval: _updateIntervalMs
        repeat: false

        onTriggered: d.updateModel()
    }

    //--------------------------------------------------------------------------
    // Private Implementation
    //--------------------------------------------------------------------------
    QtObject {
        id: d

        // State
        property var controllerManagers: []
        property var elementData: ({})      // Map: label -> number[] (samples)
        property var elementOrder: []       // Sorted list of labels

        // UI model
        property var elementsModel: ListModel {
        }
        property real globalMax: 100
        property real globalMin: 0
        property int maxSamples: _defaultMaxSamples
        property int messageCount: 0
        property bool topicAvailable: false
        property int totalSamples: 0

        /**
         * Parses a statistics name and builds a display label.
         * Examples:
         *   "joint_state_broadcaster.stats/execution_time/current_value" -> "joint_state_broadcaster"
         *   "arm_interface.stats/read_cycle/execution_time/current_value" -> "arm_interface (read)"
         */
        function buildLabel(fullName) {
            let element = fullName;
            let cycleKind = null;

            // Extract element name (before ".stats")
            const statsIndex = fullName.indexOf(".stats");
            if (statsIndex !== -1) {
                element = fullName.substring(0, statsIndex);
            } else {
                // Fallback: take first segment
                const slashIndex = fullName.indexOf("/");
                const dotIndex = fullName.indexOf(".");
                if (dotIndex !== -1 && (slashIndex === -1 || dotIndex < slashIndex)) {
                    element = fullName.substring(0, dotIndex);
                } else if (slashIndex !== -1) {
                    element = fullName.substring(0, slashIndex);
                }
            }

            // Detect read/write cycle for hardware interfaces
            if (fullName.indexOf("/read_cycle/") !== -1)
                cycleKind = "read";
            else if (fullName.indexOf("/write_cycle/") !== -1)
                cycleKind = "write";
            return cycleKind ? element + " (" + cycleKind + ")" : element;
        }

        /**
         * Calculates boxplot statistics for an array of samples.
         * Returns null if samples array is empty.
         */
        function calculateStats(samples) {
            if (!samples || samples.length === 0)
                return null;

            // Sort for percentile calculation
            const sorted = samples.slice().sort((a, b) => a - b);
            const n = sorted.length;
            return {
                "min": sorted[0],
                "q1": sorted[Math.floor(n * 0.25)],
                "median": sorted[Math.floor(n * 0.5)],
                "q3": sorted[Math.floor(n * 0.75)],
                "max": sorted[n - 1],
                "count": n
            };
        }

        /**
         * Clears all collected data and resets state.
         */
        function clear() {
            updateTimer.stop();
            elementData = {};
            elementOrder = [];
            messageCount = 0;
            totalSamples = 0;
            globalMin = 0;
            globalMax = 100;
            elementsModel.clear();
        }

        /**
         * Formats a time value in microseconds to a human-readable string
         * with appropriate unit (us or ms).
         */
        function formatTime(us) {
            if (us == 0)
                return 0;
            if (us >= 1000)
                return (us / 1000).toFixed(2) + " ms";
            if (us >= 1)
                return us.toFixed(1) + " \u00b5s";
            return us.toFixed(2) + " \u00b5s";
        }

        /**
         * Processes incoming statistics message and accumulates samples.
         */
        function processMessage(msg) {
            if (!msg || !(context.enabled ?? true))
                return;
            const statistics = msg.statistics;
            if (!statistics || statistics.length === undefined)
                return;
            let hasNewData = false;
            const len = statistics.length;
            for (let i = 0; i < len; i++) {
                // Use .at() accessor for qml6_ros2_plugin arrays
                const stat = statistics.at(i);
                if (!stat)
                    continue;
                const name = stat.name;
                const value = stat.value;

                // Validate fields
                if (name === undefined || name === null)
                    continue;
                if (value === undefined || value === null || !isFinite(value))
                    continue;

                // Filter for execution_time/current_value entries only
                if (String(name).indexOf(_executionTimeFilter) === -1)
                    continue;

                // Parse and build label
                const label = buildLabel(name);

                // Initialize or get existing samples array
                let samples = elementData[label];
                if (!samples) {
                    samples = [];
                    elementData[label] = samples;
                }
                samples.push(value);

                // Enforce sample limit (ring buffer behavior)
                if (samples.length > maxSamples)
                    samples.shift();
                hasNewData = true;
                totalSamples++;
            }
            messageCount++;
            topicAvailable = true;
            if (hasNewData)
                triggerUpdate();
        }

        /**
         * Rebuilds the entire model from scratch.
         */
        function rebuildModel(statsMap) {
            elementsModel.clear();
            for (let i = 0; i < elementOrder.length; i++) {
                const label = elementOrder[i];
                const stats = statsMap[label];
                if (!stats)
                    continue;
                elementsModel.append({
                    "label": label,
                    "min": stats.min,
                    "q1": stats.q1,
                    "median": stats.median,
                    "q3": stats.q3,
                    "max": stats.max,
                    "count": stats.count
                });
            }
        }

        /**
         * Discovers available controller managers by querying ListControllers services.
         */
        function refresh() {
            const prevControllerManager = context.controller_manager_namespace;
            const services = Ros2.queryServices("controller_manager_msgs/srv/ListControllers");
            let managers = prevControllerManager ? [prevControllerManager] : [];
            for (let i = 0; i < services.length; i++) {
                const parts = services[i].split("/");
                parts.pop(); // Remove service name to get namespace
                const ns = parts.join("/");
                if (ns && managers.indexOf(ns) === -1)
                    managers.push(ns);
            }
            managers.sort();
            controllerManagers = managers;

            // Restore selection
            if (prevControllerManager) {
                const index = managers.indexOf(prevControllerManager);
                controllerManagerComboBox.currentIndex = Math.max(0, index);
            }
        }

        /**
         * Updates max samples and trims existing data if needed.
         */
        function setMaxSamples(newMax) {
            maxSamples = newMax;

            // Trim existing samples if they exceed new limit
            const labels = Object.keys(elementData);
            let trimmedCount = 0;
            for (let i = 0; i < labels.length; i++) {
                const samples = elementData[labels[i]];
                if (samples && samples.length > newMax) {
                    const excess = samples.length - newMax;
                    samples.splice(0, excess);
                    trimmedCount += excess;
                }
            }
            if (trimmedCount > 0) {
                totalSamples = Math.max(0, totalSamples - trimmedCount);
                triggerUpdate();
            }
        }

        /**
         * Schedules a debounced UI update.
         */
        function triggerUpdate() {
            if (!updateTimer.running)
                updateTimer.start();
        }

        /**
         * Updates the UI model with current statistics.
         * Uses in-place updates when possible to avoid flickering.
         */
        function updateModel() {
            const labels = Object.keys(elementData);
            if (labels.length === 0)
                return;

            // Calculate stats for all elements
            const statsMap = {};
            let newMin = Infinity;
            let newMax = -Infinity;
            for (let i = 0; i < labels.length; i++) {
                const label = labels[i];
                const samples = elementData[label];
                const stats = calculateStats(samples);
                if (!stats)
                    continue;
                statsMap[label] = stats;
                newMin = Math.min(newMin, stats.min);
                newMax = Math.max(newMax, stats.max);
            }

            // Update global range with padding and a minimum span to keep
            // boxplots visible even when all samples are equal.
            const statsCount = Object.keys(statsMap).length;
            if (statsCount > 0) {
                const range = newMax - newMin;
                const center = (newMin + newMax) / 2;
                const halfRange = range > 0 ? (range * 0.55) : Math.max(Math.abs(center) * 0.05, 0.5);
                globalMin = Math.max(0, center - halfRange);
                globalMax = center + halfRange;
                if (globalMax < 100)
                    globalMax = Math.ceil(globalMax / 5) * 5;
                else if (globalMax < 1000)
                    globalMax = Math.ceil(globalMax / 20) * 20;
                else if (globalMax < 10000)
                    globalMax = Math.ceil(globalMax / 100) * 100;
                else if (globalMax < 100000)
                    globalMax = Math.ceil(globalMax / 1000) * 1000;
                else if (globalMax < 1000000)
                    globalMax = Math.ceil(globalMax / 10000) * 10000;
            }

            // Re-sort alphabetically only when element count changes
            const currentLabels = Object.keys(statsMap);
            if (currentLabels.length !== elementOrder.length) {
                currentLabels.sort((a, b) => a.localeCompare(b));
                elementOrder = currentLabels;
            }

            // Update model (in-place when possible)
            for (let i = 0; i < elementOrder.length; i++) {
                const label = elementOrder[i];
                const stats = statsMap[label];
                if (!stats)
                    continue;
                const entry = {
                    "label": label,
                    "min": stats.min,
                    "q1": stats.q1,
                    "median": stats.median,
                    "q3": stats.q3,
                    "max": stats.max,
                    "count": stats.count
                };
                if (i < elementsModel.count) {
                    const existing = elementsModel.get(i);
                    if (existing.label === label) {
                        elementsModel.set(i, entry);
                    } else {
                        // Order mismatch - rebuild entire model
                        rebuildModel(statsMap);
                        return;
                    }
                } else {
                    elementsModel.append(entry);
                }
            }

            // Remove stale trailing entries when elements have disappeared
            while (elementsModel.count > elementOrder.length)
                elementsModel.remove(elementsModel.count - 1);
        }
    }
}
