import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Ros2

/**
 * Colored pills with the reliability, durability and history of a topic's endpoints, one row per
 * distinct QoS.
 */
ColumnLayout {
    id: root

    //! The endpoints' QoS: objects with the policy enums reliability, durability and history and the history depth.
    property var qos: []

    spacing: 2

    QtObject {
        id: d

        //! One list of {text, color, tooltip} pills per distinct row.
        readonly property var rows: {
            const rows = {};
            for (const q of root.qos) {
                const pills = d.pills(q);
                rows[JSON.stringify(pills)] = pills;
            }
            return Object.values(rows);
        }

        /**
         * Returns the pills of the QoS @p q, leaving out policies without a label.
         */
        function pills(q) {
            const reliability = {
                [ReliabilityPolicy.Reliable]: [qsTr("Reliable"), Material.Green],
                [ReliabilityPolicy.BestEffort]: [qsTr("Best effort"), Material.Orange],
                [ReliabilityPolicy.BestAvailable]: [qsTr("Best available"), Material.Teal],
                [ReliabilityPolicy.SystemDefault]: [qsTr("System default"), Material.Grey],
                [ReliabilityPolicy.Unknown]: [qsTr("Unknown"), Material.Grey]
            }[q.reliability];
            const durability = {
                [DurabilityPolicy.TransientLocal]: [qsTr("Transient local"), Material.Blue],
                [DurabilityPolicy.Volatile]: [qsTr("Volatile"), Material.Grey],
                [DurabilityPolicy.BestAvailable]: [qsTr("Best available"), Material.Teal],
                [DurabilityPolicy.SystemDefault]: [qsTr("System default"), Material.Grey],
                [DurabilityPolicy.Unknown]: [qsTr("Unknown"), Material.Grey]
            }[q.durability];
            const history = {
                [HistoryPolicy.KeepLast]: [qsTr("Keep last %1").arg(q.depth), Material.Cyan],
                [HistoryPolicy.KeepAll]: [qsTr("Keep all"), Material.Purple],
                [HistoryPolicy.SystemDefault]: [qsTr("System default"), Material.Grey]
            }[q.history];
            const pill = (label, tooltip) => label && {
                    "text": label[0],
                    "color": label[1],
                    "tooltip": tooltip
                };
            return [pill(reliability, qsTr("Reliability")), pill(durability, qsTr("Durability")), pill(history, qsTr("History"))].filter(p => p);
        }
    }
    Repeater {
        model: d.rows

        delegate: Flow {
            id: row

            required property var modelData

            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: row.modelData

                delegate: Rectangle {
                    required property var modelData

                    ToolTip.text: modelData.tooltip
                    ToolTip.visible: hover.hovered
                    color: Material.color(modelData.color)
                    implicitHeight: label.implicitHeight + 4
                    implicitWidth: label.implicitWidth + 12
                    radius: height / 2

                    HoverHandler {
                        id: hover
                    }
                    Label {
                        id: label
                        anchors.centerIn: parent
                        // Perceived brightness: black reads better on all but the darkest pill colors.
                        color: 0.299 * parent.color.r + 0.587 * parent.color.g + 0.114 * parent.color.b > 0.4 ? "black" : "white"
                        font.pixelSize: 11
                        text: modelData.text
                    }
                }
            }
        }
    }
}
