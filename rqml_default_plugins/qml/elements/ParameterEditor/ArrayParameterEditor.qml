import QtQuick
import QtQuick.Layouts
import RQml.Elements
import RQml.Fonts
import RQml.Utils

RowLayout {
    id: root

    property var localParamValue: typeof paramValue !== 'undefined' && paramValue !== null ? paramValue : modelData.value
    property var modelData: ({})
    property var paramValue: null

    signal editRequested(var modelData, var arrValue)

    function formatArray(value) {
        if (value === null || value === undefined)
            return "[]";
        let javascriptObject = MessageUtils.toJavaScriptObject(value);
        if (!Array.isArray(javascriptObject)) {
            return JSON.stringify(javascriptObject);
        }
        let len = javascriptObject.length;
        if (len === 0)
            return "[]";
        let preview = [];
        let maxPreview = Math.min(len, 10);
        for (let i = 0; i < maxPreview; i++) {
            preview.push(JSON.stringify(javascriptObject[i]));
        }
        if (len > 10) {
            return "[" + preview.join(", ") + ", ... (" + len + " items)]";
        }
        return "[" + preview.join(", ") + "]";
    }

    spacing: 4

    onLocalParamValueChanged: {
        if (localParamValue !== undefined && localParamValue !== null) {
            arrayValueLabel.text = formatArray(localParamValue);
        }
    }

    TruncatedLabel {
        id: arrayValueLabel

        Layout.fillWidth: true
        color: palette.text
        font.family: "Monospace"
        opacity: 0.8
        text: root.formatArray(root.localParamValue)
    }
    IconButton {
        enabled: !modelData.readOnly
        text: IconFont.iconEdit

        onClicked: {
            root.editRequested(modelData, localParamValue);
        }
    }
}
