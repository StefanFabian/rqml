import QtQuick
import QtQuick.Controls
import "../../interfaces"

TextField {
    id: root
    property var modelData: ({})
    property var paramValue: null
    property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value

    signal parameterSetFailed(string paramName, string reason)

    objectName: "stringEditor_" + (modelData.paramName ?? "")
    onLocalParamValueChanged: if (localParamValue !== undefined)
        text = localParamValue

    text: modelData.value ?? ""
    enabled: !(modelData.readOnly ?? false)
    selectByMouse: true
    ToolTip.text: text
    ToolTip.visible: hovered && implicitWidth > width
    onEditingFinished: {
        if (text === localParamValue) return;
        let prev = localParamValue;
        ParameterService.setParameter(modelData.nodeName, modelData.paramName, text, modelData.paramType, function(success, reason) {
            if (!success) {
                text = prev !== undefined ? prev : "";
                root.parameterSetFailed(modelData.paramName, reason);
            }
        });
    }
}
