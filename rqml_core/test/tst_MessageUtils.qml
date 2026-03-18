import QtQuick
import QtTest
import RQml.Utils

Item {
    width: 400
    height: 400

    TestCase {
        name: "MessageUtilsTest"

        function test_toJavaScriptObject() {
            var msg = {
                a: 1,
                b: { c: 2 },
                d: [3, 4]
            };
            var jsObj = MessageUtils.toJavaScriptObject(msg);
            compare(jsObj.a, 1);
            compare(jsObj.b.c, 2);
            compare(jsObj.d[0], 3);
            compare(jsObj.d[1], 4);
        }

        function test_toJavaScriptObject_withToArray() {
            // ROS messages may have a toArray() method for array-like types
            var msg = {
                toArray: function() { return [10, 20, 30]; }
            };
            var jsObj = MessageUtils.toJavaScriptObject(msg);
            verify(Array.isArray(jsObj), "toArray() result should be converted to array");
            compare(jsObj.length, 3);
            compare(jsObj[0], 10);
        }

        function test_toJavaScriptObject_primitives() {
            compare(MessageUtils.toJavaScriptObject(null), null);
            compare(MessageUtils.toJavaScriptObject(42), 42);
            compare(MessageUtils.toJavaScriptObject("hello"), "hello");
        }

        function test_toListElement() {
            var msg = [1, 2];
            var list = MessageUtils.toListElement(msg);
            compare(list.length, 2);
            compare(list[0].display, 1);
            compare(list[1].display, 2);
        }

        function test_toListElement_nestedObjects() {
            var msg = [{ x: 1 }, "plain"];
            var list = MessageUtils.toListElement(msg);
            compare(list.length, 2);
            // Object elements are recursively converted, not wrapped in display
            compare(list[0].x, 1);
            // Primitive elements get wrapped
            compare(list[1].display, "plain");
        }

        function test_stripEmptyFields() {
            var msg = {
                a: 1,
                b: "",
                c: 0,
                d: false,
                e: { f: 0 },
                f: [0, "", false]
            };
            var stripped = MessageUtils.stripEmptyFields(msg);
            compare(stripped.a, 1);
            verify(stripped.b === undefined, "Empty string should be stripped");
            verify(stripped.c === undefined, "Zero should be stripped");
            verify(stripped.d === undefined, "False should be stripped");
            verify(stripped.e === undefined, "Object with only empty fields should be stripped");
            verify(stripped.f === undefined, "Array with only empty values should be stripped");
        }

        function test_stripEmptyFields_preservesNonEmpty() {
            var msg = {
                str: "hello",
                num: 42,
                flag: true,
                nested: { value: 1 },
                arr: [1, 2]
            };
            var stripped = MessageUtils.stripEmptyFields(msg);
            compare(stripped.str, "hello");
            compare(stripped.num, 42);
            compare(stripped.flag, true);
            compare(stripped.nested.value, 1);
            compare(stripped.arr[0], 1);
            compare(stripped.arr[1], 2);
        }

        function test_stripEmptyFields_skipsHashProperties() {
            var msg = {
                "#messageType": "std_msgs/msg/String",
                data: "hello"
            };
            var stripped = MessageUtils.stripEmptyFields(msg);
            verify(stripped["#messageType"] === undefined,
                "Properties starting with # should be skipped");
            compare(stripped.data, "hello");
        }

        function test_stripEmptyFields_skipsClockType() {
            var msg = {
                clockType: 1,
                sec: 10,
                nanosec: 0
            };
            var stripped = MessageUtils.stripEmptyFields(msg);
            verify(stripped.clockType === undefined,
                "clockType property should be skipped");
            compare(stripped.sec, 10);
        }
    }
}
