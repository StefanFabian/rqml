import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import "interfaces"

/**
 * MoveIt Controller Plugin
 *
 * Provides a UI for controlling robot motion through MoveIt's moveGroup action.
 * Features:
 * - Move group selection from SRDF
 * - Joint sliders for goal position control
 * - Predefined pose buttons from SRDF group_states
 * - Velocity scaling and planning time configuration
 */
Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(500, 400)

    anchors.fill: parent
    color: palette.base

    // ========================================================================
    // Private Data
    // ========================================================================
    QtObject {
        id: d

        readonly property bool configured: hasActionServer && hasMoveGroups
        property string errorDetails: ""
        property string errorTitle: ""
        readonly property bool hasActionServer: moveItInterface.actionServers.count > 0
        readonly property bool hasMoveGroups: moveItInterface.moveGroups.count > 0
        property bool planningConfigExpanded: false
        property bool showError: false
    }
    MoveItInterface {
        id: moveItInterface

        accelerationScale: context.accelerationScale ?? 0.1
        actionServer: context.actionServer ?? ""
        moveGroupName: context.moveGroup ?? ""
        numPlanningAttempts: context.planningAttempts ?? 1
        planningTime: context.planningTime ?? 5.0
        velocityScale: context.velocityScale ?? 0.1

        onGoalAccepted: {
            d.showError = false;
            errorHideTimer.stop();
        }
        onMotionFailed: function (title, details) {
            d.errorTitle = title;
            d.errorDetails = details;
            d.showError = true;
            errorHideTimer.restart();
        }
    }

    // Timer to auto-hide error after 10 seconds
    Timer {
        id: errorHideTimer

        interval: 10000

        onTriggered: d.showError = false
    }
    KeyActivationGuard {
        id: keyGuard

    }

    // ========================================================================
    // Main Layout
    // ========================================================================
    GridLayout {
        anchors.fill: parent
        anchors.margins: 8
        columnSpacing: 8
        columns: 3
        rowSpacing: 8

        // --------------------------------------------------------------------
        // Action Server Selection
        // --------------------------------------------------------------------
        Label {
            text: "Action Server"
        }
        RowLayout {
            Layout.columnSpan: 2
            Layout.fillWidth: true

            ComboBox {
                id: actionServerComboBox

                Layout.fillWidth: true
                currentIndex: {
                    for (let i = 0; i < moveItInterface.actionServers.count; i++) {
                        if (moveItInterface.actionServers.get(i).name === context.actionServer)
                            return i;
                    }
                    return 0;
                }
                model: moveItInterface.actionServers
                objectName: "moveitActionServerComboBox"
                textRole: "name"

                onActivated: {
                    if (currentText && currentText !== context.actionServer) {
                        context.actionServer = currentText;
                    }
                }
                onCurrentTextChanged: {
                    // Auto-select first discovered action server only when context has no explicit
                    // selection yet. Deferred since discovery can run inside the actionServer binding.
                    Qt.callLater(() => {
                        if (!context.actionServer && currentText)
                            context.actionServer = currentText;
                    });
                }
            }
            RefreshButton {
                objectName: "moveitRefreshButton"

                onClicked: {
                    animate = true;
                    moveItInterface.refresh();
                    animate = false;
                }
            }
        }

        // --------------------------------------------------------------------
        // Empty-state placeholder (shown when no action server or no groups)
        // --------------------------------------------------------------------
        Label {
            Layout.columnSpan: 3
            Layout.fillHeight: true
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            objectName: "moveitEmptyStateLabel"
            text: d.hasActionServer ? "No MoveGroups found." : "No MoveGroup action server found."
            verticalAlignment: Text.AlignVCenter
            visible: !d.configured
        }

        // --------------------------------------------------------------------
        // Move Group Selection
        // --------------------------------------------------------------------
        Label {
            text: "Move Group"
            visible: d.configured
        }
        ComboBox {
            id: moveGroupComboBox

            Layout.columnSpan: 2
            Layout.fillWidth: true
            currentIndex: {
                for (let i = 0; i < moveItInterface.moveGroups.count; i++) {
                    if (moveItInterface.moveGroups.get(i).name === context.moveGroup)
                        return i;
                }
                return 0;
            }
            model: moveItInterface.moveGroups
            objectName: "moveitMoveGroupComboBox"
            textRole: "name"
            visible: d.configured

            onActivated: {
                if (currentText && currentText !== context.moveGroup) {
                    context.moveGroup = currentText;
                }
            }
            onCurrentTextChanged: {
                // Auto-select first available move group only when context has
                // no explicit selection yet.
                if (!context.moveGroup && currentText) {
                    context.moveGroup = currentText;
                }
            }
        }

        // --------------------------------------------------------------------
        // Named Poses Section
        // --------------------------------------------------------------------
        Label {
            Layout.columnSpan: 3
            font.bold: true
            text: "Named Poses"
            visible: d.configured && moveItInterface.namedPoses.count > 0
        }
        Flow {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            objectName: "moveitNamedPosesFlow"
            spacing: 4
            visible: d.configured && moveItInterface.namedPoses.count > 0

            Repeater {
                model: moveItInterface.namedPoses

                Button {
                    ToolTip.delay: 500
                    ToolTip.text: "Apply '" + model.name + "' pose to joint goals"
                    ToolTip.visible: hovered
                    text: model.name

                    onClicked: {
                        moveItInterface.applyNamedPose(model.name);
                    }
                }
            }
        }

        // --------------------------------------------------------------------
        // Error Banner (full width)
        // --------------------------------------------------------------------
        Rectangle {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.preferredHeight: errorBannerColumn.implicitHeight + 12
            border.color: palette.highlightedText
            border.width: 1
            color: palette.highlight
            objectName: "moveitErrorBannerRect"
            radius: 4
            visible: d.configured && d.showError

            ColumnLayout {
                id: errorBannerColumn

                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        color: palette.highlightedText
                        font.bold: true
                        objectName: "moveitErrorTitle"
                        text: d.errorTitle
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Button {
                        flat: true
                        implicitHeight: 20
                        implicitWidth: 20
                        text: "x"

                        onClicked: d.showError = false
                    }
                }
                Label {
                    Layout.fillWidth: true
                    color: palette.highlightedText
                    objectName: "moveitErrorDetails"
                    text: d.errorDetails
                    visible: d.errorDetails !== ""
                    wrapMode: Text.WordWrap
                }
            }
        }

        // --------------------------------------------------------------------
        // Joint Sliders
        // --------------------------------------------------------------------
        Label {
            Layout.columnSpan: 3
            font.bold: true
            text: "Joint Goals"
            visible: d.configured && moveItInterface.joints.count > 0
        }
        ListView {
            id: jointListView

            Layout.columnSpan: 3
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            model: moveItInterface.joints
            objectName: "moveitJointListView"
            spacing: 4
            visible: d.configured && moveItInterface.joints.count > 0

            ScrollBar.vertical: ScrollBar {
                policy: jointListView.contentHeight > jointListView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }
            delegate: RowLayout {
                height: 48
                spacing: 8
                width: jointListView.width - 16
                x: 8

                Label {
                    Layout.preferredWidth: 150
                    elide: Text.ElideRight
                    text: model.name
                }
                ChangeSlider {
                    id: positionSlider

                    Layout.fillWidth: true
                    currentValue: model.position
                    from: model.limits.lower
                    stepSize: 0.01
                    to: model.limits.upper
                    value: model.goal

                    onMoved: {
                        model.goal = Math.round(value * 100) / 100;
                    }
                }
                TextField {
                    readonly property string goalText: model.goal.toFixed(2)

                    horizontalAlignment: Text.AlignRight
                    implicitWidth: 70
                    selectByMouse: true

                    validator: DoubleValidator {
                        bottom: model.limits.lower
                        top: model.limits.upper
                    }

                    // Not bound: typing updates the goal live, so only show external goal changes when not editing.
                    Component.onCompleted: text = goalText
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            text = goalText;
                    }
                    onGoalTextChanged: {
                        if (!activeFocus)
                            text = goalText;
                    }
                    onTextEdited: {
                        let value = parseFloat(text);
                        if (isNaN(value))
                            return;
                        value = Math.min(model.limits.upper, Math.max(value, model.limits.lower));
                        value = Math.round(value * 100) / 100;
                        if (Math.abs(value - model.goal) < 1e-9)
                            return;
                        model.goal = value;
                    }
                }
            }

            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                    return;
                if (!executeButton.visible || !executeButton.enabled || moveItInterface.isGoalActive)
                    return;
                event.accepted = true;
                executeButton.clicked();
                executeButton.forceActiveFocus(Qt.ShortcutFocusReason);
            }
        }

        // --------------------------------------------------------------------
        // Action Buttons (always visible)
        // --------------------------------------------------------------------
        RowLayout {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            visible: d.hasActionServer && !!context.moveGroup

            Button {
                Layout.fillWidth: true
                Layout.margins: 4
                ToolTip.delay: 500
                ToolTip.text: "Reset all joint goals to current positions"
                ToolTip.visible: hovered
                objectName: "moveitResetButton"
                text: "Reset"

                onClicked: moveItInterface.resetGoals()
            }
            Button {
                id: executeButton

                Layout.fillWidth: true
                Layout.margins: 4
                ToolTip.delay: 500
                ToolTip.text: {
                    if (moveItInterface.isGoalActive)
                        return "Cancel current motion";
                    if (moveItInterface.activeJointCount === 0)
                        return "Enable at least one joint to execute";
                    return "Plan and execute motion to goal positions";
                }
                ToolTip.visible: hovered
                enabled: moveItInterface.actionReady && (moveItInterface.isGoalActive || moveItInterface.activeJointCount > 0)
                objectName: "moveitExecuteButton"
                text: moveItInterface.isGoalActive ? "Cancel" : "Execute"

                Keys.onPressed: event => keyGuard.filter(event)
                onClicked: {
                    keyGuard.arm();
                    if (moveItInterface.isGoalActive) {
                        moveItInterface.cancelGoals();
                    } else {
                        moveItInterface.sendGoals();
                    }
                }
            }
        }

        // --------------------------------------------------------------------
        // Planning Configuration (collapsible)
        // --------------------------------------------------------------------
        Rectangle {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            border.color: palette.mid
            border.width: 1
            color: palette.button
            implicitHeight: planningContent.implicitHeight + 12
            radius: 4
            visible: d.hasActionServer && !!context.moveGroup

            GridLayout {
                id: planningContent

                anchors.fill: parent
                anchors.margins: 6
                columns: 3

                // Velocity scale slider
                Label {
                    Layout.leftMargin: 8
                    Layout.preferredWidth: 80
                    text: "Velocity:"
                    visible: d.planningConfigExpanded
                }
                Slider {
                    id: velocitySlider

                    Layout.fillWidth: true
                    from: 0.01
                    objectName: "moveitVelocitySlider"
                    to: 1.0
                    value: context.velocityScale ?? 0.1
                    visible: d.planningConfigExpanded

                    onMoved: context.velocityScale = value
                }
                Label {
                    Layout.preferredWidth: 50
                    Layout.rightMargin: 8
                    horizontalAlignment: Text.AlignRight
                    text: (velocitySlider.value * 100).toFixed(0) + "%"
                    visible: d.planningConfigExpanded
                }

                // Acceleration scale slider
                Label {
                    Layout.leftMargin: 8
                    Layout.preferredWidth: 80
                    text: "Acceleration:"
                    visible: d.planningConfigExpanded
                }
                Slider {
                    id: accelerationSlider

                    Layout.fillWidth: true
                    from: 0.01
                    objectName: "moveitAccelerationSlider"
                    to: 1.0
                    value: context.accelerationScale ?? 0.1
                    visible: d.planningConfigExpanded

                    onMoved: context.accelerationScale = value
                }
                Label {
                    Layout.preferredWidth: 50
                    Layout.rightMargin: 8
                    horizontalAlignment: Text.AlignRight
                    text: (accelerationSlider.value * 100).toFixed(0) + "%"
                    visible: d.planningConfigExpanded
                }

                // Planning time slider
                Label {
                    Layout.leftMargin: 8
                    Layout.preferredWidth: 80
                    text: "Plan time:"
                    visible: d.planningConfigExpanded
                }
                Slider {
                    id: planningTimeSlider

                    Layout.fillWidth: true
                    from: 1.0
                    objectName: "moveitPlanningTimeSlider"
                    to: 30.0
                    value: context.planningTime ?? 5.0
                    visible: d.planningConfigExpanded

                    onMoved: context.planningTime = value
                }
                Label {
                    Layout.preferredWidth: 50
                    Layout.rightMargin: 8
                    horizontalAlignment: Text.AlignRight
                    text: planningTimeSlider.value.toFixed(1) + "s"
                    visible: d.planningConfigExpanded
                }

                // Planning attempts slider
                Label {
                    Layout.leftMargin: 8
                    Layout.preferredWidth: 80
                    text: "Attempts:"
                    visible: d.planningConfigExpanded
                }
                Slider {
                    id: planningAttemptsSlider

                    Layout.fillWidth: true
                    from: 1
                    objectName: "moveitPlanningAttemptsSlider"
                    stepSize: 1
                    to: 20
                    value: context.planningAttempts ?? 5
                    visible: d.planningConfigExpanded

                    onMoved: context.planningAttempts = Math.round(value)
                }
                Label {
                    Layout.preferredWidth: 50
                    Layout.rightMargin: 8
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(planningAttemptsSlider.value).toString()
                    visible: d.planningConfigExpanded
                }

                // Toggle header stays at the bottom so the content expands upward.
                Button {
                    id: planningConfigHeaderButton

                    Layout.columnSpan: 3
                    Layout.fillWidth: true
                    flat: true
                    objectName: "moveitPlanningConfigButton"

                    contentItem: RowLayout {
                        spacing: 8

                        Label {
                            font.family: IconFont.name
                            font.pixelSize: 12
                            text: d.planningConfigExpanded ? IconFont.iconChevronUp : IconFont.iconChevronRight
                        }
                        Label {
                            text: "Planning Configuration"
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Label {
                            text: {
                                let result = moveItInterface.planningTime.toFixed(1) + "s / ";
                                result += moveItInterface.numPlanningAttempts + " Attempts ・ ";
                                result += "Vel: " + (moveItInterface.velocityScale * 100).toFixed(0) + "%, ";
                                result += "Acc: " + (moveItInterface.accelerationScale * 100).toFixed(0) + "%";
                                return result;
                            }
                            visible: !d.planningConfigExpanded
                        }
                    }

                    onClicked: d.planningConfigExpanded = !d.planningConfigExpanded
                }
            }
        }

        // --------------------------------------------------------------------
        // Status Bar
        // --------------------------------------------------------------------
        RowLayout {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            spacing: 16

            Label {
                objectName: "moveitUrdfStatusLabel"
                text: "URDF: " + (moveItInterface.hasRobotDescription ? "Loaded" : "Waiting...")
            }
            Label {
                objectName: "moveitSrdfStatusLabel"
                text: "SRDF: " + (moveItInterface.hasSrdf ? "Loaded" : "Waiting...")
            }
            Item {
                Layout.fillWidth: true
            }
            Label {
                objectName: "moveitActionStatusLabel"
                text: "Action: " + (moveItInterface.actionReady ? "Ready" : "Connecting...")
            }
        }
    }
}
