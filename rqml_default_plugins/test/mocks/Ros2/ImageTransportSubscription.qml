import QtQuick

QtObject {
    id: root

    property string topic: ""
    property string defaultTransport: "raw"
    property bool enabled: true
    property var videoSink: null
    property string encoding: "rgb8"
    property real framerate: 0.0
    property bool hasAlpha: false
    property bool isColor: true
    property int timeout: 0
}
