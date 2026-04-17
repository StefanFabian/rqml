import QtQuick
import QtQuick.Controls
import QtTest
import Ros2
import RQml.Elements
import RQml.Utils

Item {
    height: 600
    width: 800

    QtObject {
        id: mockRqml

        property string clipboard: ""

        function copyTextToClipboard(text) {
            clipboard = text;
        }
        function resetClipboard() {
            clipboard = "";
        }
    }
    EditMessageDialog {
        id: dialog
        anchors.centerIn: parent
        height: 500
        message: Ros2.createEmptyMessage("ros_babel_fish_test_msgs/msg/TestMessage")
        messageType: "ros_babel_fish_test_msgs/msg/TestMessage"
        visible: true
        width: 700
    }
    TestCase {
        function cleanupTestCase() {
            TestContextBridge.setContextProperty("RQml", null);
        }

        // ---- Helpers --------------------------------------------------------
        function findItemBy(item, predicate) {
            if (!item)
                return null;
            if (predicate(item))
                return item;
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i) {
                var found = findItemBy(children[i], predicate);
                if (found)
                    return found;
            }
            if (item.contentItem && item.contentItem !== item) {
                var f = findItemBy(item.contentItem, predicate);
                if (f)
                    return f;
            }
            return null;
        }
        function findMessageContentEditor() {
            return findItemBy(dialog, function (c) {
                    return c && c.toString().indexOf("MessageContentEditor") !== -1;
                });
        }
        function findStackLayout() {
            return findItemBy(dialog, function (c) {
                    return c && c.toString().indexOf("StackLayout") !== -1;
                });
        }
        function findTabBar() {
            return findItemBy(dialog, function (c) {
                    return c && c.toString().indexOf("TabBar") !== -1 && c.hasOwnProperty("currentIndex");
                });
        }
        function findTextArea() {
            return findItemBy(dialog, function (c) {
                    return c && c.toString().indexOf("TextArea") !== -1 && c.hasOwnProperty("text");
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
        function initTestCase() {
            TestContextBridge.setContextProperty("RQml", mockRqml);
        }
        function test_copyJsonButtonCopiesViaUi() {
            var tabBar = findTabBar();
            var textArea = findTextArea();
            var button = null;
            tabBar.currentIndex = 1;
            tryVerify(function () {
                    button = findItemBy(dialog, function (c) {
                            return c && c.objectName === "editMessageDialogCopyJsonButton" && c.visible;
                        });
                    return button !== null;
                }, 1000, "Copy JSON button should be visible on the JSON tab");
            RQml.resetClipboard();
            mouseClick(button);
            compare(RQml.clipboard, textArea.text, "Copy JSON button should copy the JSON text");
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
        function test_invalidJsonIsIgnored() {
            var textArea = findTextArea();
            var prevI32 = dialog.message.i32;
            textArea.text = "{ this is not valid json";
            textArea.editingFinished();
            // The message must remain unchanged.
            compare(dialog.message.i32, prevI32, "invalid JSON must not corrupt the bound message");
        }
        function test_jsonEditUpdatesMessage() {
            var tabBar = findTabBar();
            var textArea = findTextArea();
            tabBar.currentIndex = 1;
            // Build a fresh JSON snapshot, mutate one field, write it back, and
            // simulate editingFinished — the dialog should update its message.
            var snapshot = JSON.parse(textArea.text);
            snapshot.i32 = 314;
            textArea.text = JSON.stringify(snapshot);
            textArea.editingFinished();
            compare(dialog.message.i32, 314, "valid JSON edit should update the bound message");
        }
        function test_jsonSerializationFromMessage() {
            var tabBar = findTabBar();
            var textArea = findTextArea();
            tabBar.currentIndex = 1;
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
        function test_readonly_mode() {
            var tabBar = findTabBar();
            var textArea = findTextArea();
            dialog.readonly = true;
            tabBar.currentIndex = 1;
            compare(dialog.standardButtons, Dialog.Close, "Readonly dialog should use a close button");
            compare(textArea.readOnly, true, "JSON text area should be readonly in readonly mode");
            verify(dialog.standardButton(Dialog.Close) !== null, "Close button should be present in readonly mode");
            verify(findItemBy(dialog, function (c) {
                        return c && c.objectName === "editMessageDialogCopyJsonButton" && c.visible;
                    }) !== null, "Copy JSON button should be visible in readonly mode");
            dialog.readonly = false;
        }
        function test_standardOkCancelButtons() {
            // Dialog.Ok | Dialog.Cancel — verify the standardButton accessor
            // returns valid buttons for both.
            verify(dialog.standardButton(Dialog.Ok) !== null, "Ok button should be present");
            verify(dialog.standardButton(Dialog.Cancel) !== null, "Cancel button should be present");
        }
        function test_visualEditPropagatesToText() {
            var tabBar = findTabBar();
            var editor = findMessageContentEditor();
            var textArea = findTextArea();
            tabBar.currentIndex = 0;
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

        name: "EditMessageDialogTest"
        when: windowShown
    }
}
