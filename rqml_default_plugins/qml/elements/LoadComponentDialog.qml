import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Ros2
import RQml.Elements
import "ParameterParser.js" as ParameterParser

/**
 * Asks for the component to load into a container. Package and plugin are free text with suggestions from the local
 * ament index.
 */
Dialog {
    id: root

    /**
     * Emitted on OK with params {packageName, pluginName, nodeName, nodeNamespace, remapRules: [string], logLevel,
     * parameters: [rcl_interfaces/msg/Parameter], useIntraProcessComms}, strings trimmed. logLevel is a
     * rcl_interfaces/msg/Log level, 0 for the container's level.
     */
    signal loadRequested(string container, var params)

    /**
     * Clears the fields and opens the dialog for loading into the container.
     */
    function openFor(container) {
        d.container = container;
        // shortcut: one index lookup per package on the first open (~200 ms for 800 packages), use a listing by resource type once AmentIndex has one
        if (!d.plugins) {
            const plugins = {};
            for (const name of AmentIndex.getPackages()) {
                const resource = AmentIndex.getResource("rclcpp_components", name);
                // The resource lists one "<class>;<library>" per line.
                if (resource)
                    plugins[name] = resource.content.split("\n").map(line => line.split(";")[0].trim()).filter(plugin => plugin !== "");
            }
            d.plugins = plugins;
        }
        packageSelector.text = "";
        pluginSelector.text = "";
        nodeNameField.clear();
        namespaceField.clear();
        remapArea.clear();
        parameterArea.clear();
        logLevelComboBox.currentIndex = 0;
        intraProcessCheckBox.checked = false;
        open();
        packageSelector.focusInput();
    }

    anchors.centerIn: Overlay.overlay
    height: Overlay.overlay ? Math.min(implicitHeight, Overlay.overlay.height - 32) : implicitHeight
    modal: true
    standardButtons: Dialog.Ok | Dialog.Cancel
    title: qsTr("Load Component into %1").arg(d.container)
    // The extra fields need a bit more than the 400 of the other dialogs.
    width: Overlay.overlay ? Math.min(420, Overlay.overlay.width - 32) : 420

    Component.onCompleted: standardButton(Dialog.Ok).enabled = Qt.binding(() => d.valid)
    onAccepted: root.loadRequested(d.container, {
            "packageName": packageSelector.text.trim(),
            "pluginName": pluginSelector.text.trim(),
            "nodeName": nodeNameField.text.trim(),
            "nodeNamespace": namespaceField.text.trim(),
            "remapRules": remapArea.text.split("\n").map(rule => rule.trim()).filter(rule => rule !== ""),
            "logLevel": logLevelComboBox.currentValue,
            "parameters": d.parsedParameters.parameters,
            "useIntraProcessComms": intraProcessCheckBox.checked
        })

    QtObject {
        id: d

        property string container
        readonly property var parsedParameters: ParameterParser.parseParameters(parameterArea.text)
        //! Component class names by package, read from the ament index on the first open.
        property var plugins: null
        readonly property bool valid: packageSelector.text.trim() !== "" && pluginSelector.text.trim() !== "" && parsedParameters.invalidLine === 0

        function acceptIfValid() {
            if (valid)
                root.accept();
        }
    }
    ScrollView {
        id: scrollView
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        anchors.fill: parent
        contentWidth: availableWidth

        GridLayout {
            columns: 2
            width: scrollView.availableWidth

            Label {
                text: qsTr("Package")
            }
            FuzzySelector {
                id: packageSelector
                Layout.fillWidth: true
                model: Object.keys(d.plugins ?? {})
                objectName: "nmLoadPackageField"
                placeholderText: qsTr("e.g. composition")

                onAccepted: d.acceptIfValid()
            }
            Label {
                text: qsTr("Plugin")
            }
            FuzzySelector {
                id: pluginSelector
                Layout.fillWidth: true
                model: (d.plugins ?? {})[packageSelector.text.trim()] ?? []
                objectName: "nmLoadPluginField"
                placeholderText: qsTr("e.g. composition::Talker")

                onAccepted: d.acceptIfValid()
            }
            Label {
                text: qsTr("Node name")
            }
            TextField {
                id: nodeNameField
                Layout.fillWidth: true
                objectName: "nmLoadNodeNameField"
                placeholderText: qsTr("optional")

                onAccepted: d.acceptIfValid()
            }
            Label {
                text: qsTr("Namespace")
            }
            TextField {
                id: namespaceField
                Layout.fillWidth: true
                objectName: "nmLoadNamespaceField"
                placeholderText: qsTr("optional")

                onAccepted: d.acceptIfValid()
            }
            Label {
                Layout.alignment: Qt.AlignTop
                text: qsTr("Remaps")
            }
            TextArea {
                id: remapArea
                Layout.fillWidth: true
                Layout.minimumHeight: 64
                objectName: "nmLoadRemapArea"
                placeholderText: qsTr("one per line, e.g. chatter:=/talk")
                wrapMode: TextArea.Wrap
            }
            Label {
                Layout.alignment: Qt.AlignTop
                text: qsTr("Parameters")
            }
            TextArea {
                id: parameterArea
                Layout.fillWidth: true
                Layout.minimumHeight: 64
                objectName: "nmLoadParameterArea"
                placeholderText: qsTr("one per line, e.g. rate:=10.0")
                wrapMode: TextArea.Wrap
            }
            Label {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                color: Material.color(Material.Red)
                objectName: "nmLoadParameterError"
                text: qsTr("Line %1 is not a valid name:=value").arg(d.parsedParameters.invalidLine)
                visible: d.parsedParameters.invalidLine !== 0
                wrapMode: Text.Wrap
            }
            Label {
                text: qsTr("Log level")
            }
            ComboBox {
                id: logLevelComboBox
                Layout.fillWidth: true
                // rcl_interfaces/msg/Log levels.
                model: [{
                        "text": qsTr("Default"),
                        "value": 0
                    }, {
                        "text": qsTr("Debug"),
                        "value": 10
                    }, {
                        "text": qsTr("Info"),
                        "value": 20
                    }, {
                        "text": qsTr("Warn"),
                        "value": 30
                    }, {
                        "text": qsTr("Error"),
                        "value": 40
                    }, {
                        "text": qsTr("Fatal"),
                        "value": 50
                    }]
                objectName: "nmLoadLogLevelComboBox"
                textRole: "text"
                valueRole: "value"
            }
            CheckBox {
                id: intraProcessCheckBox
                Layout.columnSpan: 2
                objectName: "nmLoadIntraProcessCheckBox"
                text: qsTr("Use intra-process communication")
            }
        }
    }
}
