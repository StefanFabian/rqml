import QtQuick

/**
 * Keeps Return, Enter and Space from activating a control that just took the focus from a key
 * action, e.g. a Cancel button replacing Send or Send taking the focus from a held Hold to drop.
 * After `arm()`, presses within `duration` milliseconds are swallowed, as are the auto-repeats
 * of a held key. A later press works normally, including its auto-repeats.
 *
 * Usage: `Keys.onPressed: event => guard.filter(event)` on the control and `guard.arm()`
 * in the handler of the action that changes it.
 */
QtObject {
    property real _armedAt: 0
    property bool _blocking: false

    //! Time in milliseconds after `arm()` during which new presses are swallowed.
    property int duration: 500

    //! Starts swallowing Return, Enter and Space presses.
    function arm() {
        _armedAt = Date.now();
        _blocking = true;
    }

    //! Accepts @p event, so the control ignores it, if it is a swallowed Return, Enter or Space press.
    function filter(event) {
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space)
            return;
        if (!event.isAutoRepeat)
            _blocking = Date.now() - _armedAt < duration;
        if (_blocking)
            event.accepted = true;
    }
}
