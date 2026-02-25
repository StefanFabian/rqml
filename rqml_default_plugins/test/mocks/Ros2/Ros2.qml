pragma Singleton
import QtQuick
import MockRos2 1.0

QtObject {
    id: root

    function warn(msg) {
        console.warn("MOCK Ros2 WARNING:", msg)
    }

    property var io: MockRos2IO

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

    property var mockParameters: [
        { name: "mock_group.mock_param_1", type: 4, string_value: "hello mock", description: "Mock string param", read_only: false, floating_point_range: [], integer_range: [] },
        { name: "mock_group.mock_param_2", type: 2, integer_value: 42, description: "Mock int param", read_only: true, floating_point_range: [], integer_range: [{from_value: 0, to_value: 100, step: 1}] },
        { name: "mock_group.mock_param_3", type: 2, integer_value: 10, description: "Mock int min", read_only: false, floating_point_range: [], integer_range: [{from_value: 5, step: 1}] },
        { name: "mock_group.mock_param_4", type: 2, integer_value: 50, description: "Mock int max", read_only: false, floating_point_range: [], integer_range: [{to_value: 100, step: 1}] },
        { name: "mock_group.mock_param_5", type: 3, double_value: 3.14, description: "Mock double param", read_only: false, floating_point_range: [{from_value: 0.0, to_value: 10.0, step: 0.1}], integer_range: [] }
    ]

    function addMockParameter(paramObj) {
        mockParameters.push(paramObj);
    }

    function createServiceClient(topic, type) {
        return {
            sendRequestAsync: function(req, cb) {
                if (topic.endsWith("/list_parameters")) {
                    var names = mockParameters.map(function(p) { return p.name; });
                    cb({ result: { names: withAt(names) } })
                } else if (topic.endsWith("/get_parameters")) {
                    var values = mockParameters.map(function(p) {
                        var v = { type: p.type };
                        if (p.type === 4) v.string_value = p.string_value;
                        if (p.type === 2) v.integer_value = p.integer_value;
                        if (p.type === 3) v.double_value = p.double_value;
                        return v;
                    });
                    cb({ values: withAt(values) })
                } else if (topic.endsWith("/describe_parameters")) {
                    var descriptors = mockParameters.map(function(p) {
                        return {
                            name: p.name,
                            description: p.description,
                            read_only: p.read_only,
                            floating_point_range: withAt(p.floating_point_range),
                            integer_range: withAt(p.integer_range)
                        };
                    });
                    cb({ descriptors: withAt(descriptors) })
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
