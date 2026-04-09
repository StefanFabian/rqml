import QtQuick
import QtQuick.Controls
import QtTest
import Ros2
import RQml.Elements

// Functional tests using a real `MessageItemModel` populated from a
// ros_babel_fish_test_msgs/msg/TestMessage. Verifies type <-> editor mapping,
// array add/delete row, model <-> UI sync, and the readonly property.
Item {
    width: 600
    height: 800

    MessageItemModel {
        id: testModel
        messageType: "ros_babel_fish_test_msgs/msg/TestMessage"
    }

    MessageContentEditor {
        id: editor
        anchors.fill: parent
        model: testModel
    }

    TestCase {
        name: "MessageContentEditorTest"
        when: windowShown

        function init() {
            editor.readonly = false;
            // Reset to a fresh empty TestMessage and let the tree populate.
            testModel.message = Ros2.createEmptyMessage("ros_babel_fish_test_msgs/msg/TestMessage");
            editor.expandRecursively();
            wait(50);
        }

        // ---- Helpers --------------------------------------------------------

        // Recursively walk an item, returning a list of child Items whose
        // toString() contains `typeName`.
        function collectByType(item, typeName, out) {
            out = out || [];
            if (!item) return out;
            if (item.toString().indexOf(typeName) !== -1) out.push(item);
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i)
                collectByType(children[i], typeName, out);
            // Also walk contentItem (delegates create components there).
            if (item.contentItem && item.contentItem !== item)
                collectByType(item.contentItem, typeName, out);
            return out;
        }

        function countByType(typeName) {
            return collectByType(editor, typeName).length;
        }

        // ---- Structural defaults --------------------------------------------

        function test_defaultReadonly() {
            compare(editor.readonly, false);
        }

        function test_clipAndFlick() {
            compare(editor.clip, true);
            compare(editor.flickableDirection, Flickable.AutoFlickIfNeeded);
        }

        function test_columnWidthProviderHonoursMinimum() {
            var w = editor.columnWidthProvider(1);
            verify(!isNaN(w));
            verify(w >= 160, "column 1 should respect the 160 minimum width");
        }

        // ---- Type → editor mapping ------------------------------------------

        function test_boolFieldGetsCheckBox() {
            // The TestMessage has a single bool `b` → expect at least one CheckBox.
            verify(countByType("CheckBox") >= 1, "bool field should produce a CheckBox");
        }

        function test_numericFieldsGetIntegerOrDecimalInput() {
            // Many integer fields (uint8/16/32/64, int8/16/32/64) → IntegerInputField,
            // and float32/float64 → DecimalInputField.
            verify(countByType("IntegerInputField") >= 4,
                "numeric integer fields should produce IntegerInputField editors, found " + countByType("IntegerInputField"));
            verify(countByType("DecimalInputField") >= 2,
                "float/double fields should produce DecimalInputField editors, found " + countByType("DecimalInputField"));
        }

        function test_stringFieldGetsTextField() {
            // `str` and `bounded_str` are short strings → TextField (not TextArea).
            verify(countByType("TextField") >= 1,
                "short string field should produce a TextField editor");
        }

        // ---- Array Add Row / Delete Row -------------------------------------

        function findArrayRowIndex() {
            // Locate the array row (`point_arr`) by searching the model for a
            // row whose 'type' role is 'array'.
            // The tree is rooted at QModelIndex(); top-level rows correspond
            // to the message fields in declaration order.
            var rootCount = testModel.rowCount(testModel.index(-1, -1));
            for (var i = 0; i < rootCount; ++i) {
                var idx = testModel.index(i, 0);
                var type = testModel.data(idx, Qt.UserRole + 5); // "type" role
                if (type === "array") return idx;
            }
            return null;
        }

        function test_arrayInsertAndRemoveRowsViaModel() {
            // Locate point_arr by name (column 0 / display role).
            var rootCount = testModel.rowCount();
            var arrIdx = null;
            for (var i = 0; i < rootCount; ++i) {
                var ci = testModel.index(i, 0);
                if (testModel.data(ci, Qt.DisplayRole) === "point_arr") {
                    arrIdx = ci;
                    break;
                }
            }
            verify(arrIdx !== null, "point_arr field should exist in TestMessage");

            var initial = testModel.rowCount(arrIdx);
            verify(testModel.insertRow(initial, arrIdx), "insertRow should succeed for arrays");
            compare(testModel.rowCount(arrIdx), initial + 1, "row count should grow after insert");

            verify(testModel.removeRow(initial, arrIdx), "removeRow should succeed for arrays");
            compare(testModel.rowCount(arrIdx), initial, "row count should shrink after remove");
        }

        // ---- UI → model synchronization -------------------------------------

        function test_modelEditUpdatesMessage() {
            // Find the `i32` row and edit it via the model's setData.
            var rootCount = testModel.rowCount();
            for (var i = 0; i < rootCount; ++i) {
                var idx = testModel.index(i, 0);
                if (testModel.data(idx, Qt.DisplayRole) === "i32") {
                    var editIdx = testModel.index(i, 1);
                    verify(testModel.setData(editIdx, 4242, Qt.EditRole),
                        "setData should accept an int32 value");
                    var msg = testModel.message;
                    compare(msg.i32, 4242, "message should reflect edited value");
                    return;
                }
            }
            fail("i32 field not found in TestMessage");
        }

        // ---- Readonly mode --------------------------------------------------

        function test_readonlySuppressesEditors() {
            var inputsBefore = countByType("IntegerInputField") + countByType("DecimalInputField") + countByType("CheckBox") + countByType("TextField");
            verify(inputsBefore > 0);
            editor.readonly = true;
            // Force the delegates to rebuild by collapsing/expanding.
            editor.collapseRecursively();
            editor.expandRecursively();
            wait(50);
            var inputsAfter = countByType("IntegerInputField") + countByType("DecimalInputField") + countByType("CheckBox") + countByType("TextField");
            verify(inputsAfter === 0,
                "readonly mode should produce no interactive editors, found " + inputsAfter);
        }
    }
}
