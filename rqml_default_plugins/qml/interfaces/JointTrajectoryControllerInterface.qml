import QtQuick
import QtQuick.Dialogs
import Ros2
import RQml.Utils
import "."

Object {
    id: root

    property string controllerManager
    property string controllerName
    property bool controllerReady: d.trajectoryClient && d.trajectoryClient.ready
    property var controllers: ListModel {
    }
    property bool hasRobotDescription: false
    property bool isGoalActive: false
    property var joints: ListModel {
    }
    //! If true, continuous joints always take the shortest path to the goal angle
    property bool takeShortestPath: false

    function cancelGoals() {
        if (!d.trajectoryClient || !d.trajectoryClient.ready) {
            Ros2.warn("Action server not connected");
            return;
        }
        d.trajectoryClient.cancelAllGoals();
    }
    function getJoint(jointName) {
        for (let i = 0; i < root.joints.count; i++) {
            let joint = root.joints.get(i);
            if (joint.name === jointName)
                return joint;
        }
        return null;
    }
    function loadControllers() {
        if (!root.controllerManager)
            return;
        if (!d.listControllersClient || d.listControllersClient.pendingRequests > 0)
            return; // Already requesting
        Ros2.debug("JointTrajectoryController: Loading controllers from " + root.controllerManager);
        d.listControllersClient.sendRequestAsync({}, function (response) {
            if (!response) {
                Ros2.warn("JointTrajectoryController: Failed to get controllers from " + root.controllerManager + ". Trying again.");
                root.loadControllers();
                return;
            }
            Ros2.debug("JointTrajectoryController: Received " + response.controller.length + " controllers from " + root.controllerManager);
            controllers.clear();
            for (let i = 0; i < response.controller.length; i++) {
                let controller = response.controller.at(i);
                if (!controller)
                    continue;
                if (controller.type !== "joint_trajectory_controller/JointTrajectoryController" || controller.state !== "active")
                    continue;
                controllers.append({
                    "name": controller.name,
                    "controller": controller
                });
            }
        });
    }
    function refresh() {
        root.loadControllers();
    }
    function resetGoals() {
        for (let i = 0; i < root.joints.count; ++i) {
            let joint = root.joints.get(i);
            joint.goal = joint.position;
        }
    }

    //! Send a goal to move all joints to their goal positions with the given speed (in rad/s)
    function sendGoals(speed) {
        if (!d.trajectoryClient || !d.trajectoryClient.ready) {
            Ros2.warn("Action server not connected");
            return;
        }
        let msg = Ros2.createEmptyActionGoal("control_msgs/action/FollowJointTrajectory");
        let goal = {
            "positions": []
        };
        let maxDiff = 0;
        for (let i = 0; i < root.joints.count; i++) {
            let joint = root.joints.get(i);
            if (!joint || !joint.active)
                continue;
            msg.trajectory.joint_names.push(joint.name);
            goal.positions.push(joint.goal);
            let diff = Math.abs(joint.goal - joint.position);
            if (root.takeShortestPath && joint.type == "continuous")
                diff = Math.min(diff, 2 * Math.PI - diff);
            maxDiff = Math.max(maxDiff, diff);
        }
        const duration = Math.max(0.1, maxDiff / speed);
        goal.time_from_start = {
            "sec": Math.floor(duration),
            "nanosec": Math.floor((duration % 1) * 1e9)
        };
        msg.trajectory.points.push(goal);
        Ros2.debug("JointTrajectoryController: Sending goal to action server with duration " + duration + "s. Positions: " + goal.positions);
        root.isGoalActive = true;
        d.trajectoryClient.sendGoalAsync(msg, {
            "onGoalResponse": function (goal_handle) {
                if (!goal_handle) {
                    Ros2.warn("JointTrajectoryController: Goal rejected by action server");
                    root.isGoalActive = false;
                    return;
                }
            },
            "onResult": function (result) {
                root.isGoalActive = false;
                Ros2.debug("JointTrajectoryController: Goal completed with code: " + result.code);
                if (result.code !== ActionResultCode.SUCCEEDED) {
                    errorDialog.text = "Goal failed with code: " + result.code;
                    errorDialog.informativeText = result.result.error_string || "";
                    errorDialog.open();
                }
            }
        });
    }

    onControllerManagerChanged: {
        root.refresh();
    }

    MessageDialog {
        id: errorDialog

        buttons: MessageDialog.Ok
        modality: Qt.WindowModal
    }
    Subscription {
        id: jointStateSubscription

        messageType: "sensor_msgs/msg/JointState"
        throttleRate: 5
        topic: d.findBestMatch("/joint_states", "sensor_msgs/msg/JointState")

        onNewMessage: msg => {
            for (let i = 0; i < msg.name.length; i++) {
                const name = msg.name.at(i);
                let joint = getJoint(name);
                if (!joint) {
                    continue;
                }
                let position = msg.position.at(i);
                if (joint.type == "continuous") {
                    position = (position + Math.PI) % (2 * Math.PI) - Math.PI; // Normalize to [-pi, pi]
                }
                position = Math.round(position * 100) / 100 || 0.0;
                joint.position = position;
                if (!joint.initialized) {
                    joint.goal = position;
                    joint.initialized = true;
                }
            }
        }
    }
    Subscription {
        id: urdfSubscription

        messageType: "std_msgs/msg/String"
        qos: Ros2.QoS().transient_local().reliable()
        topic: d.findBestMatch("/robot_description", "std_msgs/msg/String")

        onNewMessage: msg => {
            if (!msg.data)
                return;
            Ros2.debug("Received URDF description. Parsing...");
            parser.parseURDF(msg.data);
        }
    }
    Timer {
        interval: 500
        repeat: true
        running: true

        onTriggered: {
            const jointStateTopic = d.findBestMatch("/joint_states", "sensor_msgs/msg/JointState");
            if (jointStateSubscription.topic !== jointStateTopic) {
                jointStateSubscription.topic = jointStateTopic;
            }
            const urdfTopic = d.findBestMatch("/robot_description", "std_msgs/msg/String");
            if (urdfTopic && urdfTopic !== urdfSubscription.topic) {
                root.joints.clear();
                root.hasRobotDescription = false;
                urdfSubscription.topic = urdfTopic;
            }
        }
    }
    QtObject {
        id: d

        property var controller: {
            if (!root.controllerName)
                return null;
            for (let i = 0; i < root.controllers.count; i++) {
                let c = root.controllers.get(i);
                if (c.name === root.controllerName)
                    return c.controller;
            }
            return null;
        }
        property var listControllersClient: {
            if (!root.controllerManager)
                return null;
            return Ros2.createServiceClient(root.controllerManager + "/list_controllers", "controller_manager_msgs/srv/ListControllers");
        }
        property var trajectoryClient: {
            if (!root.controllerManager || !d.controller)
                return null;
            const parts = root.controllerManager.split("/");
            parts.pop();
            const ns = parts.join("/");
            const actionName = ns + "/" + d.controller.name + "/follow_joint_trajectory";
            Ros2.debug("JointTrajectoryController: Creating action client for " + actionName);
            return Ros2.createActionClient(actionName, "control_msgs/action/FollowJointTrajectory");
        }

        function addJoint(joint) {
            for (let i = 0; i < root.joints.count; i++) {
                let j = root.joints.get(i);
                if (j.name !== joint.name)
                    continue;
                // Update existing joint
                if (joint.position !== undefined)
                    j.position = joint.position;
                if (joint.goal !== undefined)
                    j.goal = joint.goal;
                if (joint.limits !== undefined)
                    j.limits = joint.limits;
                if (joint.type !== undefined)
                    j.type = joint.type;
                return;
            }
            if (!joint.position)
                joint.position = 0.0;
            if (!joint.goal)
                joint.goal = joint.position;
            if (!joint.limits)
                joint.limits = {
                    "upper": Math.PI,
                    "lower": -Math.PI
                };
            if (!joint.type)
                joint.type = "unknown";
            joint.initialized = false;
            joint.active = false;
            if (d.controller) {
                for (let i = 0; i < d.controller.claimed_interfaces.length; i++) {
                    let name = d.extractJointName(d.controller.claimed_interfaces.at(i));
                    if (name === joint.name) {
                        joint.active = true;
                        break;
                    }
                }
            }
            // Insert joint in sorted order
            let i = 0;
            for (; i < root.joints.count; i++) {
                let j = root.joints.get(i);
                if (j.name > joint.name)
                    break;
            }
            root.joints.insert(i, joint);
        }
        function extractJointName(claimedInterface) {
            const parts = claimedInterface.split("/");
            return parts.length >= 2 ? parts[parts.length - 2] : parts[0];
        }
        function findBestMatch(topic, messageType) {
            if (!root.controllerManager)
                return "";
            const topics = Ros2.queryTopics(messageType);
            const controllerManagerParts = root.controllerManager.split("/");
            let length = 0;
            let best_match = "";
            for (let i = 0; i < topics.length; i++) {
                if (!topics[i].endsWith(topic))
                    continue;
                const parts = topics[i].split("/");
                let match_length = 0;
                for (let j = 0; j < Math.min(parts.length, controllerManagerParts.length); j++) {
                    if (parts[j] !== controllerManagerParts[j])
                        break;
                    match_length++;
                }
                if (match_length > length) {
                    length = match_length;
                    best_match = topics[i];
                }
            }
            return best_match;
        }

        onControllerChanged: {
            for (let i = 0; i < root.joints.count; i++) {
                let joint = root.joints.get(i);
                joint.active = false;
            }
            if (!d.controller)
                return;
            for (let i = 0; i < d.controller.claimed_interfaces.length; i++) {
                const name = d.extractJointName(d.controller.claimed_interfaces.at(i));
                let joint = getJoint(name);
                if (joint)
                    joint.active = true;
            }
        }
    }
    QtObject {
        id: parser

        function parseURDF(urdfString) {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "data:text/xml," + encodeURIComponent(urdfString));
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status !== 200 && xhr.status !== 0) {
                    // status 0 is for local files
                    Ros2.error("Error loading URDF XML data. Status:", xhr.status);
                    return;
                }
                let xmlDoc = xhr.responseXML.documentElement;
                if (!xmlDoc) {
                    Ros2.error("Failed to parse URDF.");
                    return;
                }
                let jointElements = XmlUtils.findElementsByTagName(xmlDoc, "joint");
                Ros2.debug("Found " + jointElements.length + " joint tags in URDF.");
                for (let i = 0; i < jointElements.length; i++) {
                    let jointElement = jointElements[i];
                    const type = XmlUtils.getAttributeValue(jointElement, "type");
                    if (!type || type === "fixed")
                        continue;
                    const name = XmlUtils.getAttributeValue(jointElement, "name");
                    const limits = XmlUtils.getChildByTagName(jointElement, "limit");
                    let limitUpper = Math.PI;
                    let limitLower = -Math.PI;
                    if (limits) {
                        limitUpper = parseFloat(XmlUtils.getAttributeValue(limits, "upper"));
                        if (isNaN(limitUpper))
                            limitUpper = Math.PI;
                        limitLower = parseFloat(XmlUtils.getAttributeValue(limits, "lower"));
                        if (isNaN(limitLower))
                            limitLower = -Math.PI;
                    }
                    Ros2.debug("Adding joint " + name + " - limits: lower=" + limitLower + ", upper=" + limitUpper);
                    d.addJoint({
                        "name": name,
                        "type": type,
                        "limits": {
                            "upper": limitUpper,
                            "lower": limitLower
                        }
                    });
                }
                Ros2.debug("Found " + root.joints.count + " joints in URDF.");
                root.hasRobotDescription = true;
            };
            xhr.send();
        }
    }
}
