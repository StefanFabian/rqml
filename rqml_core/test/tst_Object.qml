import QtQuick
import QtTest
import RQml.Utils as RqmlUtils

Item {
    width: 400
    height: 400

    RqmlUtils.Object {
        id: obj
        QtObject { objectName: "child1" }
        QtObject { objectName: "child2" }
    }

    TestCase {
        name: "ObjectTest"
        when: windowShown

        function test_declaredChildrenAccessible() {
            // Verify declared children are present and accessible by objectName
            verify(obj.children.length >= 2, "Should have at least the 2 declared children");

            var foundChild1 = false;
            var foundChild2 = false;
            for (var i = 0; i < obj.children.length; i++) {
                if (obj.children[i].objectName === "child1") foundChild1 = true;
                if (obj.children[i].objectName === "child2") foundChild2 = true;
            }
            verify(foundChild1, "child1 should be accessible in children list");
            verify(foundChild2, "child2 should be accessible in children list");
        }

        function test_emptyObject() {
            var empty = Qt.createQmlObject(
                'import QtQuick; import RQml.Utils as RqmlUtils; RqmlUtils.Object {}',
                obj, "dynamicEmpty");
            verify(empty !== null, "Empty Object should be creatable");
            empty.destroy();
        }
    }
}
