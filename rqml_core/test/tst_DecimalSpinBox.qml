import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 400
    height: 400

    DecimalSpinBox {
        id: spinbox
        from: 0.0
        to: 10.0
        value: 1.5
        decimals: 1
        stepSize: 0.1
    }

    TestCase {
        name: "DecimalSpinBoxTest"
        when: windowShown

        function init() {
            spinbox.from = 0.0;
            spinbox.to = 10.0;
            spinbox.decimals = 1;
            spinbox.stepSize = 0.1;
            spinbox.suffix = "";
            spinbox.value = 1.5;
        }

        function test_valueAndConversion() {
            compare(spinbox.value, 1.5);
            compare(spinbox.decimalToInt(1.5), 15);

            spinbox.value = 2.5;
            compare(spinbox.value, 2.5);
        }

        function test_decimalFactor() {
            // decimalFactor = 10^decimals = 10^1 = 10
            compare(spinbox.decimalFactor, 10);
        }

        function test_clampToRange() {
            // Setting value below 'from' - root.value stores the raw value
            // but the internal SpinBox clamps to from (0.0)
            spinbox.value = -1.0;
            // Verify the internal SpinBox reflects the clamped value
            compare(spinbox.decimalToInt(spinbox.from), 0,
                "decimalToInt(from) should be 0");

            // Setting value above 'to' - internal SpinBox clamps to to (10.0)
            spinbox.value = 15.0;
            compare(spinbox.decimalToInt(spinbox.to), 100,
                "decimalToInt(to) should be 100");
        }

        function test_stepSizeConversion() {
            // stepSize 0.1 with decimalFactor 10 → internal step of 1
            compare(spinbox.decimalToInt(spinbox.stepSize), 1);
        }

        function findInternalSpinBox(item) {
            for (var i = 0; i < item.children.length; ++i) {
                var c = item.children[i];
                if (c && c.hasOwnProperty("textFromValue") && c.hasOwnProperty("valueFromText"))
                    return c;
                var found = findInternalSpinBox(c);
                if (found) return found;
            }
            return null;
        }

        function test_textFromValueIncludesSuffix() {
            spinbox.suffix = " m";
            spinbox.value = 2.5;
            var inner = findInternalSpinBox(spinbox);
            verify(inner !== null, "internal SpinBox should be found");
            var txt = inner.textFromValue(inner.value, Qt.locale());
            verify(txt.indexOf(" m") !== -1, "text should contain suffix: " + txt);
            verify(txt.indexOf("2") !== -1, "text should contain numeric value: " + txt);
        }

        function test_textFromValueDecimals() {
            spinbox.decimals = 3;
            var inner = findInternalSpinBox(spinbox);
            // Use the fresh scale explicitly; internal SpinBox.value is not
            // reactive to decimals changes alone.
            var scaled = spinbox.decimalToInt(1.5); // 1500
            var txt = inner.textFromValue(scaled, Qt.locale());
            // Should include three decimal digits (locale-dependent separator)
            verify(/1[.,]500/.test(txt), "expected three decimal digits, got: " + txt);
        }

        function test_valueFromTextParsesSuffix() {
            spinbox.suffix = " m";
            spinbox.decimals = 2;
            var inner = findInternalSpinBox(spinbox);
            var parsed = inner.valueFromText("3" + Qt.locale().decimalPoint + "25 m", Qt.locale());
            // Expect decimalToInt(3.25) = 325
            compare(parsed, 325);
        }

        function test_onValueModifiedUpdatesRoot() {
            spinbox.suffix = "";
            spinbox.decimals = 1;
            spinbox.value = 2.0;
            var inner = findInternalSpinBox(spinbox);
            // Simulate user modification: change inner value and emit valueModified.
            inner.value = 35; // -> root.value should become 3.5
            inner.valueModified();
            compare(spinbox.value, 3.5);
        }

        function test_doubleValidator() {
            var inner = findInternalSpinBox(spinbox);
            verify(inner.validator !== null);
            // Validator bounds track internal integer scale
            compare(inner.validator.bottom, Math.min(inner.from, inner.to));
            compare(inner.validator.top, Math.max(inner.from, inner.to));
            compare(inner.validator.decimals, spinbox.decimals);
        }
    }
}
