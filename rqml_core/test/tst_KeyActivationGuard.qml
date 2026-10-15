import QtQuick
import QtTest
import RQml.Elements

Item {
    height: 400
    width: 400

    KeyActivationGuard {
        id: guard
        duration: 100
    }
    TestCase {
        function init() {
            guard.arm();
        }
        // Returns whether the guard swallowed a press of @p key.
        function press(key, isAutoRepeat) {
            const event = {
                "key": key,
                "isAutoRepeat": isAutoRepeat,
                "accepted": false
            };
            guard.filter(event);
            return event.accepted;
        }
        function test_freshPressAfterDurationPasses() {
            wait(guard.duration + 50);
            verify(!press(Qt.Key_Return, false));
            verify(!press(Qt.Key_Return, true), "Auto-repeats of an allowed press should pass");
        }
        function test_heldKeySwallowedPastDuration() {
            verify(press(Qt.Key_Return, true));
            wait(guard.duration + 50);
            verify(press(Qt.Key_Return, true), "Auto-repeats of the triggering press should stay swallowed");
            verify(press(Qt.Key_Space, true), "Auto-repeats of a Space held through a Hold to drop should be swallowed");
        }
        function test_otherKeysPass() {
            verify(!press(Qt.Key_A, false));
        }
        function test_pressesWithinDurationSwallowed() {
            verify(press(Qt.Key_Return, false));
            verify(press(Qt.Key_Enter, false));
            verify(press(Qt.Key_Space, false));
        }
    }
}
