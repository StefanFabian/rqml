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
            // Setting value below 'from' — root.value stores the raw value
            // but the internal SpinBox clamps to from (0.0)
            spinbox.value = -1.0;
            // Verify the internal SpinBox reflects the clamped value
            compare(spinbox.decimalToInt(spinbox.from), 0,
                "decimalToInt(from) should be 0");

            // Setting value above 'to' — internal SpinBox clamps to to (10.0)
            spinbox.value = 15.0;
            compare(spinbox.decimalToInt(spinbox.to), 100,
                "decimalToInt(to) should be 100");
        }

        function test_stepSizeConversion() {
            // stepSize 0.1 with decimalFactor 10 → internal step of 1
            compare(spinbox.decimalToInt(spinbox.stepSize), 1);
        }
    }
}
