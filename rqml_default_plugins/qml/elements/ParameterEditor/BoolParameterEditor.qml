import QtQuick
import QtQuick.Controls
import "../../interfaces"

CheckBox {
    id: root
    property var modelData: ({})
    property var paramValue: null
    property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value

    signal parameterSetFailed(string paramName, string reason)

    onLocalParamValueChanged: if (localParamValue !== undefined)
        checked = localParamValue

    checked: modelData.value ?? false
    enabled: !(modelData.readOnly ?? false)
    onClicked: {
        let prev = !checked;
        ParameterService.setParameter(modelData.nodeName, modelData.paramName, checked, modelData.paramType, function(success, reason) {
            if (!success) {
                checked = prev;
                root.parameterSetFailed(modelData.paramName, reason);
            }
        });
    }
}
