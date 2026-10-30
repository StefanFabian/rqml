import QtQuick
import QtTest
import RQml.Elements
import RQml.Fonts

Item {
    height: 400
    width: 400

    IconButton {
        id: iconBtn

        text: "A"
        tooltipText: "Tooltip A"
    }
    IconToggleButton {
        id: toggleBtn

        checked: false
        iconOff: "F"
        iconOn: "O"
        tooltipTextOff: "Off"
        tooltipTextOn: "On"
    }
    TestCase {
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

        name: "IconButtonTest"
        when: windowShown
    }
}
