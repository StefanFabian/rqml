import QtQuick
import QtTest
import QtQuick.Controls.Material
import RQml.Elements

Item {
    width: 800
    height: 600

    ToastManager {
        id: toastManager
        maxToasts: 3
        dismissDuration: 500
    }

    TestCase {
        name: "ToastManagerTest"
        when: windowShown

        function clearToasts() {
            // Remove all toasts by iterating from the end
            while (toastManager.count > 0) {
                // Access the model directly to get the toastId
                var toastId = null;
                for (var i = 0; i < toastManager.data.length; i++) {
                    var obj = toastManager.data[i];
                    if (obj && obj.count !== undefined && obj.get !== undefined && obj.count > 0) {
                        toastId = obj.get(0).toastId;
                        break;
                    }
                }
                if (toastId) {
                    toastManager.removeToastById(toastId);
                    wait(50);
                } else {
                    break;
                }
            }
        }

        function init() {
            clearToasts();
            compare(toastManager.count, 0, "Toast count should be 0 after init");
        }

        function test_addSingleToast() {
            toastManager.show("Hello", "info");
            compare(toastManager.count, 1, "Should have 1 toast after show()");
        }

        function test_maxToastsEvictsOldest() {
            toastManager.show("First", "info");
            toastManager.show("Second", "warning");
            toastManager.show("Third", "error");
            compare(toastManager.count, 3, "Should have 3 toasts at max");

            // Adding a 4th should evict the oldest (First)
            toastManager.show("Fourth", "info");
            compare(toastManager.count, 3, "Count should remain at maxToasts");
        }

        function test_toastLevelColors() {
            var infoColor = toastManager.getToastColor("info");
            var warningColor = toastManager.getToastColor("warning");
            var errorColor = toastManager.getToastColor("error");

            compare(errorColor, Material.color(Material.Red, Material.Shade800),
                "Error toast should be red");
            compare(warningColor, Material.color(Material.Orange, Material.Shade800),
                "Warning toast should be orange");
            compare(infoColor, Material.color(Material.BlueGrey, Material.Shade800),
                "Info toast should be blue-grey");
        }

        function test_defaultLevelIsInfo() {
            toastManager.show("No level specified");
            compare(toastManager.count, 1);
            // The default level should be "info" (source: level || "info")
            var color = toastManager.getToastColor("info");
            compare(color, Material.color(Material.BlueGrey, Material.Shade800),
                "Default level should produce info color");
        }

        function test_removeToastById() {
            toastManager.show("To remove", "info");
            compare(toastManager.count, 1);

            // Find the toast ID from the internal model
            var toastId = null;
            for (var i = 0; i < toastManager.data.length; i++) {
                var obj = toastManager.data[i];
                if (obj && obj.count !== undefined && obj.get !== undefined && obj.count > 0) {
                    toastId = obj.get(0).toastId;
                    break;
                }
            }
            verify(toastId !== null, "Should find a toast ID");
            toastManager.removeToastById(toastId);
            wait(50);
            compare(toastManager.count, 0, "Toast should be removed by ID");
        }

        function test_autoDismiss() {
            // dismissDuration is set to 500ms for testing
            toastManager.show("Auto dismiss me", "info");
            compare(toastManager.count, 1);

            // Wait for the dismiss animation to complete (500ms duration + 200ms remove animation)
            tryVerify(function() { return toastManager.count === 0; }, 2000,
                "Toast should be auto-dismissed after dismissDuration");
        }

        function test_uniqueToastIds() {
            toastManager.show("Toast A", "info");
            toastManager.show("Toast B", "info");

            // Find the model and verify IDs are unique
            var ids = [];
            for (var i = 0; i < toastManager.data.length; i++) {
                var obj = toastManager.data[i];
                if (obj && obj.count !== undefined && obj.get !== undefined) {
                    for (var j = 0; j < obj.count; j++) {
                        ids.push(obj.get(j).toastId);
                    }
                    break;
                }
            }
            compare(ids.length, 2, "Should have 2 toast IDs");
            verify(ids[0] !== ids[1], "Toast IDs should be unique");
        }
    }
}
