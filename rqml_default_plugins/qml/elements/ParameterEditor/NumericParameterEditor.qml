import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import "../../interfaces"

RowLayout {
    id: root
    spacing: 8
    property var modelData: ({})
    property var paramValue: null
    property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value

    property bool isInteger: modelData.paramType === ParameterService.typeInteger

    property var range: isInteger ? (modelData.integerRange || {}) : (modelData.floatingPointRange || {})
    property bool hasFrom: range.from !== undefined && range.from !== null && !isNaN(range.from)
    property bool hasTo: range.to !== undefined && range.to !== null && !isNaN(range.to)
    property bool hasRange: hasFrom && hasTo && range.from < range.to

    signal parameterSetFailed(string paramName, string reason)

    onLocalParamValueChanged: {
        if (localParamValue !== undefined && localParamValue !== null) {
            if (hasRange)
                numSlider.value = localParamValue;
        }
    }

    Label {
        objectName: "minLabel_" + (modelData.paramName ?? "")
        text: root.hasRange ? root.range.from : (root.hasFrom ? qsTr("Min: ") + root.range.from : "")
        visible: root.hasRange || root.hasFrom
        Layout.alignment: Qt.AlignVCenter
    }

    Slider {
        id: numSlider
        visible: root.hasRange
        from: root.hasRange ? root.range.from : 0
        to: root.hasRange ? root.range.to : 1
        stepSize: (root.hasRange && root.range.step > 0) ? root.range.step : (root.isInteger ? 1 : 0)
        value: modelData.value
        enabled: !modelData.readOnly
        Layout.fillWidth: true
        onPressedChanged: {
            if (value == localParamValue) return;
            if (!pressed) {
                let prev = localParamValue;
                ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType, function(success, reason) {
                    if (!success) {
                        numSlider.value = prev;
                        if (root.isInteger) intField.value = prev;
                        else doubleField.value = prev;
                        root.parameterSetFailed(modelData.paramName, reason);
                    }
                });
            }
        }
        onMoved: {
            if (root.isInteger) {
                intField.text = Number(value).toFixed(0);
                intField.value = value;
            } else {
                doubleField.text = value.toPrecision(doubleField.decimals);
                doubleField.value = value;
            }
        }
    }

    Label {
        objectName: "maxLabel_" + (modelData.paramName ?? "")
        text: root.hasRange ? root.range.to : (root.hasTo ? qsTr("Max: ") + root.range.to : "")
        visible: root.hasRange || root.hasTo
        Layout.alignment: Qt.AlignVCenter
    }

    IntegerInputField {
        id: intField
        visible: root.isInteger
        objectName: "intField_" + (modelData.paramName ?? "")
        value: root.localParamValue
        enabled: !modelData.readOnly
        from: root.hasRange ? root.range.from : null
        to: root.hasRange ? root.range.to : null
        Layout.preferredWidth: root.hasRange ? 80 : -1
        Layout.fillWidth: !root.hasRange
        onEditingFinished: {
            if (value === localParamValue) return;
            if (root.hasRange)
                numSlider.value = value;
            let prev = localParamValue;
            ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType, function(success, reason) {
                if (!success) {
                    intField.value = prev;
                    if (root.hasRange) numSlider.value = prev;
                    root.parameterSetFailed(modelData.paramName, reason);
                }
            });
        }
    }

    DecimalInputField {
        id: doubleField
        visible: !root.isInteger
        objectName: "doubleField_" + (modelData.paramName ?? "")
        value: root.localParamValue
        enabled: !modelData.readOnly
        from: root.hasRange ? root.range.from : null
        to: root.hasRange ? root.range.to : null
        Layout.preferredWidth: root.hasRange ? 80 : -1
        Layout.fillWidth: !root.hasRange
        onEditingFinished: {
            if (value === localParamValue) return;
            if (root.hasRange)
                numSlider.value = value;
            let prev = localParamValue;
            ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType, function(success, reason) {
                if (!success) {
                    doubleField.value = prev;
                    if (root.hasRange) numSlider.value = prev;
                    root.parameterSetFailed(modelData.paramName, reason);
                }
            });
        }
    }
}
