import QtQuick

QtObject {
    id: root

    property string title: ""
    property string text: ""
    property string informativeText: ""
    property string detailedText: ""
    property int buttons: 0
    property int modality: Qt.NonModal

    // Standard button flag for Ok
    enum StandardButtons { Ok = 0x00000400 }

    signal accepted()
    signal rejected()

    function open() {}
    function close() {}
}
