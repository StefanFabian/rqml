import QtQuick
import QtTest
import QtQuick.Controls.Material
import RQml.Elements

Item {
    width: 400
    height: 400

    StateIndicator {
        id: indicator
        state: "active"
    }

    TestCase {
        name: "StateIndicatorTest"
        when: windowShown

        function init() {
            indicator.state = "unknown";
        }

        function test_activeState() {
            indicator.state = "active";
            compare(indicator.color, Material.color(Material.Green),
                "Active state should be green");
        }

        function test_inactiveState() {
            indicator.state = "inactive";
            compare(indicator.color, Material.color(Material.Blue),
                "Inactive state should be blue");
        }

        function test_unconfiguredState() {
            indicator.state = "unconfigured";
            compare(indicator.color, Material.color(Material.Orange),
                "Unconfigured state should be orange");
        }

        function test_unloadedState() {
            indicator.state = "unloaded";
            compare(indicator.color, Material.color(Material.Grey),
                "Unloaded state should be grey");
        }

        function test_unknownState() {
            indicator.state = "unknown";
            compare(indicator.color, Material.color(Material.Purple),
                "Unknown state should be purple");
        }

        function test_unmappedStateFallback() {
            indicator.state = "some_invalid_state";
            compare(indicator.color, Material.color(Material.Red),
                "Unmapped state should fall back to red");
        }
    }
}
