import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import "../interfaces"
import "../interfaces/GraphModel.js" as GraphModel

/**
 * Graph of the topic, service and action connections between the running nodes. Built when first shown and on Refresh.
 */
ColumnLayout {
    id: root

    //! Emitted when the user asks to inspect a node in the Nodes tab.
    signal inspectNodeRequested(string fullName)

    /**
     * Rebuilds the graph from the current ROS graph.
     */
    function refresh() {
        iface.refresh();
    }

    spacing: 4

    onVisibleChanged: d.buildOnFirstShow()

    QtObject {
        id: d

        property bool built: false

        function buildOnFirstShow() {
            if (!root.visible || built)
                return;
            built = true;
            root.refresh();
        }
    }
    NodeGraphInterface {
        id: iface
        hideCommon: hideCommonCheckBox.checked
        hideHidden: hideHiddenCheckBox.checked
        hideTf: hideTfCheckBox.checked
        showActions: showActionsCheckBox.checked
        showServices: showServicesCheckBox.checked
        showTopics: showTopicsCheckBox.checked
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 4

        SearchBar {
            id: searchBar
            Layout.fillWidth: true
            objectName: "nmGraphSearchBar"
            placeholderText: qsTr("Search nodes...")

            onNextRequested: view.jumpToNextMatch(true)
            onPreviousRequested: view.jumpToNextMatch(false)
        }
        RefreshButton {
            animate: iface.loading
            objectName: "nmGraphRefreshButton"

            onClicked: root.refresh()
        }
    }
    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: 4

        CheckBox {
            id: hideHiddenCheckBox
            checked: context.hideHiddenNodes ?? true
            objectName: "nmGraphHideHiddenCheckBox"
            text: qsTr("Hide hidden nodes")

            onToggled: context.hideHiddenNodes = checked
        }
        CheckBox {
            id: hideCommonCheckBox
            ToolTip.text: qsTr("Hides %1 and the parameter, logger and type description services").arg(GraphModel.COMMON_HUB_TOPICS.join(", "))
            ToolTip.visible: hovered
            checked: context.graphHideCommon ?? true
            objectName: "nmGraphHideCommonCheckBox"
            text: qsTr("Hide common topics")

            onToggled: context.graphHideCommon = checked
        }
        CheckBox {
            id: hideTfCheckBox
            checked: context.graphHideTf ?? true
            objectName: "nmGraphHideTfCheckBox"
            text: qsTr("Hide TF")

            onToggled: context.graphHideTf = checked
        }
        CheckBox {
            id: showTopicsCheckBox
            checked: context.graphShowTopics ?? true
            objectName: "nmGraphShowTopicsCheckBox"
            text: qsTr("Topics")

            onToggled: context.graphShowTopics = checked
        }
        CheckBox {
            id: showServicesCheckBox
            checked: context.graphShowServices ?? false
            objectName: "nmGraphShowServicesCheckBox"
            text: qsTr("Services")

            onToggled: context.graphShowServices = checked
        }
        CheckBox {
            id: showActionsCheckBox
            checked: context.graphShowActions ?? false
            objectName: "nmGraphShowActionsCheckBox"
            text: qsTr("Actions")

            onToggled: context.graphShowActions = checked
        }
        CheckBox {
            id: groupNamespacesCheckBox
            checked: context.graphGroupNamespaces ?? false
            objectName: "nmGraphGroupNamespacesCheckBox"
            text: qsTr("Group by namespace")

            onToggled: context.graphGroupNamespaces = checked
        }
    }
    NodeGraphView {
        id: view
        Layout.fillHeight: true
        Layout.fillWidth: true
        edges: iface.graph.edges
        groupNamespaces: groupNamespacesCheckBox.checked
        hasUnfilteredNodes: iface.hasNodes
        ignoredNodes: context.graphIgnoredNodes ?? []
        loading: iface.loading
        nodes: iface.graph.nodes
        objectName: "nmGraphView"
        searchText: searchBar.text
        unconnected: iface.unconnected

        onIgnoredNodesEdited: context.graphIgnoredNodes = ignoredNodes
        onInspectNodeRequested: id => root.inspectNodeRequested(id)
    }
    Caption {
        Layout.bottomMargin: 4
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: qsTr("Scroll to zoom, drag to pan or move nodes, click a node to highlight its connections, double-click to inspect it, right-click to copy names or ignore nodes.")
    }
}
