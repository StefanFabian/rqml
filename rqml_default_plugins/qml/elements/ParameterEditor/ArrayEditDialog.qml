import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import RQml.Fonts
import RQml.Utils
import "../../interfaces"

Dialog {
    id: arrayEditDialog
    title: qsTr("Edit Array Parameter")
    standardButtons: Dialog.Ok | Dialog.Cancel
    width: Math.min(parent.width * 0.8, 600)
    height: Math.min(parent.height * 0.8, 500)
    anchors.centerIn: parent
    modal: true

    property var paramModel: null
    signal parameterSetFailed(string paramName, string reason)

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Label {
            text: arrayEditDialog.paramModel ? arrayEditDialog.paramModel.fullPath : ""
            font.bold: true
            font.family: "Monospace"
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Label {
            text: qsTr("Items: %1").arg(arrayListModel.count)
        }

        ListModel {
            id: arrayListModel
        }

        ListView {
            id: arrayListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: arrayListModel

            ScrollBar.vertical: ScrollBar {
                active: true
            }

            delegate: RowLayout {
                width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)

                Label {
                    text: "[" + index + "]"
                    font.family: "Monospace"
                    Layout.preferredWidth: 50
                }

                TextField {
                    Layout.fillWidth: true
                    text: model.value !== undefined ? String(model.value) : ""
                    selectByMouse: true
                    onEditingFinished: {
                        let pType = arrayEditDialog.paramModel.paramType;
                        let parsed = text;
                        if (pType === ParameterService.typeIntegerArray)
                            parsed = parseInt(text, 10) || 0;
                        else if (pType === ParameterService.typeDoubleArray)
                            parsed = parseFloat(text) || 0.0;
                        else if (pType === ParameterService.typeBoolArray)
                            parsed = (text.toLowerCase() === "true" || text === "1");

                        arrayListModel.setProperty(index, "value", parsed);
                    }
                }

                IconButton {
                    text: IconFont.iconTrash
                    tooltipText: qsTr("Remove Item")
                    onClicked: {
                        arrayListModel.remove(index);
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: qsTr("Add Item")
                onClicked: {
                    arrayListModel.append({
                        "value": ""
                    });
                    arrayListView.positionViewAtEnd();
                }
            }
            Item {
                Layout.fillWidth: true
            }
            Button {
                text: qsTr("Clear All")
                onClicked: {
                    arrayListModel.clear();
                }
            }
        }
    }

    function openDialog(model, arrValue) {
        paramModel = model;
        let tempArray = [];

        let sourceVal = arrValue !== undefined ? arrValue : model.value;
        let javascriptObject = MessageUtils.toJavaScriptObject(sourceVal);

        if (Array.isArray(javascriptObject)) {
            tempArray = javascriptObject;
        } else if (javascriptObject !== null && javascriptObject !== undefined) {
            tempArray = [javascriptObject]; // Fallback
        }

        arrayListModel.clear();
        for (let i = 0; i < tempArray.length; i++) {
            arrayListModel.append({
                "value": tempArray[i]
            });
        }

        open();
    }

    onAccepted: {
        if (!paramModel)
            return;
        let pType = paramModel.paramType;
        let finalArray = [];
        for (let i = 0; i < arrayListModel.count; i++) {
            let itemValue = arrayListModel.get(i).value;
            if (pType === ParameterService.typeIntegerArray)
                finalArray.push(parseInt(itemValue, 10) || 0);
            else if (pType === ParameterService.typeDoubleArray)
                finalArray.push(parseFloat(itemValue) || 0.0);
            else if (pType === ParameterService.typeBoolArray)
                finalArray.push(itemValue === "true" || itemValue === true || itemValue === "1");
            else
                finalArray.push(String(itemValue));
        }

        ParameterService.setParameter(paramModel.nodeName, paramModel.paramName, finalArray, paramModel.paramType, function(success, reason) {
            if (!success) {
                arrayEditDialog.parameterSetFailed(paramModel.paramName, reason);
            }
        });
    }
}
