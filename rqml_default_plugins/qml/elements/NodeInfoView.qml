import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Elements
import RQml.Fonts
import RQml.Utils as Utils

/**
 * Scrollable list of a node's publishers, subscribers, services and actions.
 * Topics show how many endpoints are on the other side, highlight topics without any and list them
 * in a popup on click.
 */
ScrollView {
    id: root

    //! Text shown while info is null.
    property string emptyText

    //! The node as returned by Ros2.getNodeInfo(), or null. Publisher and subscriber entries additionally carry "qos",
    //! the QoS of each of the node's endpoints on the topic, and "peers", one {node, qos} per endpoint on the other side.
    //! Service and action client entries additionally carry "peers", one {node} per server.
    property var info: null

    //! Whether to list the parameter, logger and type description services and the /rosout and /parameter_events
    //! topics every node has.
    property bool showDefaultInterfaces: false

    clip: true
    contentHeight: Math.max(sections.implicitHeight, availableHeight)
    contentWidth: availableWidth

    QtObject {
        id: d

        /**
         * Returns the label for @p count peers of an entry in the section @p key.
         */
        function peerCountText(key, count) {
            if (key === "publishers")
                return count === 0 ? qsTr("No subscribers") : count === 1 ? qsTr("1 subscriber") : qsTr("%1 subscribers").arg(count);
            if (key.endsWith("Clients"))
                return count === 0 ? qsTr("No server") : count === 1 ? qsTr("1 server") : qsTr("%1 servers").arg(count);
            return count === 0 ? qsTr("No publishers") : count === 1 ? qsTr("1 publisher") : qsTr("%1 publishers").arg(count);
        }
    }
    Hint {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.emptyText
        visible: !root.info
        width: parent.width - 16
    }
    ColumnLayout {
        id: sections
        spacing: 0
        visible: !!root.info
        width: root.availableWidth

        Repeater {
            model: [{
                    "key": "publishers",
                    "title": qsTr("Publishers"),
                    "peersTitle": qsTr("Subscribers of %1")
                }, {
                    "key": "subscriptions",
                    "title": qsTr("Subscribers"),
                    "peersTitle": qsTr("Publishers of %1")
                }, {
                    "key": "serviceServers",
                    "title": qsTr("Service Servers")
                }, {
                    "key": "serviceClients",
                    "title": qsTr("Service Clients"),
                    "peersTitle": qsTr("Servers of %1")
                }, {
                    "key": "actionServers",
                    "title": qsTr("Action Servers")
                }, {
                    "key": "actionClients",
                    "title": qsTr("Action Clients"),
                    "peersTitle": qsTr("Servers of %1")
                }]

            delegate: ColumnLayout {
                id: section

                readonly property var entries: {
                    const entries = root.info ? root.info[modelData.key] : [];
                    if (root.showDefaultInterfaces || modelData.key.startsWith("action"))
                        return entries;
                    const isDefault = modelData.key.startsWith("service") ? Utils.InterfaceFilter.isDefaultService : Utils.InterfaceFilter.isDefaultTopic;
                    return entries.filter(e => !isDefault(e.name));
                }
                required property var modelData

                Layout.fillWidth: true
                spacing: 0
                visible: entries.length > 0

                ListHeader {
                    Layout.fillWidth: true
                    text: section.modelData.title + " (" + section.entries.length + ")"
                }
                Repeater {
                    model: section.entries

                    delegate: Rectangle {
                        id: entry

                        required property int index
                        required property var modelData
                        //! A client reaching several servers gets every response, which ROS does not support.
                        readonly property bool multipleServers: section.modelData.key.endsWith("Clients") && peers?.length > 1
                        //! Endpoints on the other side of a topic or the servers of a client, undefined for servers.
                        readonly property var peers: modelData.peers

                        Layout.fillWidth: true
                        color: index % 2 === 0 ? "transparent" : root.palette.alternateBase
                        implicitHeight: entryRow.implicitHeight + 12

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.margins: 2
                            anchors.top: parent.top
                            color: entry.multipleServers ? Material.color(Material.Red) : Material.color(Material.Orange)
                            objectName: "nmUnconnectedMarker"
                            visible: entry.peers?.length === 0 || entry.multipleServers
                            width: 3
                        }
                        RowLayout {
                            id: entryRow
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                TruncatedLabel {
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                    text: entry.modelData.name
                                }
                                Caption {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 8
                                    text: entry.modelData.datatypes.join(", ")
                                }
                                QosPills {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 8
                                    qos: entry.modelData.qos ?? []
                                }
                            }
                            Label {
                                Layout.rightMargin: 8 // aligns with the button's text
                                color: Material.color(Material.Orange)
                                objectName: "nmNoPeersLabel"
                                text: d.peerCountText(section.modelData.key, 0)
                                visible: entry.peers?.length === 0
                            }
                            Label {
                                ToolTip.text: qsTr("%1 servers: each of them executes every request, the client uses the first response.").arg(entry.peers?.length)
                                ToolTip.visible: errorHover.hovered
                                color: Material.color(Material.Red)
                                font.family: IconFont.name
                                objectName: "nmMultipleServersError"
                                text: IconFont.iconError
                                visible: entry.multipleServers

                                HoverHandler {
                                    id: errorHover
                                }
                            }
                            Button {
                                bottomInset: 0
                                flat: true
                                font.capitalization: Font.MixedCase
                                implicitHeight: 32
                                objectName: "nmPeersButton"
                                text: d.peerCountText(section.modelData.key, entry.peers?.length ?? 0)
                                topInset: 0
                                visible: entry.peers?.length > 0

                                onClicked: peerPopup.show(this, section.modelData.peersTitle.arg(entry.modelData.name), entry.peers)
                            }
                        }
                        ContextMenuArea {
                            MenuItem {
                                text: qsTr("Copy Name")

                                onTriggered: RQml.copyTextToClipboard(entry.modelData.name)
                            }
                            MenuItem {
                                text: qsTr("Copy Type")

                                onTriggered: RQml.copyTextToClipboard(entry.modelData.datatypes.join(", "))
                            }
                        }
                    }
                }
            }
        }
    }
    Popup {
        id: peerPopup

        //! The shown peers grouped by node: [{node, qos: [QoS]}], sorted by node.
        property var nodes: []
        property string title

        /**
         * Opens the popup below @p button listing the @p peers with the heading @p title.
         */
        function show(button, title, peers) {
            const byNode = {};
            for (const peer of peers) {
                byNode[peer.node] = byNode[peer.node] ?? [];
                // Servers of a client have no QoS.
                if (peer.qos)
                    byNode[peer.node].push(peer.qos);
            }
            nodes = Object.keys(byNode).sort().map(node => ({
                            "node": node,
                            "qos": byNode[node]
                        }));
            peerPopup.title = title;
            const pos = button.mapToItem(parent, button.width, button.height);
            x = pos.x - width;
            y = pos.y;
            open();
        }

        margins: 8 // keeps the popup inside the window
        objectName: "nmPeerPopup"
        padding: 8
        parent: root
        width: Math.min(360, root.width - 16)

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 4

            TruncatedLabel {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                font.bold: true
                text: peerPopup.title
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 300)
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                model: peerPopup.nodes
                spacing: 6

                ScrollBar.vertical: ScrollBar {
                }
                delegate: ColumnLayout {
                    id: peerNode

                    required property var modelData

                    spacing: 2
                    width: ListView.view.width

                    TruncatedLabel {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: peerNode.modelData.node
                    }
                    QosPills {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        qos: peerNode.modelData.qos
                    }
                }
            }
        }
    }
}
