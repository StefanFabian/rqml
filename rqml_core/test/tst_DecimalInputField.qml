import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 400
    height: 400

    DecimalInputField {
        id: field
        from: 0.0
        to: 10.0
        value: 5.5
        decimals: 3
    }

    TestCase {
        name: "DecimalInputFieldTest"
        when: windowShown

        function init() {
            field.value = 5.5;
            field.text = "5.5";
        }

        function test_initialValue() {
            compare(field.value, 5.5);
            compare(field.text, "5.5");
        }

        function test_editingValidValue() {
            field.text = "7.25";
            field.editingFinished();
            compare(field.value, 7.25);
            // toPrecision(3) for 7.25 is "7.25"
            compare(field.text, "7.25");
        }

        function test_clampToMax() {
            field.text = "15.0";
            field.editingFinished();
            compare(field.value, 10.0);
            compare(field.text, "10.0");
        }

        function test_clampToMin() {
            field.text = "-5.0";
            field.editingFinished();
            compare(field.value, 0.0);
        }

        function test_invalidTextResets() {
            field.value = 4.2;
            field.text = "abc";
            field.editingFinished();
            compare(field.value, 4.2);
            compare(field.text, "4.20");
        }

        function test_exactBoundaryValues() {
            field.text = "0.0";
            field.editingFinished();
            compare(field.value, 0.0, "Exact min boundary should be accepted");

            field.text = "10.0";
            field.editingFinished();
            compare(field.value, 10.0, "Exact max boundary should be accepted");
        }

        function test_emptyStringResets() {
            field.value = 3.0;
            field.text = "";
            field.editingFinished();
            compare(field.value, 3.0, "Empty string should preserve previous value");
        }

        function test_whitespaceOnlyResets() {
            field.value = 3.0;
            field.text = "   ";
            field.editingFinished();
            compare(field.value, 3.0, "Whitespace-only string should preserve previous value");
        }
    }
}
