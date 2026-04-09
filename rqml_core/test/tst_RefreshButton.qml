import QtQuick
import QtTest
import RQml.Elements
import RQml.Fonts

Item {
    width: 200
    height: 200

    RefreshButton {
        id: btn
    }

    TestCase {
        name: "RefreshButtonTest"
        when: windowShown

        function test_iconAndDefaults() {
            compare(btn.text, IconFont.iconRefresh);
            compare(btn.radius, 4);
            compare(btn.animate, false);
            verify(btn.contentItem !== null);
            compare(btn.contentItem.fontSizeMode, Text.Fit,
                "contentItem should use fit-font sizing for icon scaling");
            compare(btn.contentItem.text, btn.text);
        }

        function test_animationLifecycle() {
            // Capture the icon's initial rotation, animate it, observe that it
            // moves, then turn animate off and confirm it eventually settles back.
            var icon = btn.contentItem;
            compare(icon.rotation, 0);

            btn.animate = true;
            tryVerify(function () { return icon.rotation !== 0; }, 2000,
                "icon should rotate while animate is true");

            btn.animate = false;
            // The animation only stops at the end of a cycle (~600ms rotate + 400ms pause).
            // After it stops, the icon's rotation must stabilise (no longer changing).
            wait(1500);
            var r1 = icon.rotation;
            wait(300);
            compare(icon.rotation, r1,
                "rotation should stabilise after the current cycle completes");
        }
    }
}
