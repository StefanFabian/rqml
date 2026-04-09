import QtQuick
import QtQuick.Controls
import QtTest
import Ros2
import RQml.Elements
import RQml.Utils

Item {
    width: 800
    height: 600

    EditMessageDialog {
        id: dialog
        visible: true
        anchors.centerIn: parent
        width: 700
        height: 500
        messageType: "ros_babel_fish_test_msgs/msg/TestMessage"
        message: Ros2.createEmptyMessage("ros_babel_fish_test_msgs/msg/TestMessage")
    }

    TestCase {
        name: "EditMessageDialogTest"
        when: windowShown

        // ---- Helpers --------------------------------------------------------

        function findItemBy(item, predicate) {
            if (!item) return null;
            if (predicate(item)) return item;
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i) {
                var found = findItemBy(children[i], predicate);
                if (found) return found;
            }
            if (item.contentItem && item.contentItem !== item) {
                var f = findItemBy(item.contentItem, predicate);
                if (f) return f;
            }
            return null;
        }

        function findTabBar() {
            return findItemBy(dialog, function (c) {
                return c && c.toString().indexOf("TabBar") !== -1 && c.hasOwnProperty("currentIndex");
            });
        }

        function findStackLayout() {
            return findItemBy(dialog, function (c) {
                return c && c.toString().indexOf("StackLayout") !== -1;
            });
        }

        function findTextArea() {
            return findItemBy(dialog, function (c) {
                return c && c.toString().indexOf("TextArea") !== -1 && c.hasOwnProperty("text");
            });
        }

        function findMessageContentEditor() {
            return findItemBy(dialog, function (c) {
                return c && c.toString().indexOf("MessageContentEditor") !== -1;
            });
        }

        function init() {
            dialog.message = Ros2.createEmptyMessage("ros_babel_fish_test_msgs/msg/TestMessage");
            wait(50);
            // Restore the text area's content explicitly. Earlier tests may
            // have left it in an invalid-JSON state, breaking the original
            // declarative binding.
            var textArea = findTextArea();
            if (textArea !== null)
                textArea.text = JSON.stringify(MessageUtils.toJavaScriptObject(dialog.message) || {}, null, 2);
        }

        // ---- Tests ----------------------------------------------------------

        function test_dualTabInterface() {
            var tabBar = findTabBar();
            var stack = findStackLayout();
            verify(tabBar !== null, "TabBar should exist");
            verify(stack !== null, "StackLayout should exist");
            compare(tabBar.count, 2, "should have Visual and Text tabs");

            tabBar.currentIndex = 0;
            compare(stack.currentIndex, 0, "Visual tab should select index 0");
            tabBar.currentIndex = 1;
            compare(stack.currentIndex, 1, "Text tab should select index 1");
        }

        function test_jsonSerializationFromMessage() {
            var textArea = findTextArea();
            verify(textArea !== null);
            // Empty TestMessage should serialise to a JSON object with the
            // expected fields.
            var parsed;
            try {
                parsed = JSON.parse(textArea.text);
            } catch (e) {
                fail("text area should contain valid JSON, got: " + textArea.text);
            }
            verify(parsed.hasOwnProperty("i32"), "JSON should contain i32 field");
            verify(parsed.hasOwnProperty("b"), "JSON should contain bool field");
        }

        function test_jsonEditUpdatesMessage() {
            var textArea = findTextArea();
            // Build a fresh JSON snapshot, mutate one field, write it back, and
            // simulate editingFinished — the dialog should update its message.
            var snapshot = JSON.parse(textArea.text);
            snapshot.i32 = 314;
            textArea.text = JSON.stringify(snapshot);
            textArea.editingFinished();
            compare(dialog.message.i32, 314,
                "valid JSON edit should update the bound message");
        }

        function test_invalidJsonIsIgnored() {
            var textArea = findTextArea();
            var prevI32 = dialog.message.i32;
            textArea.text = "{ this is not valid json";
            textArea.editingFinished();
            // The message must remain unchanged.
            compare(dialog.message.i32, prevI32,
                "invalid JSON must not corrupt the bound message");
        }

        function test_visualEditPropagatesToText() {
            var editor = findMessageContentEditor();
            var textArea = findTextArea();
            verify(editor !== null);
            verify(editor.model !== null);

            // Edit i32 via the underlying MessageItemModel and verify the text
            // area picks the change up via the `modified` signal hook.
            var model = editor.model;
            var rootCount = model.rowCount();
            var done = false;
            for (var i = 0; i < rootCount; ++i) {
                var keyIdx = model.index(i, 0);
                if (model.data(keyIdx, Qt.DisplayRole) === "i32") {
                    model.setData(model.index(i, 1), 9001, Qt.EditRole);
                    done = true;
                    break;
                }
            }
            verify(done, "i32 field should be present");
            // The dialog updates textArea.text via Qt.binding on `modified`.
            tryVerify(function () {
                try {
                    return JSON.parse(textArea.text).i32 === 9001;
                } catch (e) {
                    return false;
                }
            }, 1000, "text area should reflect visual edits");
        }

        function test_standardOkCancelButtons() {
            // Dialog.Ok | Dialog.Cancel — verify the standardButton accessor
            // returns valid buttons for both.
            verify(dialog.standardButton(Dialog.Ok) !== null,
                "Ok button should be present");
            verify(dialog.standardButton(Dialog.Cancel) !== null,
                "Cancel button should be present");
        }
    }
}
