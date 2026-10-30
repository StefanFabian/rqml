import QtQuick
import QtTest
import RQml.Elements

Item {
    height: 400
    width: 400

    HoldButton {
        id: holdBtn

        holdDuration: 120
        text: "Hold"
    }
    Item {
        id: focusSink

        y: 100
    }
    SignalSpy {
        id: activatedSpy

        signalName: "activated"
        target: holdBtn
    }
    TestCase {
        function init() {
            activatedSpy.clear();
            tryCompare(holdBtn, "progress", 0, 1000);
        }
        function test_accessiblePressActivatesImmediately() {
            holdBtn.Accessible.pressAction();
            compare(activatedSpy.count, 1);
        }
        function test_focusLossCancelsHold() {
            holdBtn.forceActiveFocus();
            keyPress(Qt.Key_Space);
            focusSink.forceActiveFocus();
            wait(holdBtn.holdDuration * 2);
            keyRelease(Qt.Key_Space);
            compare(activatedSpy.count, 0);
        }
        function test_mouseHold() {
            mousePress(holdBtn);
            activatedSpy.wait(1000);
            mouseRelease(holdBtn);
            compare(activatedSpy.count, 1);
        }
        function test_spaceHold() {
            holdBtn.forceActiveFocus();
            keyPress(Qt.Key_Space);
            activatedSpy.wait(1000);
            keyRelease(Qt.Key_Space);
            compare(activatedSpy.count, 1);
        }
        function test_tapsDoNotActivate() {
            mouseClick(holdBtn);
            holdBtn.forceActiveFocus();
            keyClick(Qt.Key_Space);
            wait(holdBtn.holdDuration * 2);
            compare(activatedSpy.count, 0);
        }

        name: "HoldButtonTest"
        when: windowShown
    }
}
