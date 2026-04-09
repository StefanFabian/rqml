import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import Ros2
import RQml.DefaultPlugins
import RQml.Elements
import RQml.Fonts

Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(600, 500)
    color: palette.base

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8

        RowLayout {
            FuzzySelector {
                id: topicSelect
                objectName: "imageTopicSelector"
                Layout.fillWidth: true
                placeholderText: qsTr("Image Topic")
                text: context.topic ?? ""
                onTextChanged: {
                    if (text === context.topic)
                        return;
                    context.topic = text;
                }
                function refresh() {
                    let topics = Ros2.queryTopics("sensor_msgs/msg/Image");
                    let compressedTopics = Ros2.queryTopics("sensor_msgs/msg/CompressedImage");
                    topics = topics.concat(compressedTopics);
                    topics.sort();
                    if (!!context.topic) {
                        const index = topics.indexOf(context.topic);
                        if (index != -1)
                            topics.splice(index, 1);
                        topics.unshift(context.topic);
                    }
                    model = topics;
                }
                Component.onCompleted: refresh()
            }
            RefreshButton {
                id: refreshButton
                onClicked: {
                    animate = true;
                    topicSelect.refresh();
                    animate = false;
                }
            }
            IconToggleButton {
                id: playButton
                objectName: "imagePlayButton"
                checked: context.enabled ?? true
                onToggled: {
                    if (context.enabled === checked)
                        return;
                    context.enabled = checked;
                }
                iconOn: IconFont.iconPause
                iconOff: IconFont.iconPlay
                tooltipTextOn: qsTr("Click to pause")
                tooltipTextOff: qsTr("Click to start")
            }
            IconButton {
                id: saveButton
                objectName: "imageSaveButton"
                tooltipText: qsTr("Save Image")
                text: IconFont.iconSave
                onClicked: fileDialog.saveImage()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            RowLayout {
                visible: !imageSubscriber.isColor
                CheckBox {
                    objectName: "imageInvertCheckbox"
                    text: qsTr("Invert")
                    checked: context.invert ?? false
                    onToggled: {
                        context.invert = checked;
                    }
                }
                CheckBox {
                    objectName: "imageColorizeCheckbox"
                    text: qsTr("Colorize")
                    checked: context.colorize ?? false
                    onToggled: {
                        context.colorize = checked;
                    }
                }
                DecimalSpinBox {
                    objectName: "imageDepthSpinBox"
                    visible: d.isDepthCamera(imageSubscriber.encoding)
                    implicitWidth: 132
                    from: 0.0
                    to: 999
                    suffix: "m"
                    onValueChanged: {
                        if (context.depth === value)
                            return;
                        context.depth = value;
                    }
                    Component.onCompleted: value = context.depth ?? 3.0
                }
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                objectName: "imageRotateLeftButton"
                text: IconFont.iconRotateLeft
                tooltipText: qsTr("Rotate Left")
                onClicked: context.rotation = ((context.rotation ?? 0) - 90 + 360) % 360
            }
            Label {
                objectName: "imageRotationLabel"
                Layout.preferredWidth: 48
                text: (context.rotation ?? 0) + "°"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            IconButton {
                objectName: "imageRotateRightButton"
                text: IconFont.iconRotateRight
                tooltipText: qsTr("Rotate Right")
                onClicked: context.rotation = ((context.rotation ?? 0) + 90) % 360
            }
        }

        VideoOutput {
            id: videoOutput
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: context.rotation ?? 0

            layer.enabled: {
                if (imageSubscriber.hasAlpha)
                    return true;
                if (imageSubscriber.isColor)
                    return false;
                if (imageSubscriber.encoding === "32FC1" || imageSubscriber.encoding === "16UC1")
                    return true;
                if (imageSubscriber.encoding === "mono16")
                    return true;
                return false;
            }
            layer.effect: ShaderEffect {
                property rect cRect: videoOutput.contentRect
                property int flags: {
                    let f = 0;
                    if (context.invert ?? false)
                        f |= 1;
                    if (context.colorize ?? false)
                        f |= 2;
                    return f;
                }
                property var colormap: Image {
                    source: "shaders/turbo.png"
                }

                // Calculate normalized min/max (0.0 - 1.0)
                property real xMin: videoOutput.width > 0 ? cRect.x / videoOutput.width : 0.0
                property real xMax: videoOutput.width > 0 ? (cRect.x + cRect.width) / videoOutput.width : 1.0
                property real yMin: videoOutput.height > 0 ? cRect.y / videoOutput.height : 0.0
                property real yMax: videoOutput.height > 0 ? (cRect.y + cRect.height) / videoOutput.height : 1.0

                fragmentShader: {
                    if (imageSubscriber.hasAlpha)
                        return "shaders/transparency.frag.qsb";
                    if (!imageSubscriber.isColor)
                        return "shaders/depthimage.frag.qsb";
                    return "";
                }
            }
            smooth: false

            // Processes depth images, forwards all other images unchanged
            DepthImageProcessor {
                id: depthProcessor
                maxDepth: context.depth ?? 3.0
                outputVideoSink: videoOutput.videoSink
            }

            ImageTransportSubscription {
                id: imageSubscriber
                topic: d.topicInformation?.topic ?? ""
                defaultTransport: d.topicInformation?.transport ?? "raw"
                enabled: context.enabled ?? true
                videoSink: depthProcessor.videoSink
                timeout: 3000
            }
        }

        // Video Info
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Label {
                text: "Resolution: " + videoOutput.sourceRect.width + "x" + videoOutput.sourceRect.height
            }
            Label {
                text: "FPS: " + imageSubscriber.framerate.toFixed(1)
            }
            Item {
                Layout.fillWidth: true
            }
            Label {
                text: "Encoding: " + imageSubscriber.encoding
            }
        }
    }

    QtObject {
        id: d
        property int _recheckTrigger: 0
        property var topicInformation: {
            _recheckTrigger;
            if (!context.topic || !Ros2.isValidTopic(context.topic))
                return {};
            const types = Ros2.queryTopicTypes(context.topic);
            if (types.length == 0)
                return {};
            const isRaw = types.indexOf("sensor_msgs/msg/Image") != -1 || context.topic.endsWith("/image_raw");
            if (isRaw) {
                return {
                    topic: context.topic,
                    transport: "raw"
                }
            }
            const parts = context.topic.split("/");
            if (parts.length < 2)
                return {topic: context.topic, transport: "raw"};
            const topic = parts.slice(0, parts.length - 1).join("/");
            const transport = parts[parts.length - 1];
            return {
                topic: topic,
                transport: transport
            };
        }

        function isDepthCamera(encoding) {
            return encoding === "32FC1" || encoding === "16UC1" || encoding === "mono16";
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: imageSubscriber.enabled && !imageSubscriber.subscribed
        onTriggered: {
            d._recheckTrigger++;
        }
    }

    FileDialog {
        id: fileDialog
        objectName: "imageSaveFileDialog"
        title: qsTr("Save Image")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "png"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.bmp)"]
        onAccepted: {
            let path = fileDialog.selectedFile.toString();
            if (path.startsWith("file://"))
                path = path.slice(7);
            depthProcessor.saveGrabbedFrame(path);
            depthProcessor.clearGrabbedFrame();
        }
        onRejected: {
            depthProcessor.clearGrabbedFrame();
        }

        function saveImage() {
            depthProcessor.grabFrame();
            open();
        }
    }
}
