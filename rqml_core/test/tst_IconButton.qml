import QtQuick
import QtTest
import RQml.Elements
import RQml.Fonts

Item {
    width: 400
    height: 400

    IconButton {
        id: iconBtn
        text: "A"
        tooltipText: "Tooltip A"
    }

    IconToggleButton {
        id: toggleBtn
        iconOn: "O"
        iconOff: "F"
        tooltipTextOn: "On"
        tooltipTextOff: "Off"
        checked: false
    }

    TestCase {
        name: "IconButtonTest"
        when: windowShown

        function test_iconButton() {
            compare(iconBtn.text, "A");
            compare(iconBtn.tooltipText, "Tooltip A");
            compare(iconBtn.font.family, IconFont.name);
        }

        function test_iconToggleButton() {
            compare(toggleBtn.checked, false);
            compare(toggleBtn.text, "F");

            toggleBtn.checked = true;
            compare(toggleBtn.text, "O");
        }
    }
}
