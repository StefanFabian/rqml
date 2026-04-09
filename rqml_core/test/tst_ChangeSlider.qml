import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 400
    height: 400

    ChangeSlider {
        id: slider
        from: 0
        to: 100
        currentValue: 50
        value: 20
    }

    TestCase {
        name: "ChangeSliderTest"
        when: windowShown

        function init() {
            slider.value = 20;
            slider.currentValue = 50;
        }

        function test_currentValueVisualPosition() {
            compare(slider.currentValue, 50, "currentValue should be 50");
            compare(slider.value, 20, "value should be 20");
            compare(slider.currentValueVisualPosition, 0.5, "visual position should be 0.5");
            compare(slider.visualPosition, 0.2, "value visual position should be 0.2");

            slider.currentValue = 80;
            compare(slider.currentValueVisualPosition, 0.8, "visual position should be 0.8");

            // out of bounds
            slider.currentValue = 150;
            compare(slider.currentValueVisualPosition, 1.0, "visual position should clamp to 1.0");

            slider.currentValue = -50;
            compare(slider.currentValueVisualPosition, 0.0, "visual position should clamp to 0.0");
        }

        function test_stepSize() {
            // stepSize is auto-computed as (to - from) / 1000
            compare(slider.stepSize, (slider.to - slider.from) / 1000);

            slider.to = 200;
            slider.from = 0;
            compare(slider.stepSize, 0.2, "stepSize should update with range");
        }

        function test_layoutMirroring() {
            slider.currentValue = 25; // 0.25 unmirrored
            compare(slider.currentValueVisualPosition, 0.25);
            mirroredSlider.currentValue = 25;
            // Mirrored should be 1 - 0.25 = 0.75
            compare(mirroredSlider.currentValueVisualPosition, 0.75,
                "mirrored position should be inverted");
        }
    }

    ChangeSlider {
        id: mirroredSlider
        from: 0
        to: 100
        value: 10
        currentValue: 25
        LayoutMirroring.enabled: true
    }
}
