import QtQuick
import QtQuick.Controls

/**
 * A Button that must be pressed and held (pointer or keyboard) for `holdDuration`
 * milliseconds before it fires its `activated` signal. A fill grows across the button
 * while held and drains again if released early. The accessibility press action
 * activates immediately. Use for destructive or irreversible actions that should not
 * be triggered by an accidental tap.
 */
Button {
    id: control

    property real _progress: 0

    //! Time in milliseconds the button must be held before `activated` fires.
    property int holdDuration: 2000

    //! Fill progress in the range [0, 1] while the button is held.
    readonly property alias progress: control._progress

    //! Emitted once the button has been held for `holdDuration`.
    signal activated

    Accessible.description: qsTr("Press and hold to activate")

    // Assistive technology actions are deliberate, so they skip the hold.
    Accessible.onPressAction: activated()
    onPressedChanged: {
        if (pressed) {
            drainAnimation.stop();
            // Resume from the current fill so a quick re-press is not penalized.
            fillAnimation.duration = holdDuration * (1 - _progress);
            fillAnimation.start();
        } else {
            fillAnimation.stop();
            drainAnimation.start();
        }
    }

    NumberAnimation {
        id: fillAnimation
        property: "_progress"
        target: control
        to: 1

        onFinished: {
            control._progress = 0;
            control.activated();
        }
    }
    NumberAnimation {
        id: drainAnimation
        duration: 150
        property: "_progress"
        target: control
        to: 0
    }

    // Fill overlay follows the background since styles inset it (e.g. Material).
    Rectangle {
        anchors.bottom: control.background.bottom
        anchors.left: control.background.left
        anchors.top: control.background.top
        color: control.palette.highlight
        opacity: 0.35
        radius: control.background.radius ?? 0
        width: control.background.width * control._progress
    }
}
