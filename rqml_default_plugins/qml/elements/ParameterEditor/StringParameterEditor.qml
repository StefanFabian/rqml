import QtQuick
import QtQuick.Controls
import "../../interfaces"

TextField {
    id: root

    property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
    property var modelData: ({})
    property var paramValue: null

    signal parameterSetFailed(string paramName, string reason)

    ToolTip.text: text
    ToolTip.visible: hovered && implicitWidth > width
    enabled: !(modelData.readOnly ?? false)
    objectName: "stringEditor_" + (modelData.paramName ?? "")
    selectByMouse: true
    text: modelData.value ?? ""

    onEditingFinished: {
        if (text === localParamValue)
            return;
        let prev = localParamValue;
        ParameterService.setParameter(modelData.nodeName, modelData.paramName, text, modelData.paramType, function (success, reason) {
            if (!success) {
                text = prev !== undefined ? prev : "";
                root.parameterSetFailed(modelData.paramName, reason);
            }
        });
    }
    onLocalParamValueChanged: if (localParamValue !== undefined)
        text = localParamValue
}
