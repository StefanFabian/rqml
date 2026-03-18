/*
 * Copyright (C) 2025  Stefan Fabian
 *
 * This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import QtTest 1.15
import "../qml" as PluginQml
import Ros2

Item {
    id: windowRoot
    width: 800
    height: 600

    property var context: ({
        service: "",
        type: "",
        request: null,
        showDefaultServices: false
    })

    PluginQml.ServiceCaller {
        id: serviceCaller
        anchors.fill: parent
    }

    TestCase {
        name: "ServiceCallerTest"
        when: windowShown

        function init() {
            Ros2.reset();
            // Set up mock services
            Ros2._mockServices[""] = [
                "/test_service",
                "/another_service",
                "/mock_node/describe_parameters"
            ];
            Ros2._mockTypeMap["/test_service"] = ["std_srvs/srv/SetBool"];
            Ros2._mockTypeMap["/another_service"] = ["std_srvs/srv/Trigger"];
            Ros2._mockServiceResponses["/test_service"] = {
                success: true,
                message: "Mock response"
            };
        }

        function findChildByProperty(parentItem, propName, propValue) {
            if (!parentItem) return null;
            if (parentItem[propName] === propValue) return parentItem;
            var children = parentItem.children || [];
            if (parentItem.contentItem) children = parentItem.contentItem.children;
            for (var i = 0; i < children.length; i++) {
                var found = findChildByProperty(children[i], propName, propValue);
                if (found) return found;
            }
            return null;
        }

        function test_01_plugin_loads() {
            verify(serviceCaller !== null, "ServiceCaller plugin should load");
        }

        function test_02_service_discovery() {
            wait(50);

            // Verify services are available via mock
            var services = Ros2.queryServices();
            compare(services.length, 3, "Should have 3 mock services");
            verify(services.indexOf("/test_service") !== -1, "Should contain /test_service");
        }

        function test_03_type_resolution() {
            var serviceSelector = findChildByProperty(serviceCaller, "placeholderText", "Service Topic");
            verify(serviceSelector !== null, "Service FuzzySelector should be found");
            serviceSelector.text = "/test_service";

            var typeSelector = findChildByProperty(serviceCaller, "placeholderText", "Service Type");
            verify(typeSelector !== null, "Type FuzzySelector should be found");
            tryCompare(typeSelector, "text", "std_srvs/srv/SetBool", 1000,
                "Type should be automatically updated to std_srvs/srv/SetBool");
            compare(windowRoot.context.type, "std_srvs/srv/SetBool", "context.type should be updated");

            // Change to another service
            serviceSelector.text = "/another_service";
            tryCompare(typeSelector, "text", "std_srvs/srv/Trigger", 1000,
                "Type should be automatically updated to std_srvs/srv/Trigger");
            compare(windowRoot.context.type, "std_srvs/srv/Trigger", "context.type should be updated");

            // Clear service
            serviceSelector.text = "";
            tryCompare(typeSelector, "text", "std_srvs/srv/Trigger", 1000,
                "Type should NOT be cleared when service is cleared");
            compare(windowRoot.context.type, "std_srvs/srv/Trigger", "context.type should remain");
        }

        function test_04_default_services_filter() {
            // Find the service FuzzySelector by its placeholderText
            var serviceSelector = findChildByProperty(serviceCaller, "placeholderText", "Service Topic");
            verify(serviceSelector !== null, "Service FuzzySelector should be found");
            verify(serviceSelector.refresh !== undefined, "Service selector should have refresh()");

            // Without default services, describe_parameters should be filtered out
            windowRoot.context.showDefaultServices = false;
            serviceSelector.refresh();
            var filtered = serviceSelector.model;
            for (var i = 0; i < filtered.length; i++) {
                verify(!filtered[i].endsWith("/describe_parameters"),
                    "Default services should be hidden when showDefaultServices is false");
            }

            // With default services shown, describe_parameters should appear
            windowRoot.context.showDefaultServices = true;
            serviceSelector.refresh();
            var all = serviceSelector.model;
            var foundDefault = false;
            for (var j = 0; j < all.length; j++) {
                if (all[j].endsWith("/describe_parameters")) {
                    foundDefault = true;
                    break;
                }
            }
            verify(foundDefault, "Default services should be visible when showDefaultServices is true");
        }

        function test_05_empty_request_creation() {
            context.service = "/test_service";
            context.type = "std_srvs/srv/SetBool";
            wait(100);

            var emptyReq = Ros2.createEmptyServiceRequest("std_srvs/srv/SetBool");
            verify(emptyReq !== null, "Empty request should be created");
            compare(emptyReq["#messageType"], "std_srvs/srv/SetBool_Request", "Type should match");
            compare(emptyReq.data, false, "Default bool should be false");
        }

        function test_06_service_client_creation() {
            // Verify createServiceClient returns a ready client
            var client = Ros2.createServiceClient("/test_service", "std_srvs/srv/SetBool");
            verify(client !== null, "Client should be created");
            verify(client.ready, "Client should be ready");
        }

        function test_07_send_and_receive() {
            windowRoot.context.service = "/test_service";
            windowRoot.context.type = "std_srvs/srv/SetBool";

            var client = Ros2.createServiceClient("/test_service", "std_srvs/srv/SetBool");
            var responseReceived = false;
            var response = null;
            client.sendRequestAsync({ data: true }, function(resp) {
                responseReceived = true;
                response = resp;
            });

            tryVerify(function() { return responseReceived; }, 1000,
                "Response should be received");
            verify(response !== null, "Response should not be null");
            compare(response.success, true, "Response success should be true");
            compare(response.message, "Mock response", "Response message should match");
        }
    }
}
