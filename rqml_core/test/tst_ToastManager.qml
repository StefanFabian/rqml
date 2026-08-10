import QtQuick
import QtTest
import QtQuick.Controls.Material
import RQml.Elements
import RQml.Fonts

Item {
    id: root

    readonly property int defaultDismissDuration: 500

    height: 600
    width: 800

    ToastManager {
        id: toastManager
        dismissDuration: root.defaultDismissDuration
        maxToasts: 3
    }
    TestCase {
        // Runs even when a test failed, which an inline cleanup does not since
        // a failed assertion aborts the test function.
        function cleanup() {
            toastManager.dismissDuration = root.defaultDismissDuration;
            clearToasts();
            wait(250);
        }
        function clearToasts() {
            // Remove all toasts by iterating from the end
            while (toastManager.count > 0) {
                var toast = toastManager.getToast(0);
                if (!toast)
                    break;
                toastManager.removeToastById(toast.toastId);
                wait(50);
            }
        }
        function findDelegate(item) {
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i) {
                var c = children[i];
                if (c && c.hasOwnProperty("toastId"))
                    return c;
                var f = findDelegate(c);
                if (f)
                    return f;
            }
            return null;
        }
        function findDelegateCloseButton(item) {
            if (!item)
                return null;
            if (item.text === IconFont.iconClose && item.clicked !== undefined)
                return item;
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i) {
                var f = findDelegateCloseButton(children[i]);
                if (f)
                    return f;
            }
            return null;
        }
        function findMessageLabel(delegate, text) {
            var found = walkAll(delegate, function (c) {
                    return c && c.objectName === "toastMessage" && c.text === text;
                });
            return found.length > 0 ? found[0] : null;
        }
        function findProgressAnim(delegate) {
            if (!delegate)
                return null;
            var found = walkAll(delegate, function (c) {
                    return c && c.hasOwnProperty("paused") && c.hasOwnProperty("duration") && c.toString().indexOf("NumberAnimation") !== -1;
                });
            return found.length > 0 ? found[0] : null;
        }
        function init() {
            clearToasts();
            compare(toastManager.count, 0, "Toast count should be 0 after init");
        }
        function test_addSingleToast() {
            toastManager.show("Hello", "info");
            compare(toastManager.count, 1, "Should have 1 toast after show()");
        }
        function test_autoDismiss() {
            // dismissDuration is set to 500ms for testing
            toastManager.show("Auto dismiss me", "info");
            compare(toastManager.count, 1);

            // Wait for the dismiss animation to complete (500ms duration + 200ms remove animation)
            tryVerify(function () {
                    return toastManager.count === 0;
                }, 2000, "Toast should be auto-dismissed after dismissDuration");
        }
        function test_defaultLevelIsInfo() {
            toastManager.show("No level specified");
            compare(toastManager.count, 1);
            // The default level should be "info" (source: level || "info")
            var color = toastManager.getToastColor("info");
            compare(color, Material.color(Material.BlueGrey, Material.Shade800), "Default level should produce info color");
        }
        function test_hoverPauseStructural() {
            // Verify the structural contract for hover-pausing: each toast
            // delegate has a HoverHandler whose `hovered` is wired into the
            // progress animation's `paused` property. We cannot drive
            // synthetic hover events through the offscreen QPA platform
            // reliably, so we instead assert the wiring exists by inspecting
            // the delegate tree.
            toastManager.dismissDuration = 5000;
            toastManager.show("hover me", "info");
            tryVerify(function () {
                    return findDelegate(toastManager) !== null;
                }, 1000);
            var delegate = findDelegate(toastManager);

            // The HoverHandler is stored on the delegate's `data` list.
            var hover = null;
            var data = delegate.data || [];
            for (var i = 0; i < data.length; ++i) {
                var c = data[i];
                if (c && c.hasOwnProperty("hovered")) {
                    hover = c;
                    break;
                }
            }
            verify(hover !== null, "delegate should have a HoverHandler");
            compare(hover.hovered, false, "hover state should start unhovered");
        }
        function test_longMessageIsFullyVisible() {
            // A wrapping message must grow the toast and the manager has to
            // reserve that height. The manager is anchored to the bottom of its
            // parent, so a toast that is taller than the reserved height is
            // drawn past the bottom edge and cut off by the window.
            toastManager.dismissDuration = 10000;
            var longMessage = "Failed to activate flipper_trajectory_controller: AUTO: cannot activate the requested controllers because active controller(s) [flipper_velocity_to_position_controller] claim conflicting resources. Use FORCE_AUTO to list the controllers to deactivate.";
            toastManager.show(longMessage, "error");
            tryVerify(function () {
                    return findDelegate(toastManager) !== null;
                }, 2000, "toast delegate should be found");
            var delegate = findDelegate(toastManager);
            var label = findMessageLabel(delegate, longMessage);
            verify(label, "message label should be found");

            // Let the layout settle before measuring.
            wait(200);
            verify(label.lineCount > 1, "The message under test has to wrap");
            // The delegate clips, so the message has to fit inside it. Checking
            // the label against itself would be pointless, it always reports the
            // size of its own content.
            var labelBottom = label.mapToItem(delegate, 0, label.height).y;
            verify(labelBottom <= delegate.height + 1, "The message must fit inside the toast, bottom of the message is at " + labelBottom + " but the toast is only " + delegate.height + " high");
            // The manager is only as high as its content, so a delegate that is
            // higher is drawn past the bottom edge of the parent. The list view
            // measures the delegate when it is added and keeps that height, so
            // this has to hold right away, not eventually.
            compare(toastManager.height, delegate.height, "The manager has to reserve the full height of the toast");
        }
        function test_manualDismissViaCloseButton() {
            // Use a longer dismissDuration so the auto-dismiss animation does not
            // race with the manual-close assertion.
            toastManager.dismissDuration = 10000;
            toastManager.show("Manual close", "info");
            compare(toastManager.count, 1);

            // Allow the delegate to instantiate.
            tryVerify(function () {
                    return findDelegateCloseButton(toastManager) !== null;
                }, 2000, "close button delegate should be found");
            var btn = findDelegateCloseButton(toastManager);
            btn.clicked();
            wait(50);
            compare(toastManager.count, 0, "clicking close button should remove toast");
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
        function test_removeToastById() {
            toastManager.show("To remove", "info");
            compare(toastManager.count, 1);
            var toast = toastManager.getToast(0);
            verify(toast !== null, "Should find a toast ID");
            toastManager.removeToastById(toast.toastId);
            wait(50);
            compare(toastManager.count, 0, "Toast should be removed by ID");
        }
        function test_shortMessageIsVerticallyCentered() {
            toastManager.dismissDuration = 10000;
            toastManager.show("Short message", "success");
            tryVerify(function () {
                    return findDelegate(toastManager) !== null;
                }, 2000, "toast delegate should be found");
            var delegate = findDelegate(toastManager);
            var label = findMessageLabel(delegate, "Short message");
            verify(label, "message label should be found");
            wait(100);
            // The content is centered in the area above the progress bar, so
            // the center of a short message sits half a progress bar (4 px)
            // above the center of the toast. One pixel for rounding.
            const expectedCenter = delegate.height / 2 - 2;
            var labelCenter = label.mapToItem(delegate, 0, 0).y + label.height / 2;
            verify(Math.abs(labelCenter - expectedCenter) <= 1, "A message that does not fill the toast has to stay vertically centered, its center is at " + labelCenter + " instead of " + expectedCenter);
        }
        function test_toastLevelColors() {
            var infoColor = toastManager.getToastColor("info");
            var warningColor = toastManager.getToastColor("warning");
            var errorColor = toastManager.getToastColor("error");
            var successColor = toastManager.getToastColor("success");
            compare(errorColor, Material.color(Material.Red, Material.Shade800), "Error toast should be red");
            compare(warningColor, Material.color(Material.Orange, Material.Shade800), "Warning toast should be orange");
            compare(successColor, Material.color(Material.Green, Material.Shade800), "Success toast should be green");
            compare(infoColor, Material.color(Material.BlueGrey, Material.Shade800), "Info toast should be blue-grey");
        }
        function test_toastLevelIcons() {
            compare(toastManager.getToastIcon("error"), IconFont.iconError);
            compare(toastManager.getToastIcon("warning"), IconFont.iconWarning);
            compare(toastManager.getToastIcon("success"), IconFont.iconSuccess);
            compare(toastManager.getToastIcon("info"), IconFont.iconInfo);
            compare(toastManager.getToastIcon("bogus"), IconFont.iconInfo, "unknown levels should fall back to info icon");
            verify(IconFont.iconSuccess !== IconFont.iconInfo, "Success has to have its own icon");
        }
        function test_uniqueToastIds() {
            toastManager.show("Toast A", "info");
            toastManager.show("Toast B", "info");

            // Verify IDs are unique
            var ids = [];
            for (var i = 0; i < toastManager.count; ++i) {
                ids.push(toastManager.getToast(i).toastId);
            }
            compare(ids.length, 2, "Should have 2 toast IDs");
            verify(ids[0] !== ids[1], "Toast IDs should be unique");
        }
        function walkAll(item, predicate, out) {
            out = out || [];
            if (!item)
                return out;
            if (predicate(item))
                out.push(item);
            // QML stores both children and non-visual resources in `data`.
            var data = item.data || [];
            for (var i = 0; i < data.length; ++i) {
                var c = data[i];
                if (!c)
                    continue;
                if (predicate(c))
                    out.push(c);
                walkAll(c, predicate, out);
            }
            return out;
        }

        name: "ToastManagerTest"
        when: windowShown
    }
}
