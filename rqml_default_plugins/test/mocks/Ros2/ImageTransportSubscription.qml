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
    property bool isColor: false
    property int timeout: 0
    property bool subscribed: true
    property int networkLatency: 0
    property int processingLatency: 0
    property int latency: 0
}
