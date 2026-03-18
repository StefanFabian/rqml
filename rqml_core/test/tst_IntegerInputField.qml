import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 400
    height: 400

    IntegerInputField {
        id: field
        from: -10
        to: 10
        value: 5
    }

    TestCase {
        name: "IntegerInputFieldTest"
        when: windowShown

        function init() {
            field.value = 5;
            field.text = "5";
        }

        function test_initialValue() {
            compare(field.value, 5);
            compare(field.text, "5");
        }

        function test_editingValidValue() {
            field.text = "8";
            field.editingFinished();
            compare(field.value, 8);
            compare(field.text, "8");
        }

        function test_clampToMax() {
            field.text = "15";
            field.editingFinished();
            compare(field.value, 10);
            compare(field.text, "10");
        }

        function test_clampToMin() {
            field.text = "-15";
            field.editingFinished();
            compare(field.value, -10);
            compare(field.text, "-10");
        }

        function test_invalidTextResets() {
            field.value = 4;
            field.text = "abc";
            field.editingFinished();
            compare(field.value, 4);
            compare(field.text, "4");
        }

        function test_exactBoundaryValues() {
            field.text = "-10";
            field.editingFinished();
            compare(field.value, -10, "Exact min boundary should be accepted");

            field.text = "10";
            field.editingFinished();
            compare(field.value, 10, "Exact max boundary should be accepted");
        }

        function test_emptyStringResets() {
            field.value = 3;
            field.text = "";
            field.editingFinished();
            compare(field.value, 3, "Empty string should preserve previous value");
        }

        function test_whitespaceOnlyResets() {
            field.value = 3;
            field.text = "   ";
            field.editingFinished();
            compare(field.value, 3, "Whitespace-only string should preserve previous value");
        }
    }
}
