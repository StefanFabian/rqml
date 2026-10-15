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

    property var context: contextObj
    property var plugin: pluginLoader.item

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 768
    width: 1024

    QtObject {
        id: contextObj

        property var request: null
        property string service: ""
        property bool showDefaultServices: false
        property string type: ""
    }
    Utils {
        id: helpers
    }
    Loader {
        id: pluginLoader
        function reload() {
            source = "";
            source = "../qml/ServiceCaller.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        id: testCase
        function init() {
            Ros2.reset();
            contextObj.service = "";
            contextObj.type = "";
            contextObj.request = null;

            // Register a mock service
            Ros2.registerService("/test_service", "std_srvs/srv/SetBool", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("std_srvs/srv/SetBool");
                    resp.success = req.data;
                    resp.message = "Called with " + req.data;
                    return resp;
                });
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                });

            // Wait for service to be discovered
            tryVerify(function () {
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
            tryVerify(function () {
                    return contextObj.service === "/test_service";
                }, 5000, "Service selection failed");

            // Type should be auto-filled
            var typeSelector = find("serviceTypeSelector");
            tryVerify(function () {
                    return typeSelector.text === "std_srvs/srv/SetBool";
                }, 5000, "Service type auto-fill failed. Actual: " + typeSelector.text);
            compare(contextObj.type, "std_srvs/srv/SetBool");
        }
        function test_enter_sends() {
            Ros2.registerService("/test_service", "std_srvs/srv/SetBool", function (req) {
                    return {
                        "success": true,
                        "message": ""
                    };
                });
            contextObj.service = "/test_service";
            contextObj.type = "std_srvs/srv/SetBool";
            contextObj.request = Ros2.createEmptyServiceRequest("std_srvs/srv/SetBool");
            var sendButton = find("serviceSendButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            // Return in a request field (see tst_MessageContentEditor) sends.
            find("serviceRequestEditor").submitted();
            tryCompare(find("serviceTabBar"), "currentIndex", 1, 5000);
            verify(find("serviceHoldDropButton").activeFocus, "Hold to drop button should take focus after sending");
            tryVerify(function () {
                    return sendButton.activeFocus;
                }, 2000, "Back button should take focus from Hold to drop once the response arrives");
            compare(sendButton.text, "Back");
        }
        function test_hold_to_drop_hung_request() {
            var requestCount = 0;
            Ros2.registerService("/hang_service", "std_srvs/srv/SetBool", function (req) {
                    requestCount++;
                    return {
                        "#hang": true
                    };
                });
            contextObj.service = "/hang_service";
            contextObj.type = "std_srvs/srv/SetBool";
            contextObj.request = Ros2.createEmptyServiceRequest("std_srvs/srv/SetBool");
            var sendButton = find("serviceSendButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);

            // The call hangs: status stays waiting and the hold-to-drop escape
            // hatch replaces Send, also on the request tab.
            var statusLabel = find("serviceStatusLabel");
            tryCompare(statusLabel, "text", "Waiting for response...", 2000);
            var holdButton = find("serviceHoldDropButton");
            verify(holdButton);
            tryVerify(function () {
                    return holdButton.visible && !sendButton.visible;
                }, 2000);
            var tabBar = find("serviceTabBar");
            tabBar.currentIndex = 0;
            verify(holdButton.visible, "Hold to drop should stay reachable from the request tab");

            // A tap must not drop; only a full hold does.
            holdButton.holdDuration = 120;
            mouseClick(holdButton);
            wait(holdButton.holdDuration * 2);
            verify(holdButton.visible);

            // Holding past holdDuration drops the request and returns to the
            // request tab, ready to send again, with the focus on Send.
            // Let the key guard armed by the earlier click expire.
            wait(600);
            holdButton.forceActiveFocus();
            mousePress(holdButton);
            tryVerify(function () {
                    return !holdButton.visible;
                }, 2000);
            mouseRelease(holdButton);
            tryCompare(tabBar, "currentIndex", 0, 2000);
            tryVerify(function () {
                    return sendButton.visible && sendButton.enabled;
                }, 2000);
            verify(sendButton.activeFocus, "Send should take focus from Hold to drop after dropping");

            // A key still held from the drop must not re-send on the focused Send.
            var sentBefore = requestCount;
            keyClick(Qt.Key_Space);
            wait(50);
            compare(requestCount, sentBefore, "Space right after dropping must not re-send the request");
        }
        function test_reset() {
            contextObj.service = "/test_service";
            contextObj.type = "std_srvs/srv/SetBool";
            contextObj.request = Ros2.createEmptyServiceRequest("std_srvs/srv/SetBool");
            contextObj.request.data = true;
            var resetButton = find("serviceResetButton");
            verify(resetButton !== null);
            mouseClick(resetButton);
            tryVerify(function () {
                    // createdEmptyServiceRequest should have data: false by default
                    return contextObj.request.data === false;
                }, 5000, "Reset failed to clear request data");
        }
        function test_service_call() {
            // Set up state directly to ensure we are testing the call logic
            contextObj.service = "/test_service";
            contextObj.type = "std_srvs/srv/SetBool";
            contextObj.request = Ros2.createEmptyServiceRequest("std_srvs/srv/SetBool");
            contextObj.request.data = true;
            var sendButton = find("serviceSendButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);

            // Should switch to response tab
            var tabBar = find("serviceTabBar");
            tryCompare(tabBar, "currentIndex", 1, 5000);

            // Verify status label
            var statusLabel = find("serviceStatusLabel");
            tryCompare(statusLabel, "text", "Ready", 5000);
        }

        name: "ServiceCallerTest"
        when: windowShown
    }
}
