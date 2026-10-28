import QtQuick
import QtTest
import QtQuick.Controls.Material
import RQml.Elements

Item {
    height: 400
    width: 400

    StateIndicator {
        id: indicator
        state: "active"
    }
    TestCase {
        function init() {
            indicator.state = "unknown";
        }
        function test_activeState() {
            indicator.state = "active";
            compare(indicator.color, Material.color(Material.Green), "Active state should be green");
        }
        function test_errorProcessingState() {
            indicator.state = "errorprocessing";
            compare(indicator.color, Material.color(Material.Red), "Error processing state should be red");
        }
        function test_finalizedState() {
            indicator.state = "finalized";
            compare(indicator.color, Material.color(Material.Grey, Material.Shade700), "Finalized state should be dark grey");
        }
        function test_inactiveState() {
            indicator.state = "inactive";
            compare(indicator.color, Material.color(Material.Blue), "Inactive state should be blue");
        }
        function test_transientStates() {
            for (const state of ["configuring", "cleaningup", "shuttingdown", "activating", "deactivating"]) {
                indicator.state = state;
                compare(indicator.color, Material.color(Material.Amber), state + " should be amber");
            }
        }
        function test_unconfiguredState() {
            indicator.state = "unconfigured";
            compare(indicator.color, Material.color(Material.Orange), "Unconfigured state should be orange");
        }
        function test_unknownState() {
            indicator.state = "unknown";
            compare(indicator.color, Material.color(Material.Purple), "Unknown state should be purple");
        }
        function test_unloadedState() {
            indicator.state = "unloaded";
            compare(indicator.color, Material.color(Material.Grey), "Unloaded state should be grey");
        }
        function test_unmappedStateFallback() {
            indicator.state = "some_invalid_state";
            compare(indicator.color, Material.color(Material.Red), "Unmapped state should fall back to red");
        }

        name: "StateIndicatorTest"
        when: windowShown
    }
}
