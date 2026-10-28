import QtQuick
import QtTest
import RQml.Utils

Item {
    TestCase {
        function test_filterServices() {
            const names = ["/arm/_action/send_goal", "/arm/set_parameters", "/arm/reset"];
            compare(InterfaceFilter.filterServices(names, false), ["/arm/reset"]);
            compare(InterfaceFilter.filterServices(names, true), ["/arm/set_parameters", "/arm/reset"]);
        }
        function test_isActionInternal() {
            verify(InterfaceFilter.isActionInternal("/arm/move/_action/feedback"));
            verify(InterfaceFilter.isActionInternal("/arm/move/_action/send_goal"));
            verify(!InterfaceFilter.isActionInternal("/arm/move"));
            verify(!InterfaceFilter.isActionInternal("/arm/_actions"));
        }
        function test_isDefaultService() {
            verify(InterfaceFilter.isDefaultService("/ns/node/get_parameters"));
            verify(InterfaceFilter.isDefaultService("/node/get_type_description"));
            verify(!InterfaceFilter.isDefaultService("/node/get_parameters_custom"));
            verify(!InterfaceFilter.isDefaultService("/node/change_state"));
        }
        function test_isDefaultTopic() {
            verify(InterfaceFilter.isDefaultTopic("/rosout"));
            verify(InterfaceFilter.isDefaultTopic("/parameter_events"));
            verify(!InterfaceFilter.isDefaultTopic("/ns/rosout"));
            verify(!InterfaceFilter.isDefaultTopic("/chatter"));
        }

        name: "InterfaceFilter"
    }
}
