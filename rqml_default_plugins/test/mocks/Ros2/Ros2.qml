pragma Singleton
import QtQuick

QtObject {
    id: root

    function warn(msg) {
        console.warn("MOCK Ros2 WARNING:", msg)
    }

    function queryServices(srvName) {
        if (srvName === "rcl_interfaces/srv/ListParameters") {
            return ["/mock_node/list_parameters"]
        }
        return []
    }

    function withAt(arr) {
        arr.at = function(i) { return this[i]; }
        return arr;
    }

    function createServiceClient(topic, type) {
        return {
            sendRequestAsync: function(req, cb) {
                if (topic.endsWith("/list_parameters")) {
                    cb({ result: { names: withAt(["mock_group.mock_param_1", "mock_group.mock_param_2"]) } })
                } else if (topic.endsWith("/get_parameters")) {
                    cb({
                        values: withAt([
                            { type: 4, string_value: "hello mock" },
                            { type: 2, integer_value: 42 }
                        ])
                    })
                } else if (topic.endsWith("/describe_parameters")) {
                    cb({
                        descriptors: withAt([
                            { name: "mock_group.mock_param_1", description: "Mock string param", read_only: false, floating_point_range: [], integer_range: [] },
                            { name: "mock_group.mock_param_2", description: "Mock int param", read_only: true, floating_point_range: withAt([]), integer_range: withAt([{from_value: 0, to_value: 100, step: 1}]) }
                        ])
                    })
                } else if (topic.endsWith("/set_parameters")) {
                    console.log("MOCK SET PARAMETERS CALLED:", JSON.stringify(req));
                    cb({
                        results: withAt([{ successful: true }])
                    })
                }
            }
        }
    }
}
