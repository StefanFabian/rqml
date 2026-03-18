import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 400
    height: 400

    SpeedSlider {
        id: slider
        from: -5.0
        to: 5.0
        value: 1.0
    }

    TestCase {
        name: "SpeedSliderTest"
        when: windowShown

        function init() {
            slider.value = 1.0;
        }

        function test_initialValue() {
            compare(slider.value, 1.0);
            compare(slider.from, -5.0);
            compare(slider.to, 5.0);
        }

        function test_resetButtonResetsToZero() {
            slider.value = 3.5;
            compare(slider.value, 3.5);

            // Find the "0" reset button by walking children
            var resetBtn = findResetButton(slider);
            verify(resetBtn !== null, "Reset button should exist");
            mouseClick(resetBtn);
            compare(slider.value, 0, "Value should be zero after clicking reset button");
        }

        function test_negativeValue() {
            slider.value = -3.0;
            compare(slider.value, -3.0);
        }

        // Helper: find the Button with text "0" (the reset button)
        function findResetButton(parentItem) {
            if (!parentItem) return null;
            if (parentItem.text === "0" && parentItem.clicked !== undefined)
                return parentItem;
            var children = parentItem.children || [];
            if (parentItem.contentItem) children = parentItem.contentItem.children;
            for (var i = 0; i < children.length; i++) {
                var found = findResetButton(children[i]);
                if (found) return found;
            }
            return null;
        }
    }
}
