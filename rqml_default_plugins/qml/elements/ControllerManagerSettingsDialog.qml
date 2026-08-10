import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Elements
import RQml.Fonts
import "../interfaces"

Dialog {
    id: root

    // The plugin context the settings are read from and persisted to.
    property var settings: null

    anchors.centerIn: parent
    modal: true
    standardButtons: Dialog.Ok
    title: qsTr("Controller Manager Settings")
    width: Math.min(parent.width * 0.8, 480)

    onAboutToShow: {
        // Re-sync the controls with the persisted settings. User interaction
        // breaks the initial bindings, so the values are assigned explicitly.
        strictnessComboBox.currentIndex = d.indexOfStrictness(d.strictness);
        activateAsapCheckBox.checked = d.activateAsap;
        timeoutSpinBox.value = d.switchTimeout;
    }

    QtObject {
        id: d

        readonly property bool activateAsap: root.settings?.activate_asap ?? false
        readonly property int strictness: root.settings?.switch_strictness ?? ControllerManagerInterface.Strictness.Auto
        // Labels use the constant names of controller_manager_msgs/srv/SwitchController
        // so that they match the service definition and the ros2 control CLI.
        readonly property var strictnessOptions: [{
                "label": qsTr("BEST_EFFORT"),
                "value": ControllerManagerInterface.Strictness.BestEffort,
                "description": qsTr("Skips transitions that are not necessary and never aborts on failure.")
            }, {
                "label": qsTr("STRICT"),
                "value": ControllerManagerInterface.Strictness.Strict,
                "description": qsTr("Aborts the entire switch and reports an error if anything goes wrong.")
            }, {
                "label": qsTr("AUTO"),
                "value": ControllerManagerInterface.Strictness.Auto,
                "description": qsTr("Resolves the controller chain automatically so that all dependent controllers activate within the same update iteration. Once resolved, the switch is strict: it fails and reports an error if it cannot be performed.")
            }, {
                "label": qsTr("FORCE_AUTO"),
                "value": ControllerManagerInterface.Strictness.ForceAuto,
                "description": qsTr("Like AUTO, but also deactivates any running controller that blocks the requested activation by claiming a conflicting interface.")
            }]
        readonly property real switchTimeout: root.settings?.switch_timeout ?? 0

        function indexOfStrictness(value) {
            for (let i = 0; i < strictnessOptions.length; ++i) {
                if (strictnessOptions[i].value === value)
                    return i;
            }
            // An unknown value was persisted, fall back to the default.
            for (let i = 0; i < strictnessOptions.length; ++i) {
                if (strictnessOptions[i].value === ControllerManagerInterface.Strictness.Auto)
                    return i;
            }
            return 0;
        }
    }
    ColumnLayout {
        anchors.fill: parent

        Label {
            font.bold: true
            text: qsTr("Switch Strictness:")
        }
        ComboBox {
            id: strictnessComboBox
            Layout.fillWidth: true
            currentIndex: d.indexOfStrictness(d.strictness)
            model: d.strictnessOptions
            objectName: "cmSettingsStrictnessComboBox"
            textRole: "label"
            valueRole: "value"

            // Only persist while the dialog is shown. Otherwise the initial
            // binding would already write the default into the settings and
            // pre-empt the plugin's own initialization.
            onCurrentValueChanged: {
                if (!root.visible || !root.settings || currentValue === undefined || currentValue === root.settings.switch_strictness)
                    return;
                root.settings.switch_strictness = currentValue;
            }
        }
        Hint {
            Layout.fillWidth: true
            objectName: "cmSettingsStrictnessDescription"
            text: d.strictnessOptions[d.indexOfStrictness(d.strictness)].description
        }
        RowLayout {
            Layout.fillWidth: true
            objectName: "cmSettingsStrictnessWarning"
            spacing: 8
            visible: d.strictness === ControllerManagerInterface.Strictness.Auto || d.strictness === ControllerManagerInterface.Strictness.ForceAuto

            Text {
                Layout.alignment: Qt.AlignTop
                color: Material.color(Material.Orange)
                font.family: IconFont.name
                text: IconFont.iconWarning
            }
            Hint {
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                text: qsTr("AUTO and FORCE_AUTO are not implemented by the official controller_manager as of 4.45 (08/2026). It accepts the request and behaves like BEST_EFFORT.")
            }
        }
        CheckBox {
            id: activateAsapCheckBox
            Layout.fillWidth: true
            Layout.topMargin: 8
            checked: d.activateAsap
            objectName: "cmSettingsActivateAsapCheckBox"
            text: qsTr("Activate as soon as possible")

            onToggled: {
                if (!root.settings)
                    return;
                root.settings.activate_asap = checked;
            }
        }
        Hint {
            Layout.fillWidth: true
            text: qsTr("Activates the controllers as soon as their hardware dependencies are ready, waits for all interfaces to be ready otherwise.")
        }
        Label {
            Layout.topMargin: 8
            font.bold: true
            text: qsTr("Switch Timeout:")
        }
        DecimalSpinBox {
            id: timeoutSpinBox
            decimals: 1
            from: 0
            objectName: "cmSettingsTimeoutSpinBox"
            stepSize: 0.5
            suffix: qsTr(" s")
            to: 60
            value: d.switchTimeout

            onValueChanged: {
                if (!root.visible || !root.settings || root.settings.switch_timeout === value)
                    return;
                root.settings.switch_timeout = value;
            }
        }
        Hint {
            Layout.fillWidth: true
            text: qsTr("Time to wait for pending controllers before aborting. Zero uses the controller manager's default of 1 s.")
        }
    }
}
