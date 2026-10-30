import QtQuick
import Ros2
import RQml.Utils
import "GraphModel.js" as GraphModel

/**
 * Topic, service and action connection graph of the running nodes, see GraphModel.buildGraph().
 */
Object {
    //! Graph {nodes, edges} of the last refresh() with the current filters applied.
    readonly property var graph: GraphModel.buildGraph(d.infos, {
        "hideHidden": hideHidden,
        "hideCommon": hideCommon,
        "hideTf": hideTf,
        "showTopics": showTopics,
        "showServices": showServices,
        "showActions": showActions
    })

    //! Whether the last refresh() found any nodes, including those the filters hide.
    readonly property bool hasNodes: d.infos.length > 0

    //! Hide the topics in GraphModel.COMMON_HUB_TOPICS and the default services.
    property bool hideCommon: true

    //! Hide nodes whose name starts with "_".
    property bool hideHidden: true

    //! Hide TF topics.
    property bool hideTf: true

    //! True from refresh() until the graph is rebuilt.
    readonly property bool loading: buildTimer.running

    //! Add edges from action clients to action servers.
    property bool showActions: false

    //! Add edges from service clients to service servers.
    property bool showServices: false

    //! Add edges from publishers to subscribers.
    property bool showTopics: true

    //! Count of subscriptions without publishers and clients without servers by full node name, as of the last refresh().
    readonly property var unconnected: d.unconnected

    /**
     * Rebuilds the graph from the nodes currently in the ROS graph.
     */
    function refresh() {
        buildTimer.start();
    }

    QtObject {
        id: d

        property var infos: []
        property var unconnected: ({})
    }

    // The queries block the UI thread, so they wait until the busy indicator is painted.
    Timer {
        id: buildTimer

        interval: 50

        onTriggered: {
            const all = Ros2.getAllNodeInfo();
            // RQml's own endpoints still count as counterparts of the others.
            d.unconnected = GraphModel.countUnconnected(all);
            const ownName = Ros2.getName();
            const ownNamespace = Ros2.getNamespace();
            // RQml's own clients and subscriptions would connect it to everything it inspects.
            d.infos = all.filter(node => node.name !== ownName || node.namespace !== ownNamespace);
        }
    }
}
