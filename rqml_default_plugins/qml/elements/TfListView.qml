import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts

/**
 * Tree-style list view for TF frames.
 * Displays frames in a hierarchical list with frequency, age, and selection indicators.
 */
Item {
    id: root

    //! Shared TfBuffer from the parent plugin
    property var buffer: null

    //! Semantic status colors (set by parent to avoid duplication)
    property color freshColor: Material.color(Material.Green)

    //! Indentation per tree depth level in pixels
    property int indentPerLevel: 16

    //! Search text for filtering frames (lowercase, empty = no filter)
    property string searchText: ""

    //! Currently selected source frame (empty = none)
    property string sourceFrame: ""
    property color staleColor: Material.color(Material.Red)

    //! Age threshold (in seconds) after which a dynamic transform is considered stale
    property real staleThreshold: 5.0
    property color staticColor: Material.color(Material.Blue)

    //! Currently selected target frame (empty = none)
    property string targetFrame: ""

    //! The TfTreeInterface providing frame data
    property var tfInterface: null

    //! Signal emitted when a frame is clicked with modifiers
    signal selectFrame(string frameId, int modifiers)

    //! Signal emitted when the user requests swapping source and target
    signal swapFrames

    /**
     * Jump to the next (or previous) matching frame in the list.
     */
    function jumpToNextMatch(forward) {
        if (root.searchText === "" || !root.tfInterface)
            return;
        const count = root.tfInterface.frames.count;
        if (count === 0)
            return;
        const start = frameListView.currentIndex >= 0 ? frameListView.currentIndex : (forward ? -1 : count);
        for (let step = 1; step <= count; ++step) {
            const idx = forward ? (start + step) % count : (start - step + count) % count;
            const item = root.tfInterface.frames.get(idx);
            if (item.frameId.toLowerCase().indexOf(root.searchText) !== -1) {
                frameListView.currentIndex = idx;
                // positionViewAtIndex must run after the ListView processes the currentIndex change
                Qt.callLater(frameListView.positionViewAtIndex, idx, ListView.Center);
                return;
            }
        }
    }

    QtObject {
        id: d

        function getAgeColor(age) {
            if (age < 0)
                return palette.text;
            if (age < 1)
                return root.freshColor;
            if (age < root.staleThreshold)
                return Material.color(Material.Orange);
            return root.staleColor;
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ListView {
            id: frameListView

            Layout.fillHeight: true
            Layout.fillWidth: true
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400
            clip: true
            currentIndex: -1
            headerPositioning: ListView.OverlayHeader
            highlightFollowsCurrentItem: true
            model: root.tfInterface ? root.tfInterface.frames : null
            objectName: "tfFrameListView"
            reuseItems: true

            ScrollBar.vertical: ScrollBar {
                policy: frameListView.contentHeight > frameListView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }
            delegate: Rectangle {
                id: delegateRoot

                required property int index
                readonly property bool matchesSearch: root.searchText === "" || model.frameId.toLowerCase().indexOf(root.searchText) !== -1
                required property var model

                color: index % 2 === 0 ? palette.base : palette.alternateBase
                height: 36
                opacity: matchesSearch ? 1.0 : 0.3
                width: frameListView.width

                MouseArea {
                    acceptedButtons: Qt.RightButton | Qt.LeftButton
                    anchors.fill: parent

                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            frameListView.currentIndex = index;
                            contextMenu.popup();
                        } else {
                            if (mouse.modifiers === Qt.NoModifier && frameListView.currentIndex === index) {
                                frameListView.currentIndex = -1;
                            } else {
                                frameListView.currentIndex = index;
                                root.selectFrame(model.frameId, mouse.modifiers);
                            }
                        }
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 20
                    spacing: 4

                    // Indentation spacer
                    Item {
                        Layout.preferredWidth: model.depth * root.indentPerLevel
                        visible: model.depth > 0
                    }

                    // Tree branch indicator
                    Label {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 16
                        font.family: IconFont.name
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        text: model.isCollapsed ? IconFont.iconChevronRight : IconFont.iconChevronDown
                        visible: model.hasChildren

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: model.hasChildren ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: model.hasChildren
                            objectName: "tfBranchIndicatorArea"

                            onClicked: root.tfInterface.toggleCollapse(model.frameId)
                        }
                    }

                    // Spacer when no children (keep alignment with siblings that have chevrons)
                    Item {
                        Layout.preferredWidth: 16
                        visible: !model.hasChildren
                    }

                    // Static/dynamic indicator dot
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: 8
                        Layout.preferredWidth: 8
                        ToolTip.text: model.isStatic ? "Static transform" : "Dynamic transform"
                        ToolTip.visible: staticMouseArea.containsMouse
                        color: model.isStatic ? root.staticColor : root.freshColor
                        opacity: model.age >= 0 ? 1 : 0
                        radius: 4

                        MouseArea {
                            id: staticMouseArea

                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }

                    // Frame name - fills all remaining space
                    TruncatedLabel {
                        id: frameNameLabel

                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        text: model.frameId
                    }

                    // Source indicator
                    LetterIndicator {
                        id: sourceIndicator

                        Layout.alignment: Qt.AlignVCenter
                        color: Material.color(Material.Red, Material.Shade400)
                        objectName: "sourceIndicator"
                        text: "S"
                        tooltipText: "Source frame"
                        visible: model.frameId === root.sourceFrame
                    }

                    // Target indicator
                    LetterIndicator {
                        id: targetIndicator

                        Layout.alignment: Qt.AlignVCenter
                        color: Material.color(Material.Red, Material.Shade1000)
                        objectName: "targetIndicator"
                        text: "T"
                        tooltipText: "Target frame"
                        visible: model.frameId === root.targetFrame
                    }

                    // Frequency column
                    Label {
                        Layout.preferredWidth: 80
                        horizontalAlignment: Text.AlignRight
                        text: root.tfInterface ? root.tfInterface.formatFrequency(model.frequency, model.isStatic) : ""
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Age column
                    Label {
                        Layout.preferredWidth: 60
                        color: model.isStatic ? palette.text : d.getAgeColor(model.age)
                        horizontalAlignment: Text.AlignRight
                        text: model.isStatic ? "" : (root.tfInterface ? root.tfInterface.formatAge(model.age) : "")
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Menu {
                    id: contextMenu

                    objectName: "tfContextMenu"

                    MenuItem {
                        objectName: "tfCopyFrameIdAction"
                        text: "Copy Frame ID"

                        onTriggered: RQml.copyTextToClipboard(model.frameId)
                    }
                    MenuItem {
                        enabled: model.parentId !== ""
                        objectName: "tfCopyParentIdAction"
                        text: "Copy Parent ID"

                        onTriggered: RQml.copyTextToClipboard(model.parentId)
                    }
                    MenuSeparator {
                    }
                    MenuItem {
                        enabled: model.age >= 0
                        objectName: "tfCopyTransformAction"
                        text: "Copy Transform"

                        onTriggered: {
                            const tf = "translation: [" + model.translationX + ", " + model.translationY + ", " + model.translationZ + "]\n" + "rotation: [" + model.rotationX + ", " + model.rotationY + ", " + model.rotationZ + ", " + model.rotationW + "]";
                            RQml.copyTextToClipboard(tf);
                        }
                    }
                }
            }
            header: Rectangle {
                color: palette.mid
                height: 32
                width: frameListView.width
                z: 2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 20
                    spacing: 0

                    Label {
                        Layout.fillWidth: true
                        font.bold: true
                        height: parent.height
                        text: "Frame"
                        verticalAlignment: Text.AlignVCenter
                    }
                    Label {
                        Layout.preferredWidth: 80
                        font.bold: true
                        height: parent.height
                        horizontalAlignment: Text.AlignRight
                        text: "Freq"
                        verticalAlignment: Text.AlignVCenter
                    }
                    Label {
                        Layout.preferredWidth: 60
                        font.bold: true
                        height: parent.height
                        horizontalAlignment: Text.AlignRight
                        text: "Age"
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            highlight: Rectangle {
                color: palette.highlight
                opacity: 0.2
            }

            // Empty state
            Label {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                objectName: "tfEmptyStateLabel"
                text: {
                    if (!root.tfInterface)
                        return "No TF interface";
                    return root.tfInterface.enabled ? "Waiting for TF data..." : "Paused";
                }
                visible: root.tfInterface ? root.tfInterface.frameCount === 0 : true
            }
        }
        TfTransformDisplay {
            id: transformDisplay

            Layout.fillWidth: true
            buffer: root.buffer
            expanded: context.listTransformOpen ?? true
            objectName: "tfListTransformDisplay"
            sourceFrame: root.sourceFrame
            targetFrame: root.targetFrame

            onExpandedChanged: {
                if (context.listTransformOpen !== expanded)
                    context.listTransformOpen = expanded;
            }
            onSwapRequested: root.swapFrames()
        }
    }
}
