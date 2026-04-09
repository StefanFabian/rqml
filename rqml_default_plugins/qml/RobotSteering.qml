import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts

Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(350, 500)
    color: palette.base

    Component.onCompleted: {
        if (!context.linear)
            context.linear = {};
        if (!context.angular)
            context.angular = {};
    }

    QtObject {
        id: d
        property var publisher: {
            if (!context.topic || !Ros2.isValidTopic(context.topic))
                return null;
            return Ros2.createPublisher(context.topic, context.stamped ? "geometry_msgs/msg/TwistStamped" : "geometry_msgs/msg/Twist", 1);
        }

        function publish() {
            if (!context.enabled || !publisher)
                return;
            if (stampedCheckBox.checked) {
                publisher.publish({
                    header: {
                        stamp: Ros2.now()
                    },
                    twist: {
                        linear: {
                            x: linearSlider.value,
                            y: 0,
                            z: 0
                        },
                        angular: {
                            x: 0,
                            y: 0,
                            z: angularSlider.value
                        }
                    }
                });
            } else {
                publisher.publish({
                    linear: {
                        x: linearSlider.value,
                        y: 0,
                        z: 0
                    },
                    angular: {
                        x: 0,
                        y: 0,
                        z: angularSlider.value
                    }
                });
            }
        }
    }

    Timer {
        interval: rate.value == 0 ? 0 : 1000 / rate.value
        repeat: true
        running: rate.value > 0
        onTriggered: d.publish()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8

        RowLayout {
            FuzzySelector {
                id: topicSelect
                objectName: "steeringTopicSelector"
                Layout.fillWidth: true
                placeholderText: qsTr("Velocity Topic")
                onTextChanged: {
                    if (text === context.topic)
                        return;
                    context.enabled = false;
                    context.topic = text;
                    if (!Ros2.isValidTopic(text))
                        return;
                    const types = Ros2.queryTopicTypes(text);
                    const hasTwist = types.includes("geometry_msgs/msg/Twist");
                    const hasStamped = types.includes("geometry_msgs/msg/TwistStamped");
                    if (hasTwist && !hasStamped)
                        stampedCheckBox.checked = false;
                    else if (hasStamped && !hasTwist)
                        stampedCheckBox.checked = true;
                }
                function refresh() {
                    let topics = Ros2.queryTopics("geometry_msgs/msg/Twist");
                    let stampedTopics = Ros2.queryTopics("geometry_msgs/msg/TwistStamped");
                    topics = topics.concat(stampedTopics);
                    // Deduplicate (a topic could appear in both)
                    topics = [...new Set(topics)];
                    topics.sort();
                    if (!!context.topic) {
                        const index = topics.indexOf(context.topic);
                        if (index !== -1)
                            topics.splice(index, 1);
                        topics.unshift(context.topic);
                    }
                    model = topics;
                }
                Component.onCompleted: {
                    text = context.topic ?? "/cmd_vel";
                    refresh();
                }
            }
            RefreshButton {
                onClicked: {
                    animate = true;
                    topicSelect.refresh();
                    animate = false;
                }
            }
        }

        RowLayout {
            spacing: 10
            CheckBox {
                id: stampedCheckBox
                objectName: "steeringStampedCheckbox"
                display: AbstractButton.TextUnderIcon
                text: "Stamped"
                checked: !!context.stamped
                onCheckedChanged: context.stamped = checked
            }

            Label {
                text: "Rate (Hz):"
            }
            SpinBox {
                id: rate
                objectName: "steeringRateSpinBox"
                editable: true
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: context.rate = value
                Component.onCompleted: value = context.rate ?? 10
            }
            // Spacer
            Item {
                Layout.fillWidth: true
            }
            Button {
                id: playButton
                objectName: "steeringPlayButton"
                implicitHeight: 48
                implicitWidth: 48
                checkable: true
                checked: !!context.enabled
                onCheckedChanged: context.enabled = checked
                ToolTip.visible: hovered
                ToolTip.text: checked ? "Click to pause" : "Click to start"
                ToolTip.delay: 500
                font.family: IconFont.name
                font.pixelSize: 20
                text: checked ? IconFont.iconPause : IconFont.iconPlay
            }
        }

        SpeedSlider {
            id: linearSlider
            objectName: "steeringLinearSlider"
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            enabled: !!context.enabled
            from: context.linear.min ?? -1.0
            onFromChanged: context.linear.min = from
            to: context.linear.max ?? 1.0
            onToChanged: context.linear.max = to
            onValueChanged: {
                if (rate.value == 0)
                    publish();
            }
        }

        SpeedSlider {
            id: angularSlider
            objectName: "steeringAngularSlider"
            Layout.fillWidth: true
            enabled: !!context.enabled
            direction: Qt.Horizontal
            from: context.angular.min ?? -1.0
            onFromChanged: context.angular.min = from
            to: context.angular.max ?? 1.0
            onToChanged: context.angular.max = to
            onValueChanged: {
                if (rate.value == 0)
                    publish();
            }
        }

        Button {
            objectName: "steeringStopButton"
            Layout.fillWidth: true
            text: "Stop"
            onClicked: {
                linearSlider.value = 0;
                angularSlider.value = 0;
            }
        }
    }
}
