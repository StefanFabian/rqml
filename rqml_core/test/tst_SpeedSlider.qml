import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 600
    height: 600

    SpeedSlider {
        id: slider
        width: 400
        height: 400
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

        // Helpers to locate inner items by property signature.
        function findItemBy(parentItem, predicate) {
            if (!parentItem) return null;
            if (predicate(parentItem)) return parentItem;
            var children = parentItem.children || [];
            for (var i = 0; i < children.length; ++i) {
                var f = findItemBy(children[i], predicate);
                if (f) return f;
            }
            return null;
        }

        function findInnerSlider(item) {
            return findItemBy(item, function (c) {
                return c && c.hasOwnProperty("orientation") && c.hasOwnProperty("stepSize") && c.hasOwnProperty("from") && c.hasOwnProperty("to") && c.hasOwnProperty("value") && !c.hasOwnProperty("decimals");
            });
        }

        function findDecimalFieldWith(item, minFrom, maxTo) {
            return findItemBy(item, function (c) {
                return c && c.hasOwnProperty("decimals") && c.hasOwnProperty("from") && c.hasOwnProperty("to") && c.hasOwnProperty("value") && c.from === minFrom && c.to === maxTo;
            });
        }

        function test_sliderSyncsFromValueField() {
            var innerSlider = findInnerSlider(slider);
            verify(innerSlider !== null);
            // valueField has from/to equal to root.from/root.to.
            var valueField = findDecimalFieldWith(slider, slider.from, slider.to);
            verify(valueField !== null);
            valueField.value = 2.5;
            compare(innerSlider.value, 2.5, "slider should follow valueField changes");
        }

        function test_sliderBoundsFollowMinMaxFields() {
            var innerSlider = findInnerSlider(slider);
            // maxField is the one with from=0.1, to=100.0
            var maxField = findDecimalFieldWith(slider, 0.1, 100.0);
            // minField: from=-100, to=-0.1
            var minField = findDecimalFieldWith(slider, -100.0, -0.1);
            verify(maxField !== null);
            verify(minField !== null);
            // Min/max fields use decimals=1 (i.e. toPrecision(1)), so pick
            // single-significant-digit values that round-trip cleanly.
            maxField.value = 3;
            minField.value = -2;
            compare(innerSlider.to, 3, "slider.to should track maxField");
            compare(innerSlider.from, -2, "slider.from should track minField");
        }

        function findValueField() {
            return findDecimalFieldWith(slider, slider.from, slider.to);
        }

        function test_dragSliderUpdatesValueField() {
            // Move the inner Slider's value programmatically (the binding
            // already covers the "value moved by user" path) and confirm the
            // value field reflects the change.
            var innerSlider = findInnerSlider(slider);
            var valueField = findValueField();
            verify(innerSlider !== null);
            verify(valueField !== null);

            slider.value = 0;
            wait(20);
            innerSlider.value = 2.5;
            wait(20);
            compare(valueField.value, 2.5,
                "value field should follow slider movement");

            // Reset for any other tests.
            slider.value = 1.0;
        }

        function test_directionOrientation() {
            var innerSlider = findInnerSlider(slider);
            slider.direction = Qt.Horizontal;
            compare(innerSlider.orientation, Qt.Horizontal);
            slider.direction = Qt.Vertical;
            compare(innerSlider.orientation, Qt.Vertical);
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
