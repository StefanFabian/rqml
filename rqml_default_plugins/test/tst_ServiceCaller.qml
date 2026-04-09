/*
 * Copyright (C) 2025  Stefan Fabian
 *
 * This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
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

import QtQuick
import QtQuick.Controls
import QtTest
import Ros2

Item {
    id: root
    width: 1024; height: 768

    property var context: contextObj
    QtObject {
        id: contextObj
        property string service: ""
        property string type: ""
        property var request: null
        property bool showDefaultServices: false
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/ServiceCaller.qml"; }
    }

    property var plugin: pluginLoader.item

    function find(name) { return helpers.findChild(root, name); }

    TestCase {
        id: testCase
        name: "ServiceCallerTest"
        when: windowShown

        function init() {
            Ros2.reset();
            contextObj.service = "";
            contextObj.type = "";
            contextObj.request = null;

            // Register a mock service
            Ros2.registerService("/test_service", "std_srvs/srv/SetBool", function(req) {
                var resp = Ros2.createEmptyServiceResponse("std_srvs/srv/SetBool");
                resp.success = req.data;
                resp.message = "Called with " + req.data;
                return resp;
            });

            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; });

            // Wait for service to be discovered
            tryVerify(function() {
                var selector = find("serviceTopicSelector");
                return selector && (selector.model || []).indexOf("/test_service") !== -1;
            }, 5000, "Discovery timed out");
        }

        function test_discovery() {
            var topicSelector = find("serviceTopicSelector");
            verify(topicSelector !== null);

            // Select it by typing the full name to be safe
            mouseClick(topicSelector);
            var fullName = "/test_service";
            for (var i = 0; i < fullName.length; ++i) {
                keyClick(fullName[i]);
            }
            keyClick(Qt.Key_Enter);

            tryVerify(function() { return contextObj.service === "/test_service"; }, 5000, "Service selection failed");

            // Type should be auto-filled
            var typeSelector = find("serviceTypeSelector");
            tryVerify(function() {
                return typeSelector.text === "std_srvs/srv/SetBool";
            }, 5000, "Service type auto-fill failed. Actual: " + typeSelector.text);
            compare(contextObj.type, "std_srvs/srv/SetBool");
        }

        function test_service_call() {
            // Set up state directly to ensure we are testing the call logic
            contextObj.service = "/test_service";
            contextObj.type = "std_srvs/srv/SetBool";
            contextObj.request = Ros2.createEmptyServiceRequest("std_srvs/srv/SetBool");
            contextObj.request.data = true;

            var sendButton = find("serviceSendButton");
            tryVerify(function() { return sendButton.enabled; }, 5000);

            mouseClick(sendButton);

            // Should switch to response tab
            var tabBar = find("serviceTabBar");
            tryCompare(tabBar, "currentIndex", 1, 5000);

            // Verify status label
            var statusLabel = find("serviceStatusLabel");
            tryCompare(statusLabel, "text", "Ready", 5000);
        }

        function test_reset() {
            contextObj.service = "/test_service";
            contextObj.type = "std_srvs/srv/SetBool";
            contextObj.request = Ros2.createEmptyServiceRequest("std_srvs/srv/SetBool");
            contextObj.request.data = true;

            var resetButton = find("serviceResetButton");
            verify(resetButton !== null);
            mouseClick(resetButton);

            tryVerify(function() {
                // createdEmptyServiceRequest should have data: false by default
                return contextObj.request.data === false;
            }, 5000, "Reset failed to clear request data");
        }
    }
}
