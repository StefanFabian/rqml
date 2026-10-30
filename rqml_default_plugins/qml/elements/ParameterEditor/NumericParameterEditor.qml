import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import "../../interfaces"

RowLayout {
    id: root

    property bool hasFrom: range.from !== undefined && range.from !== null && !isNaN(range.from)
    property bool hasRange: hasFrom && hasTo && range.from < range.to
    property bool hasTo: range.to !== undefined && range.to !== null && !isNaN(range.to)
    property bool isInteger: modelData.paramType === ParameterService.typeInteger
    property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
    property var modelData: ({})
    property var paramValue: null
    property var range: isInteger ? (modelData.integerRange || {}) : (modelData.floatingPointRange || {})

    signal parameterSetFailed(string paramName, string reason)

    spacing: 8

    onLocalParamValueChanged: {
        if (localParamValue !== undefined && localParamValue !== null) {
            if (hasRange)
                numSlider.value = localParamValue;
        }
    }

    Label {
        Layout.alignment: Qt.AlignVCenter
        objectName: "minLabel_" + (modelData.paramName ?? "")
        text: root.hasRange ? root.range.from : (root.hasFrom ? qsTr("Min: ") + root.range.from : "")
        visible: root.hasRange || root.hasFrom
    }
    Slider {
        id: numSlider

        Layout.fillWidth: true
        enabled: !modelData.readOnly
        from: root.hasRange ? root.range.from : 0
        stepSize: (root.hasRange && root.range.step > 0) ? root.range.step : (root.isInteger ? 1 : 0)
        to: root.hasRange ? root.range.to : 1
        value: modelData.value
        visible: root.hasRange

        onMoved: {
            if (root.isInteger) {
                intField.text = Number(value).toFixed(0);
                intField.value = value;
            } else {
                doubleField.text = value.toPrecision(doubleField.decimals);
                doubleField.value = value;
            }
        }
        onPressedChanged: {
            if (value == localParamValue)
                return;
            if (!pressed) {
                let prev = localParamValue;
                ParameterService.setParameter(modelData.nodeName, modelData.paramName, value, modelData.paramType, function (success, reason) {
                    if (!success) {
                        numSlider.value = prev;
                        if (root.isInteger)
                            intField.value = prev;
                        else
                            doubleField.value = prev;
                        root.parameterSetFailed(modelData.paramName, reason);
                    }
                });
            }
        }
    }
    Label {
        Layout.alignment: Qt.AlignVCenter
        objectName: "maxLabel_" + (modelData.paramName ?? "")
        text: root.hasRange ? root.range.to : (root.hasTo ? qsTr("Max: ") + root.range.to : "")
        visible: root.hasRange || root.hasTo
    }
    IntegerInputField {
        id: intField

        Layout.fillWidth: !root.hasRange
        Layout.preferredWidth: root.hasRange ? 80 : -1
        enabled: !modelData.readOnly
        from: root.hasRange ? root.range.from : null
        objectName: "intField_" + (modelData.paramName ?? "")
        to: root.hasRange ? root.range.to : null
        value: root.localParamValue
        visible: root.isInteger

        onEditingFinished: {
            if (parseInt(value) === parseInt(localParamValue))
                return;
            if (root.hasRange)
                numSlider.value = value;
            let prev = localParamValue;
            ParameterService.setParameter(modelData.nodeName, modelData.paramName, parseInt(value), modelData.paramType, function (success, reason) {
                if (!success) {
                    intField.value = prev;
                    if (root.hasRange)
                        numSlider.value = prev;
                    root.parameterSetFailed(modelData.paramName, reason);
                }
            });
        }
    }
    DecimalInputField {
        id: doubleField

        Layout.fillWidth: !root.hasRange
        Layout.preferredWidth: root.hasRange ? 80 : -1
        enabled: !modelData.readOnly
        from: root.hasRange ? root.range.from : null
        objectName: "doubleField_" + (modelData.paramName ?? "")
        to: root.hasRange ? root.range.to : null
        value: root.localParamValue
        visible: !root.isInteger

        onEditingFinished: {
            if (Number(value) === Number(localParamValue))
                return;
            if (root.hasRange)
                numSlider.value = value;
            let prev = localParamValue;
            ParameterService.setParameter(modelData.nodeName, modelData.paramName, Number(value), modelData.paramType, function (success, reason) {
                if (!success) {
                    doubleField.value = prev;
                    if (root.hasRange)
                        numSlider.value = prev;
                    root.parameterSetFailed(modelData.paramName, reason);
                }
            });
        }
    }
}
