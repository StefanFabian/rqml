/*
 * Copyright (C) 2025  Aljoscha Schmidt
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

        property string controller_manager_namespace: ""
        property bool enabled: true
        property var max_samples: undefined
    }
    Utils {
        id: helpers

    }
    Loader {
        id: pluginLoader

        function reload() {
            source = "";
            source = "../qml/ControllerManagerStatistics.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        readonly property string statsTopic: "/mock_cm/statistics/full"
        readonly property string statsType: "pal_statistics_msgs/msg/Statistics"

        // ===========================================================================
        // Init
        // ===========================================================================
        function init() {
            Ros2.reset();
            Ros2.registerService("/mock_cm/list_controllers", "controller_manager_msgs/srv/ListControllers", function (req) {
                return Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListControllers");
            });
            Ros2.registerTopic(statsTopic, statsType);
            contextObj.enabled = true;
            contextObj.controller_manager_namespace = "";
            contextObj.max_samples = undefined;
            pluginLoader.reload();
            tryVerify(function () {
                return pluginLoader.status === Loader.Ready;
            }, 2000, "Plugin should load");
            wait(50);
        }

        // ===========================================================================
        // Helpers
        // ===========================================================================

        //! Find the plugin's subscription and inject a message via injectMessage.
        function injectStats(entries) {
            var sub = find("rsStatisticsSubscription");
            verify(sub !== null, "Statistics subscription should exist");
            sub.injectMessage({
                "statistics": entries
            });
        }

        //! Inject N messages for a single element with given values.
        function injectValues(elementName, values) {
            for (var i = 0; i < values.length; i++) {
                injectStats([
                    {
                        "name": elementName + ".stats/execution_time/current_value",
                        "value": values[i]
                    }
                ]);
            }
        }

        //! Load the plugin with /mock_cm namespace and wait for ready.
        function loadWithNamespace() {
            contextObj.controller_manager_namespace = "/mock_cm";
            pluginLoader.reload();
            tryVerify(function () {
                return pluginLoader.status === Loader.Ready;
            }, 2000, "Plugin should load");
            // Wait for subscription element to be available
            tryVerify(function () {
                return find("rsStatisticsSubscription") !== null;
            }, 2000, "Statistics subscription should be created");
        }

        //! Count currently rendered stats delegates in the ListView content item.
        function renderedStatsDelegateCount() {
            var listView = find("rsStatsListView");
            verify(listView !== null, "Stats ListView should exist");
            var contentItem = listView.contentItem;
            verify(contentItem !== null, "ListView contentItem should exist");
            var count = 0;
            var children = contentItem.children;
            for (var i = 0; i < children.length; i++) {
                var child = children[i];
                if (child && child.objectName === "rsStatsDelegate" && child.visible)
                    count++;
            }
            return count;
        }
        function test_boxplot_statistics() {
            loadWithNamespace();

            // Inject known values: [10, 20, 30, 40, 50]
            injectValues("test_element", [10, 20, 30, 40, 50]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000, "One element expected");
            var entry = listView.model.get(0);
            compare(entry.min, 10, "min should be 10");
            // floor(5 * 0.25) = 1 -> sorted[1] = 20
            compare(entry.q1, 20, "q1 should be 20");
            // floor(5 * 0.5) = 2 -> sorted[2] = 30
            compare(entry.median, 30, "median should be 30");
            // floor(5 * 0.75) = 3 -> sorted[3] = 40
            compare(entry.q3, 40, "q3 should be 40");
            compare(entry.max, 50, "max should be 50");
            compare(entry.count, 5, "count should be 5");
        }
        function test_clear_and_reset() {
            loadWithNamespace();
            injectValues("element_x", [10, 20, 30]);
            injectValues("element_y", [40, 50, 60]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 2, 2000, "Two elements before clear");
            var clearBtn = find("rsClearButton");
            verify(clearBtn !== null, "Clear button should exist");
            mouseClick(clearBtn);
            tryCompare(listView.model, "count", 0, 2000, "Model should be empty after clear");
            var samplesLabel = find("rsSamplesLabel");
            tryCompare(samplesLabel, "text", "Samples: 0", 1000, "Samples counter should reset");
        }
        function test_clear_stale_entries() {
            // Ensure that after clear + new data for fewer elements, no stale
            // trailing entries remain in the model.
            loadWithNamespace();

            // Populate with 3 elements
            injectStats([
                {
                    "name": "a.stats/execution_time/current_value",
                    "value": 10
                },
                {
                    "name": "b.stats/execution_time/current_value",
                    "value": 20
                },
                {
                    "name": "c.stats/execution_time/current_value",
                    "value": 30
                }
            ]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 3, 2000, "Three elements before clear");

            // Clear
            mouseClick(find("rsClearButton"));
            tryCompare(listView.model, "count", 0, 2000);

            // Now send data for only 1 element
            injectValues("only_one", [42]);
            tryCompare(listView.model, "count", 1, 2000, "Exactly one element after clear and partial repopulation");
            compare(listView.model.get(0).label, "only_one", "The single element should be the newly published one");
        }
        function test_clear_when_paused() {
            // Reproduces bug: after pause + clear, stale chart delegates could
            // remain visible.
            loadWithNamespace();

            // Inject limited data (1 message, few elements)
            injectStats([
                {
                    "name": "ctrl_a.stats/execution_time/current_value",
                    "value": 15
                },
                {
                    "name": "ctrl_b.stats/execution_time/current_value",
                    "value": 25
                }
            ]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 2, 2000, "Two elements before pause+clear");

            // Pause
            var pauseToggle = find("rsPauseToggle");
            mouseClick(pauseToggle);
            tryCompare(contextObj, "enabled", false, 1000);

            // Clear
            var clearBtn = find("rsClearButton");
            mouseClick(clearBtn);
            tryCompare(listView.model, "count", 0, 2000, "Model should be empty after clear while paused");

            // Simulate a late message while paused; it should be ignored.
            injectStats([
                {
                    "name": "ctrl_late.stats/execution_time/current_value",
                    "value": 55
                }
            ]);

            // Wait longer than update timer + animation duration and verify stays empty
            wait(1500);
            compare(listView.model.count, 0, "Model should remain empty with no new messages arriving");
            compare(renderedStatsDelegateCount(), 0, "No stats delegates should remain rendered after clear");

            // Also verify the elements label
            var elementsLabel = find("rsElementsLabel");
            compare(elementsLabel.text, "0 elements", "Elements counter should show zero");
        }
        function test_controller_manager_discovery() {
            Ros2.registerService("/another_cm/list_controllers", "controller_manager_msgs/srv/ListControllers", function (req) {
                return Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListControllers");
            });
            var combo = find("rsControllerManagerComboBox");
            verify(combo !== null, "ComboBox should exist");
            var refreshBtn = find("rsRefreshButton");
            verify(refreshBtn !== null, "Refresh button should exist");
            mouseClick(refreshBtn);
            tryVerify(function () {
                var m = combo.model || [];
                return m.indexOf("/mock_cm") !== -1 && m.indexOf("/another_cm") !== -1;
            }, 2000, "Both controller managers should appear");
        }
        function test_empty_state_message() {
            // When messages arrive but none match the execution_time filter,
            // the "No execution time data found" label should be visible.
            loadWithNamespace();

            // Inject a message with NO execution_time entries
            injectStats([
                {
                    "name": "unrelated_stat/something_else",
                    "value": 99
                }
            ]);

            // processMessage increments messageCount even when no data matches
            var listView = find("rsStatsListView");
            wait(1000);
            compare(listView.model.count, 0, "Model should be empty when no entries match filter");

            // totalSamples counts matched entries, not messages
            var samplesLabel = find("rsSamplesLabel");
            compare(samplesLabel.text, "Samples: 0", "totalSamples should be 0 since nothing matched");
        }
        function test_formatting_units_and_scale() {
            // Microsecond range
            loadWithNamespace();
            injectValues("us_elem", [80, 50, 500]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000);
            var scaleMin = find("rsScaleMinLabel");
            var scaleMax = find("rsScaleMaxLabel");
            verify(scaleMin !== null && scaleMax !== null, "Scale labels should exist");

            // All values < 1000, so scale should show µs
            tryVerify(function () {
                return scaleMax.text.indexOf("\u00b5s") !== -1;
            }, 2000, "Scale should use \u00b5s for values < 1000");

            // Sub-1µs value should use 2 decimal places in scale
            tryVerify(function () {
                return scaleMin.text.indexOf("\u00b5s") !== -1;
            }, 2000, "Scale min should also use \u00b5s");

            // Clear and test millisecond range
            mouseClick(find("rsClearButton"));
            tryCompare(listView.model, "count", 0, 2000);
            injectValues("ms_elem", [1500, 2000, 3500]);
            tryCompare(listView.model, "count", 1, 2000);
            tryVerify(function () {
                return scaleMax.text.indexOf("ms") !== -1;
            }, 2000, "Scale should use ms for values >= 1000");
        }
        function test_label_parsing() {
            loadWithNamespace();
            injectStats([
                {
                    "name": "joint_state_broadcaster.stats/execution_time/current_value",
                    "value": 10
                },
                {
                    "name": "arm_interface.stats/read_cycle/execution_time/current_value",
                    "value": 20
                },
                {
                    "name": "arm_interface.stats/write_cycle/execution_time/current_value",
                    "value": 30
                }
            ]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 3, 2000, "Three elements expected");

            // Collect labels from the model
            var labels = [];
            for (var i = 0; i < listView.model.count; i++)
                labels.push(listView.model.get(i).label);
            labels.sort();
            compare(labels[0], "arm_interface (read)", "Read cycle label");
            compare(labels[1], "arm_interface (write)", "Write cycle label");
            compare(labels[2], "joint_state_broadcaster", "Controller label");
        }
        function test_message_processing() {
            loadWithNamespace();
            injectStats([
                {
                    "name": "controller_a.stats/execution_time/current_value",
                    "value": 50.0
                },
                {
                    "name": "controller_b.stats/execution_time/current_value",
                    "value": 100.0
                },
                {
                    "name": "some_other_stat/not_execution_time",
                    "value": 999.0
                }
            ]);
            var listView = find("rsStatsListView");
            verify(listView !== null, "ListView should exist");
            tryCompare(listView.model, "count", 2, 2000, "Only execution_time entries should appear (2 of 3)");
        }
        function test_namespace_change_clears() {
            loadWithNamespace();
            injectValues("element_a", [10, 20, 30]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000, "Should have data before switch");

            // Register a second controller manager
            Ros2.registerService("/other_cm/list_controllers", "controller_manager_msgs/srv/ListControllers", function (req) {
                return Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListControllers");
            });

            // Refresh to pick up the new CM
            mouseClick(find("rsRefreshButton"));

            // Select the other CM via ComboBox
            var combo = find("rsControllerManagerComboBox");
            tryVerify(function () {
                var m = combo.model || [];
                return m.indexOf("/other_cm") !== -1;
            }, 2000, "New CM should appear");

            // Find the index of /other_cm and select it
            var idx = -1;
            for (var i = 0; i < combo.model.length; i++) {
                if (combo.model[i] === "/other_cm") {
                    idx = i;
                    break;
                }
            }
            verify(idx >= 0, "Should find /other_cm index");
            combo.currentIndex = idx;

            // Old data should be cleared
            tryCompare(listView.model, "count", 0, 2000, "Switching namespace should clear old data");
            var samplesLabel = find("rsSamplesLabel");
            compare(samplesLabel.text, "Samples: 0", "Samples counter should reset on namespace change");
        }
        function test_nonfinite_values_filtered() {
            loadWithNamespace();
            injectStats([
                {
                    "name": "ok.stats/execution_time/current_value",
                    "value": 42
                },
                {
                    "name": "nan.stats/execution_time/current_value",
                    "value": NaN
                },
                {
                    "name": "inf.stats/execution_time/current_value",
                    "value": Infinity
                },
                {
                    "name": "neginf.stats/execution_time/current_value",
                    "value": -Infinity
                }
            ]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000, "Only the finite-valued entry should appear");
            compare(listView.model.get(0).label, "ok", "Only the valid entry should be in the model");
        }
        function test_pause_resume() {
            loadWithNamespace();
            injectValues("element_a", [42]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000, "One element after first inject");

            // Pause
            var pauseToggle = find("rsPauseToggle");
            verify(pauseToggle !== null, "Pause toggle should exist");
            mouseClick(pauseToggle);
            tryCompare(contextObj, "enabled", false, 1000, "Should be paused");

            // Verify subscription is disabled (in production, no messages would arrive)
            var sub = find("rsStatisticsSubscription");
            verify(!sub.enabled, "Subscription should be disabled when paused");

            // Data injected while paused should be ignored.
            injectValues("paused_ignored", [999]);
            compare(listView.model.count, 1, "Existing data should be preserved while paused");

            // Resume
            mouseClick(pauseToggle);
            tryCompare(contextObj, "enabled", true, 1000, "Should be resumed");

            // Verify subscription is re-enabled
            verify(sub.enabled, "Subscription should be re-enabled after resume");
            injectValues("element_c", [77]);
            tryCompare(listView.model, "count", 2, 2000, "New element should appear after resume");
        }

        // ===========================================================================
        // Tests
        // ===========================================================================
        function test_plugin_loads() {
            verify(plugin !== null, "ControllerManagerStatistics plugin should load");
        }
        function test_ring_buffer_caps_samples() {
            // processMessage trims via shift() when exceeding max_samples
            loadWithNamespace();

            // Set a small window so we can exceed it easily
            contextObj.max_samples = 100;
            pluginLoader.reload();
            tryVerify(function () {
                return pluginLoader.status === Loader.Ready;
            }, 2000);
            tryVerify(function () {
                return find("rsStatisticsSubscription") !== null;
            }, 2000);

            // Inject 150 values (exceeds max_samples of 100)
            var values = [];
            for (var i = 0; i < 150; i++)
                values.push(i);
            injectValues("capped", values);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000);

            // count should be capped at max_samples, not 150
            var entry = listView.model.get(0);
            compare(entry.count, 100, "Sample count should be capped at max_samples");
            // Oldest values (0-49) were shifted out, so min should be 50
            compare(entry.min, 50, "Oldest samples should have been trimmed");
        }
        function test_sample_window_default() {
            var label = find("rsSampleWindowLabel");
            verify(label !== null, "Sample window label should exist");
            tryVerify(function () {
                return label.text.indexOf("1000") !== -1;
            }, 1000, "Default should be 1000 samples");
        }
        function test_set_max_samples_trims() {
            // setMaxSamples trims existing data when window shrinks
            loadWithNamespace();

            // Inject 500 values
            var values = [];
            for (var i = 0; i < 500; i++)
                values.push(i);
            injectValues("trimmed", values);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000);
            compare(listView.model.get(0).count, 500, "Should have 500 samples");

            // Reduce window to 200 via slider (simulating onMoved)
            var slider = find("rsSampleSizeSlider");
            verify(slider !== null, "Slider should exist");
            slider.value = 200;
            slider.moved();

            // Model should update with trimmed data
            tryVerify(function () {
                return listView.model.get(0).count === 200;
            }, 2000, "Samples should be trimmed to 200");

            // Oldest 300 values removed, so min should now be 300
            compare(listView.model.get(0).min, 300, "Oldest samples should have been trimmed by setMaxSamples");
        }
        function test_single_sample_statistics() {
            loadWithNamespace();
            injectValues("solo", [42]);
            var listView = find("rsStatsListView");
            tryCompare(listView.model, "count", 1, 2000);
            var entry = listView.model.get(0);
            // With 1 sample all percentiles collapse to the same value
            compare(entry.min, 42, "min should equal the single value");
            compare(entry.q1, 42, "q1 should equal the single value");
            compare(entry.median, 42, "median should equal the single value");
            compare(entry.q3, 42, "q3 should equal the single value");
            compare(entry.max, 42, "max should equal the single value");
            compare(entry.count, 1, "count should be 1");
        }

        name: "ControllerManagerStatisticsTest"
        when: windowShown
    }
}
