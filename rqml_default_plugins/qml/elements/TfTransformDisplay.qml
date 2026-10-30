import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Material
import Ros2
import RQml.Elements
import RQml.Fonts

/**
 * Displays TF transform information between a source and target frame.
 * Used in both the Graph View panel and the List View persistent area.
 */
Rectangle {
    id: root

    property var buffer: null
    property bool expanded: true
    property string sourceFrame: ""
    property string targetFrame: ""

    //! Signal emitted when the user requests swapping source and target
    signal swapRequested

    //! @internal Exposes the TfTransform for test access only. Do not use in production.
    function _testTfTransform() {
        return d.tfTransform;
    }

    border.color: palette.mid
    border.width: 1
    color: palette.window

    // Height grows and shrinks with the animated content wrapper.
    implicitHeight: headerButton.implicitHeight + contentWrapper.height
    radius: 4

    QtObject {
        id: d

        readonly property bool hasFrames: root.sourceFrame !== "" && root.targetFrame !== ""
        property TfTransform tfTransform: TfTransform {
            buffer: root.buffer
            enabled: d.hasFrames && root.expanded && context.enabled
            sourceFrame: root.sourceFrame
            targetFrame: root.targetFrame
        }

        function buildPayload() {
            return {
                "source_frame": root.sourceFrame,
                "target_frame": root.targetFrame,
                "translation": {
                    "x": d.tfTransform.translation.x,
                    "y": d.tfTransform.translation.y,
                    "z": d.tfTransform.translation.z
                },
                "rotation": {
                    "x": d.tfTransform.rotation.x,
                    "y": d.tfTransform.rotation.y,
                    "z": d.tfTransform.rotation.z,
                    "w": d.tfTransform.rotation.w
                }
            };
        }
        function formatNumber(x) {
            return d.hasFrames && d.tfTransform.valid ? x.toFixed(3) : "-";
        }
        function payloadToYaml(p) {
            return "source_frame: " + p.source_frame + "\n" + "target_frame: " + p.target_frame + "\n" + "translation:\n" + "  x: " + p.translation.x + "\n" + "  y: " + p.translation.y + "\n" + "  z: " + p.translation.z + "\n" + "rotation:\n" + "  x: " + p.rotation.x + "\n" + "  y: " + p.rotation.y + "\n" + "  z: " + p.rotation.z + "\n" + "  w: " + p.rotation.w + "\n";
        }
    }

    // -------------------------------------------------------------------------
    // Header / Toggle Button
    // -------------------------------------------------------------------------
    IconTextButton {
        id: headerButton

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        bottomInset: 0
        flat: true
        iconText: root.expanded ? IconFont.iconChevronDown : IconFont.iconChevronRight
        leftInset: 0
        objectName: "tfTransformDisplayHeader"
        rightInset: 0
        text: "Transform"
        topInset: 0

        onClicked: root.expanded = !root.expanded
    }

    // -------------------------------------------------------------------------
    // Animated content area
    // -------------------------------------------------------------------------
    Item {
        id: contentWrapper

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerButton.bottom
        clip: true
        height: root.expanded ? contentCol.implicitHeight : 0

        Behavior on height {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        ColumnLayout {
            id: contentCol

            anchors.left: parent.left
            anchors.margins: 4
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                color: palette.mid
                height: 1
            }

            // Source / Target (shown only when at least one frame is set)
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 8

                GridLayout {
                    Layout.fillWidth: true
                    columnSpacing: 8
                    columns: root.width > 480 ? 4 : 2
                    rowSpacing: 2

                    Label {
                        font.bold: true
                        text: "Source:"
                    }
                    TruncatedLabel {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        font.italic: root.sourceFrame === ""
                        opacity: root.sourceFrame === "" ? 0.5 : 1.0
                        text: root.sourceFrame !== "" ? root.sourceFrame : "(Select frame)"
                    }
                    Label {
                        font.bold: true
                        text: "Target:"
                    }
                    TruncatedLabel {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        font.italic: root.targetFrame === ""
                        opacity: root.targetFrame === "" ? 0.5 : 1.0
                        text: root.targetFrame !== "" ? root.targetFrame : "(Select frame)"
                    }
                }
                IconButton {
                    enabled: d.hasFrames
                    objectName: "tfSwapButton"
                    text: IconFont.iconRightLeft
                    tooltipText: "Swap source and target"

                    onClicked: root.swapRequested()
                }
            }

            // Transform data (always shown, values are "-" when not valid)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 8

                GridLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 360
                    columnSpacing: 12
                    columns: 9
                    rowSpacing: 4

                    // Translation row: icon + x/y/z pairs
                    LetterIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        color: palette.text
                        font.family: IconFont.name
                        font.pixelSize: 10
                        text: "\uf0b2"
                        textColor: palette.mid
                        tooltipText: "Translation"
                    }
                    Label {
                        font.family: "monospace"
                        text: "x:"
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        text: d.formatNumber(d.tfTransform.translation.x)
                    }
                    Label {
                        font.family: "monospace"
                        text: "y:"
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        text: d.formatNumber(d.tfTransform.translation.y)
                    }
                    Label {
                        font.family: "monospace"
                        text: "z:"
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        text: d.formatNumber(d.tfTransform.translation.z)
                    }
                    Item {
                        Layout.columnSpan: 2
                    }

                    // Rotation row: icon + x/y/z/w pairs
                    LetterIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        color: palette.text
                        font.family: IconFont.name
                        font.pixelSize: 10
                        text: "\uf2f1"
                        textColor: palette.mid
                        tooltipText: "Rotation (Quaternion)"
                    }
                    Label {
                        font.family: "monospace"
                        text: "x:"
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        text: d.formatNumber(d.tfTransform.rotation.x)
                    }
                    Label {
                        font.family: "monospace"
                        text: "y:"
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        text: d.formatNumber(d.tfTransform.rotation.y)
                    }
                    Label {
                        font.family: "monospace"
                        text: "z:"
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        text: d.formatNumber(d.tfTransform.rotation.z)
                    }
                    Label {
                        font.family: "monospace"
                        text: "w:"
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        text: d.formatNumber(d.tfTransform.rotation.w)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    IconTextButton {
                        enabled: d.hasFrames && d.tfTransform.valid
                        iconText: IconFont.iconCopy
                        objectName: "tfTransformPopupCopyJson"
                        text: "JSON"
                        tooltipText: "Copy as JSON"

                        onClicked: RQml.copyTextToClipboard(JSON.stringify(d.buildPayload(), null, 2))
                    }
                    IconTextButton {
                        enabled: d.hasFrames && d.tfTransform.valid
                        iconText: IconFont.iconCopy
                        objectName: "tfTransformPopupCopyYaml"
                        text: "YAML"
                        tooltipText: "Copy as YAML"

                        onClicked: RQml.copyTextToClipboard(d.payloadToYaml(d.buildPayload()))
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
            Item {
                Layout.preferredHeight: 4
            }
        }
    }
}
