import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import "../interfaces/GraphModel.js" as GraphModel

/**
 * Lists the ROS nodes (left) and shows the interfaces of the selected one (right).
 */
SplitView {
    id: root

    /**
     * Re-reads the node list and the selected node's interfaces.
     */
    function refresh() {
        const contentY = nodeList.contentY;
        d.all = Ros2.getAllNodeInfo();
        d.unconnected = GraphModel.countUnconnected(d.all);
        // Only the names, so the list keeps its delegates when just the interfaces of a node change.
        // ROS 2 allows duplicate node names.
        d.nodes = d.all.map(n => ({
                        "name": n.name,
                        "namespace": n.namespace,
                        "fullName": n.fullName
                    })).sort((a, b) => (a.fullName > b.fullName) - (a.fullName < b.fullName)).filter((n, i, all) => i === 0 || n.fullName !== all[i - 1].fullName);
        // A changed node set resets the list to the top; writing an unchanged position would stop a running flick.
        if (nodeList.contentY !== contentY)
            nodeList.contentY = contentY;
        d.updateInfo();
    }

    /**
     * Selects the node @p fullName, shows its interfaces and scrolls it into view. Showing the tab refreshes the list,
     * so show it first to find nodes started while it was hidden.
     */
    function showNode(fullName) {
        d.select(fullName);
        // The filter must not hide the node the user asked for.
        if (d.selectedRow < 0)
            searchBar.clear();
        nodeList.positionViewAtIndex(d.selectedRow, ListView.Contain);
    }

    orientation: Qt.Horizontal

    // The node list only changes with the ROS graph.
    RefreshTrigger {
        active: root.visible
        interval: 500

        onTriggered: root.refresh()
    }
    QtObject {
        id: d

        //! All nodes as returned by Ros2.getAllNodeInfo() in the last refresh().
        property var all: []
        property var info: null
        property var nodes: []
        readonly property int selectedRow: shownNodes.findIndex(n => n.fullName === context.selectedNodeFullName)
        readonly property var shownNodes: nodes.filter(n => !((context.hideHiddenNodes ?? true) && n.name.startsWith("_")) && n.fullName.toLowerCase().includes(searchBar.text))

        //! Count of subscriptions without publishers and clients without servers by full node name.
        property var unconnected: ({})

        /**
         * Returns @p node, an entry of all, with the endpoint QoS and the peers NodeInfoView shows.
         */
        function details(node) {
            const ownQos = endpoints => endpoints.filter(e => e.nodeName === node.name && e.nodeNamespace === node.namespace).map(e => e.qos);
            const peers = endpoints => endpoints.map(e => ({
                                "node": (e.nodeNamespace === "/" ? "/" : e.nodeNamespace + "/") + e.nodeName,
                                "qos": e.qos
                            }));
            const servers = (clients, serverRole) => clients.map(c => Object.assign({}, c, {
                                "peers": all.filter(n => n[serverRole].some(s => s.name === c.name)).map(n => ({
                                                "node": n.fullName
                                            }))
                            }));
            return Object.assign({}, node, {
                    "publishers": node.publishers.map(t => Object.assign({}, t, {
                                    "qos": ownQos(Ros2.getPublishersInfoByTopic(t.name)),
                                    "peers": peers(Ros2.getSubscriptionsInfoByTopic(t.name))
                                })),
                    "subscriptions": node.subscriptions.map(t => Object.assign({}, t, {
                                    "qos": ownQos(Ros2.getSubscriptionsInfoByTopic(t.name)),
                                    "peers": peers(Ros2.getPublishersInfoByTopic(t.name))
                                })),
                    "serviceClients": servers(node.serviceClients, "serviceServers"),
                    "actionClients": servers(node.actionClients, "actionServers")
                });
        }
        function select(fullName) {
            context.selectedNodeFullName = fullName;
            updateInfo();
        }
        function selectRow(row) {
            if (row < 0 || row >= shownNodes.length)
                return;
            select(shownNodes[row].fullName);
            nodeList.positionViewAtIndex(row, ListView.Contain);
        }
        function updateInfo() {
            const node = all.find(n => n.fullName === context.selectedNodeFullName);
            const newInfo = node ? details(node) : null;
            // QoSWrapper values never compare equal, so reassigning equal info would recreate the delegates.
            if (JSON.stringify(newInfo) !== JSON.stringify(info))
                info = newInfo;
        }
    }
    ColumnLayout {
        SplitView.minimumWidth: 160
        SplitView.preferredWidth: 260
        spacing: 4

        SearchBar {
            id: searchBar
            Layout.fillWidth: true
            Layout.margins: 4
            objectName: "nmNodeSearchBar"
            placeholderText: qsTr("Filter nodes...")
            showNavigation: false

            // Commit first so the keys step through the typed filter's rows, not the debounced one's.
            Keys.onDownPressed: {
                searchBar.commitSearchText();
                d.selectRow(d.selectedRow + 1);
            }
            Keys.onUpPressed: {
                searchBar.commitSearchText();
                d.selectRow(d.selectedRow - 1);
            }
            onNextRequested: {
                if (d.selectedRow < 0)
                    d.selectRow(0);
            }
        }
        CheckBox {
            Layout.leftMargin: 4
            checked: context.hideHiddenNodes ?? true
            objectName: "nmHideHiddenCheckBox"
            text: qsTr("Hide hidden nodes")

            onToggled: context.hideHiddenNodes = checked
        }
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: d.shownNodes.length > 0 ? 1 : 0

            Hint {
                horizontalAlignment: Text.AlignHCenter
                objectName: "nmNodeListHint"
                text: d.nodes.length > 0 ? qsTr("No nodes match the filter.") : qsTr("No nodes found. Is ROS running?")
                verticalAlignment: Text.AlignVCenter
            }
            LoadingListView {
                id: nodeList
                model: d.shownNodes
                objectName: "nmNodeList"
                spacing: 2

                delegate: ItemDelegate {
                    id: row

                    required property var modelData
                    readonly property int unconnected: d.unconnected[modelData.fullName] ?? 0

                    highlighted: modelData.fullName === context.selectedNodeFullName
                    text: modelData.fullName
                    width: ListView.view.width

                    contentItem: RowLayout {
                        TruncatedLabel {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: row.text
                            verticalAlignment: Text.AlignVCenter
                        }
                        Label {
                            ToolTip.text: row.unconnected === 1 ? qsTr("1 subscription or client has no publisher or server") : qsTr("%1 subscriptions or clients have no publisher or server").arg(row.unconnected)
                            ToolTip.visible: warningHover.hovered
                            color: Material.color(Material.Orange)
                            font.family: IconFont.name
                            objectName: "nmUnconnectedWarning"
                            text: IconFont.iconWarning
                            visible: row.unconnected > 0

                            HoverHandler {
                                id: warningHover
                            }
                        }
                    }

                    onClicked: d.select(modelData.fullName)

                    ContextMenuArea {
                        MenuItem {
                            text: qsTr("Copy Node Name")

                            onTriggered: RQml.copyTextToClipboard(row.modelData.fullName)
                        }
                    }
                }
            }
        }
    }
    ColumnLayout {
        SplitView.fillWidth: true
        spacing: 0

        Title {
            Layout.fillWidth: true
            Layout.margins: 4
            elide: Text.ElideMiddle
            text: context.selectedNodeFullName ?? ""
        }
        NodeInfoView {
            Layout.fillHeight: true
            Layout.fillWidth: true
            emptyText: context.selectedNodeFullName ? qsTr("Node is no longer available.") : d.nodes.length > 0 ? qsTr("Select a node to view its interfaces.") : ""
            info: d.info
            objectName: "nmNodeInfoView"
            showDefaultInterfaces: context.showDefaultInterfaces ?? false
        }
        CheckBox {
            Layout.leftMargin: 4
            checked: context.showDefaultInterfaces ?? false
            text: qsTr("Show default interfaces")

            onToggled: context.showDefaultInterfaces = checked
        }
    }
}
