import QtQuick

QtObject {
    id: root

    property string topic: ""
    property string messageType: ""
    property int queueSize: 10
    property int throttleRate: 0
    property bool enabled: true
    property var qos: null
    property var message: null

    signal newMessage(var message)

    function injectMessage(msg) {
        var wrapped = Ros2.wrapCppMessage(msg);
        root.message = wrapped;
        root.newMessage(wrapped);
    }

    Component.onCompleted: Ros2._registerSubscription(root)
    Component.onDestruction: Ros2._unregisterSubscription(root)
}
