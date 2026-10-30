import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2

Rectangle {
    id: root

    // Set the minimum size for this plugin's dock widget
    property var kddockwidgets_min_size: Qt.size(300, 300)
    property string lastMessage: "No message received yet"

    color: palette.base

    Subscription {
        id: chatterSub

        topic: "/chatter"

        onNewMessage: msg => {
            lastMessage = msg.data;
        }
    }
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 20

        // Use Label instead of Text for better styling and support of different themes
        Label {
            Layout.alignment: Qt.AlignHCenter
            font.bold: true
            font.pixelSize: 24
            text: "ROS 2 Example Plugin"
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            font.pixelSize: 16
            text: "Listening on: " + chatterSub.topic
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            color: "green"
            font.pixelSize: 18
            text: lastMessage
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Publish Hello"

            onClicked: {
                // Simple publisher example
                let msg = Ros2.createEmptyMessage("std_msgs/msg/String");
                msg.data = "Hello from RQml!";
                d.pub.publish(msg);
            }
        }
    }

    // I like using a private object for internal logic and properties
    QtObject {
        id: d

        property var pub: Ros2.createPublisher("/chatter", "std_msgs/msg/String")
    }
}
