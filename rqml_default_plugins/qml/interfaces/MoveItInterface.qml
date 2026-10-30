import QtQuick
import Ros2
import RQml.Utils
import "."

/**
 * Backend interface for MoveIt move_group action client.
 * Handles SRDF/URDF parsing, joint state tracking, and motion execution.
 */
Object {
    id: root

    //! moveit_msgs/MoveItErrorCodes → { title, description }.
    // -4 (CONTROL_FAILED) uses a friendlier "Controller Error" title; every
    // other failure uses "Motion failed: <CODE_NAME>". Title changes must
    // stay in this one table.
    readonly property var _errorInfo: ({
            "-1": {
                "name": "PLANNING_FAILED",
                "description": "The planner could not find a valid motion plan."
            },
            "-2": {
                "name": "INVALID_MOTION_PLAN",
                "description": "The computed motion plan is invalid."
            },
            "-3": {
                "name": "MOTION_PLAN_INVALIDATED_BY_ENVIRONMENT_CHANGE",
                "description": "The environment changed during planning."
            },
            "-4": {
                "name": "CONTROL_FAILED",
                "title": "Controller Error",
                "description": "Motion execution failed. The trajectory controller may not be loaded or active."
            },
            "-5": {
                "name": "UNABLE_TO_AQUIRE_SENSOR_DATA",
                "description": "Could not acquire sensor data."
            },
            "-6": {
                "name": "TIMED_OUT",
                "description": "Planning or execution timed out."
            },
            "-7": {
                "name": "PREEMPTED",
                "description": "Motion was preempted."
            },
            "-10": {
                "name": "START_STATE_IN_COLLISION",
                "description": "The robot's start state is in collision."
            },
            "-11": {
                "name": "START_STATE_VIOLATES_PATH_CONSTRAINTS",
                "description": "The start state violates path constraints."
            },
            "-12": {
                "name": "GOAL_IN_COLLISION",
                "description": "The goal position is in collision."
            },
            "-13": {
                "name": "GOAL_VIOLATES_PATH_CONSTRAINTS",
                "description": "The goal violates path constraints."
            },
            "-14": {
                "name": "GOAL_CONSTRAINTS_VIOLATED",
                "description": "Goal constraints were violated."
            },
            "-15": {
                "name": "INVALID_GROUP_NAME",
                "description": "Invalid move group name."
            },
            "-16": {
                "name": "INVALID_GOAL_CONSTRAINTS",
                "description": "Invalid goal constraints."
            },
            "-17": {
                "name": "INVALID_ROBOT_STATE",
                "description": "Invalid robot state."
            },
            "-18": {
                "name": "INVALID_LINK_NAME",
                "description": "Invalid link name."
            },
            "-19": {
                "name": "INVALID_OBJECT_NAME",
                "description": "Invalid object name."
            },
            "-21": {
                "name": "FRAME_TRANSFORM_FAILURE",
                "description": "Frame transform failure."
            },
            "-22": {
                "name": "COLLISION_CHECKING_UNAVAILABLE",
                "description": "Collision checking unavailable."
            },
            "-23": {
                "name": "ROBOT_STATE_STALE",
                "description": "Robot state is stale."
            },
            "-24": {
                "name": "SENSOR_INFO_STALE",
                "description": "Sensor info is stale."
            },
            "-25": {
                "name": "COMMUNICATION_FAILURE",
                "description": "Communication failure."
            },
            "-26": {
                "name": "START_STATE_INVALID",
                "description": "Start state is invalid."
            },
            "-27": {
                "name": "GOAL_STATE_INVALID",
                "description": "Goal state is invalid."
            },
            "-28": {
                "name": "UNRECOGNIZED_GOAL_TYPE",
                "description": "Unrecognized goal type."
            },
            "-29": {
                "name": "CRASH",
                "description": "MoveIt crashed during execution."
            },
            "-30": {
                "name": "ABORT",
                "description": "Motion was aborted."
            },
            "-31": {
                "name": "NO_IK_SOLUTION",
                "description": "No inverse kinematics solution found for the goal pose."
            }
        })
    property real accelerationScale: 0.1

    //! Whether the MoveGroup action server is ready
    property bool actionReady: d.moveGroupClient && d.moveGroupClient.ready

    //! The selected MoveGroup action server (e.g., "/move_action" or "/athena/fold_manager_action")
    property string actionServer: ""

    //! Available MoveGroup action servers discovered via Ros2.queryActions()
    property var actionServers: ListModel {
    }

    //! Number of joints in the current move group with active === true
    property int activeJointCount: 0

    //! Whether we have received robot description
    property bool hasRobotDescription: false

    //! Whether we have received SRDF
    property bool hasSrdf: false

    //! Whether a goal is currently being executed
    property bool isGoalActive: false

    //! List of joints for the current move group
    property var joints: ListModel {
    }

    //! The currently selected move group name
    property string moveGroupName: ""

    //! List of available move groups from SRDF
    property var moveGroups: ListModel {
    }

    //! List of named poses for the current move group
    property var namedPoses: ListModel {
    }
    property int numPlanningAttempts: 1

    //! Planning options used by sendGoals()
    property real planningTime: 5.0
    property real velocityScale: 0.1

    //! Signal emitted when a new goal is accepted (to clear previous errors)
    signal goalAccepted

    //! Signal emitted when motion fails (for UI to display error)
    signal motionFailed(string errorTitle, string errorDetails)

    function _getErrorDescription(errorCode) {
        const info = _errorInfo[errorCode.toString()];
        return info ? info.description : "An unknown error occurred.";
    }
    function _getErrorTitle(errorCode) {
        const info = _errorInfo[errorCode.toString()];
        if (info && info.title)
            return info.title;
        return "Motion failed: " + (info ? info.name : "UNKNOWN_ERROR");
    }
    function _getJoint(jointName) {
        for (let i = 0; i < root.joints.count; i++) {
            let joint = root.joints.get(i);
            if (joint.name === jointName)
                return joint;
        }
        return null;
    }

    //! Apply a named pose (from SRDF group_state) to the current joint goals.
    function applyNamedPose(poseName) {
        if (!root.moveGroupName)
            return;
        const poses = d.allNamedPoses[root.moveGroupName];
        if (!poses)
            return;
        const jointValues = poses[poseName];
        if (!jointValues)
            return;
        for (let j = 0; j < jointValues.length; ++j) {
            const jv = jointValues[j];
            const joint = _getJoint(jv.name);
            if (joint)
                joint.goal = jv.value;
        }
    }

    /**
     * Cancel any active goal.
     */
    function cancelGoals() {
        if (!d.moveGroupClient || !d.moveGroupClient.ready) {
            Ros2.warn("MoveIt: Action server not connected");
            return;
        }
        d.moveGroupClient.cancelAllGoals();
        root.isGoalActive = false;
    }

    //! Refresh by re-querying topics and re-creating subscriptions.
    function refresh() {
        root.hasRobotDescription = false;
        root.hasSrdf = false;
        root.joints.clear();
        root.moveGroups.clear();
        root.namedPoses.clear();
        d.jointStateTopic = "";
        d.urdfTopic = "";
        d.srdfTopic = "";
        d.updateTopics();
    }

    /**
     * Reset all joint goals to their current positions.
     */
    function resetGoals() {
        for (let i = 0; i < root.joints.count; ++i) {
            let joint = root.joints.get(i);
            joint.goal = joint.position;
        }
    }

    //! Send joint goals to the MoveGroup action server using the current planning options.
    function sendGoals() {
        if (!d.moveGroupClient || !d.moveGroupClient.ready) {
            Ros2.warn("MoveIt: Action server not connected");
            return;
        }
        if (!root.moveGroupName) {
            Ros2.warn("MoveIt: No move group selected");
            return;
        }
        let msg = Ros2.createEmptyActionGoal("moveit_msgs/action/MoveGroup");
        msg.request.group_name = root.moveGroupName;
        msg.request.allowed_planning_time = root.planningTime;
        msg.request.max_velocity_scaling_factor = root.velocityScale;
        msg.request.max_acceleration_scaling_factor = root.accelerationScale;
        msg.request.num_planning_attempts = Math.max(1, root.numPlanningAttempts);

        // Build joint constraints for goal
        let goalConstraints = {
            "name": "goal_constraints",
            "joint_constraints": []
        };
        for (let i = 0; i < root.joints.count; i++) {
            let joint = root.joints.get(i);
            if (!joint.active)
                continue;
            goalConstraints.joint_constraints.push({
                "joint_name": joint.name,
                "position": joint.goal,
                "tolerance_above": 0.01,
                "tolerance_below": 0.01,
                "weight": 1.0
            });
        }
        if (goalConstraints.joint_constraints.length === 0) {
            Ros2.warn("MoveIt: No active joints to send");
            return;
        }
        msg.request.goal_constraints.push(goalConstraints);

        // Planning and execution options
        msg.planning_options.plan_only = false;
        msg.planning_options.look_around = false;
        msg.planning_options.replan = false;
        root.isGoalActive = true;
        d.moveGroupClient.sendGoalAsync(msg, {
            "onGoalResponse": function (goalHandle) {
                if (!goalHandle) {
                    Ros2.warn("MoveIt: Goal rejected by action server");
                    root.isGoalActive = false;
                    root.motionFailed("Goal Rejected", "The action server rejected the goal request.");
                    return;
                }
                root.goalAccepted();
            },
            "onResult": function (result) {
                root.isGoalActive = false;
                let errorCode = 0;
                try {
                    if (result && result.result && result.result.error_code) {
                        errorCode = result.result.error_code.val;
                    } else {
                        Ros2.warn("MoveIt: Unexpected result structure");
                        return;
                    }
                } catch (e) {
                    Ros2.error("MoveIt: Error parsing result: " + e);
                    return;
                }
                if (errorCode !== 1) {
                    // SUCCESS = 1
                    root.motionFailed(_getErrorTitle(errorCode), _getErrorDescription(errorCode));
                }
            }
        });
    }

    onActionServerChanged: {
        // Clear all state when action server changes
        root.joints.clear();
        root.moveGroups.clear();
        root.namedPoses.clear();
        root.hasRobotDescription = false;
        root.hasSrdf = false;
        d.allJoints = {};
        d.allMoveGroups = {};
        d.allNamedPoses = {};
        d.moveGroupNames = [];
        d.poseNamesPerGroup = {};
        d.kinematicChain = {};
        d.urdfTopic = "";
        d.srdfTopic = "";
        d.jointStateTopic = "";
        // Trigger immediate topic discovery for new action server
        d.updateTopics();
    }
    onMoveGroupNameChanged: {
        d._rebuildJointsModel();
        d._rebuildNamedPosesModel();
    }

    // ========================================================================
    // Subscriptions
    // ========================================================================
    Subscription {
        id: jointStateSubscription

        messageType: "sensor_msgs/msg/JointState"
        throttleRate: 5
        topic: d.jointStateTopic

        onNewMessage: msg => {
            for (let i = 0; i < msg.name.length; i++) {
                const name = msg.name.at(i);
                let joint = _getJoint(name);
                if (!joint)
                    continue;
                let position = msg.position.at(i);
                if (joint.type === "continuous") {
                    position = (position + Math.PI) % (2 * Math.PI) - Math.PI;
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
        topic: d.urdfTopic

        onNewMessage: msg => {
            if (!msg.data)
                return;
            parser.parseURDF(msg.data);
        }
    }
    Subscription {
        id: srdfSubscription

        messageType: "std_msgs/msg/String"
        qos: Ros2.QoS().transient_local().reliable()
        topic: d.srdfTopic

        onNewMessage: msg => {
            if (!msg.data)
                return;
            parser.parseSRDF(msg.data);
        }
    }

    // ========================================================================
    // Topic Discovery Timer
    // ========================================================================
    Timer {
        interval: 500
        repeat: true
        running: true

        onTriggered: d.updateTopics()
    }
    Connections {
        function onDataChanged() {
            d._updateActiveJointCount();
        }

        target: root.joints
    }

    // ========================================================================
    // Private Data
    // ========================================================================
    QtObject {
        id: d

        //! All joint data from URDF (not filtered by move group)
        property var allJoints: ({})

        //! All move group data from SRDF
        property var allMoveGroups: ({})

        //! All named poses from SRDF
        property var allNamedPoses: ({})
        property string jointStateTopic: ""

        //! Kinematic chain: maps child_link -> { joint_name, joint_type, parent_link }
        property var kinematicChain: ({})
        property var moveGroupClient: root.actionServer ? Ros2.createActionClient(root.actionServer, "moveit_msgs/action/MoveGroup") : null

        //! List of move group names (since Object.keys doesn't work in QML)
        property var moveGroupNames: []

        //! Map of pose names per group (since Object.keys doesn't work in QML)
        property var poseNamesPerGroup: ({})
        property string srdfTopic: ""
        property string urdfTopic: ""

        /**
         * Get all joints for a group, resolving chains and subgroups recursively.
         * @param groupName The name of the move group
         * @param visited Array of already visited group names (for cycle detection)
         * @returns Array of joint names
         */
        function _getJointsForGroup(groupName, visited) {
            if (!visited)
                visited = [];
            if (visited.indexOf(groupName) !== -1) {
                return []; // Circular reference
            }
            visited.push(groupName);
            const group = allMoveGroups[groupName];
            if (!group) {
                return [];
            }
            let joints = group.joints ? group.joints.slice() : [];

            // Traverse kinematic chains
            const chains = group.chains || [];
            for (let i = 0; i < chains.length; i++) {
                const chainJoints = parser.getJointsInChain(chains[i].base_link, chains[i].tip_link);
                for (let k = 0; k < chainJoints.length; k++) {
                    if (joints.indexOf(chainJoints[k]) === -1) {
                        joints.push(chainJoints[k]);
                    }
                }
            }

            // Resolve subgroups recursively
            const subgroups = group.subgroups || [];
            for (let i = 0; i < subgroups.length; i++) {
                const subgroupJoints = _getJointsForGroup(subgroups[i], visited);
                for (let k = 0; k < subgroupJoints.length; k++) {
                    if (joints.indexOf(subgroupJoints[k]) === -1) {
                        joints.push(subgroupJoints[k]);
                    }
                }
            }
            return joints;
        }

        /**
         * Rebuild the joints ListModel for the currently selected move group.
         */
        function _rebuildJointsModel() {
            if (!root.moveGroupName || !allMoveGroups[root.moveGroupName]) {
                return;
            }

            // Get all joints for the current group (resolves chains and subgroups)
            const groupJoints = _getJointsForGroup(root.moveGroupName);
            root.joints.clear();
            for (let i = 0; i < groupJoints.length; i++) {
                const jointName = groupJoints[i];
                const sourceData = allJoints[jointName];
                let jointData;
                if (!sourceData) {
                    // Joint not in URDF yet, create placeholder
                    jointData = {
                        "name": jointName,
                        "type": "unknown",
                        "limits": {
                            "upper": Math.PI,
                            "lower": -Math.PI
                        },
                        "position": 0.0,
                        "goal": 0.0,
                        "initialized": false,
                        "active": true
                    };
                } else {
                    jointData = {
                        "name": sourceData.name,
                        "type": sourceData.type,
                        "limits": sourceData.limits,
                        "position": sourceData.position || 0.0,
                        "goal": sourceData.goal || sourceData.position || 0.0,
                        "initialized": sourceData.initialized || false,
                        "active": true
                    };
                }

                // Insert in sorted order by joint name
                let insertIdx = 0;
                for (; insertIdx < root.joints.count; insertIdx++) {
                    if (root.joints.get(insertIdx).name > jointData.name)
                        break;
                }
                root.joints.insert(insertIdx, jointData);
            }
            _updateActiveJointCount();
        }
        function _rebuildNamedPosesModel() {
            root.namedPoses.clear();
            const poseNames = poseNamesPerGroup[root.moveGroupName] || [];
            for (let i = 0; i < poseNames.length; i++)
                root.namedPoses.append({
                    "name": poseNames[i]
                });
        }
        function _updateActiveJointCount() {
            let count = 0;
            for (let i = 0; i < root.joints.count; i++) {
                if (root.joints.get(i).active)
                    count++;
            }
            root.activeJointCount = count;
        }
        function addJoint(joint) {
            allJoints[joint.name] = joint;
        }
        function updateTopics() {
            // Discover MoveGroup action servers
            const allActions = Ros2.queryActions();
            let moveGroupActions = [];
            for (let i = 0; i < allActions.length; i++) {
                const types = Ros2.getActionTypes(allActions[i]);
                for (let j = 0; j < types.length; j++) {
                    if (types[j] === "moveit_msgs/action/MoveGroup") {
                        moveGroupActions.push(allActions[i]);
                        break;
                    }
                }
            }
            moveGroupActions.sort();

            // Update action servers model if changed
            let changed = moveGroupActions.length !== root.actionServers.count;
            if (!changed) {
                for (let i = 0; i < moveGroupActions.length; i++) {
                    if (root.actionServers.get(i).name !== moveGroupActions[i]) {
                        changed = true;
                        break;
                    }
                }
            }
            if (changed) {
                root.actionServers.clear();
                for (let i = 0; i < moveGroupActions.length; i++) {
                    root.actionServers.append({
                        "name": moveGroupActions[i]
                    });
                }
            }
            if (!root.actionServer)
                return;

            // Derive expected topics from the selected action server. We currently
            // do not support exotic setups not following conventions.
            const actionServer = root.actionServer;
            const lastSlash = actionServer.lastIndexOf("/");
            const ns = lastSlash > 0 ? actionServer.substring(0, lastSlash) : "";
            const expectedJointState = ns + "/joint_states";
            const expectedUrdf = ns + "/robot_description";
            const expectedSrdf = ns + "/robot_description_semantic";
            if (expectedJointState !== jointStateTopic) {
                jointStateTopic = expectedJointState;
            }
            if (expectedUrdf !== urdfTopic) {
                root.joints.clear();
                root.hasRobotDescription = false;
                urdfTopic = expectedUrdf;
            }
            if (expectedSrdf !== srdfTopic) {
                root.moveGroups.clear();
                root.namedPoses.clear();
                root.hasSrdf = false;
                srdfTopic = expectedSrdf;
            }
        }
    }

    // ========================================================================
    // XML Parser
    // ========================================================================
    QtObject {
        id: parser

        /**
         * Get all movable joints in the kinematic chain between base_link and tip_link.
         * Traverses from tip to base, collecting non-fixed joints.
         */
        function getJointsInChain(baseLink, tipLink) {
            let joints = [];
            let currentLink = tipLink;
            let iterations = 0;
            const maxIterations = 100; // Safety limit
            while (currentLink && currentLink !== baseLink && iterations < maxIterations) {
                const chainEntry = d.kinematicChain[currentLink];
                if (!chainEntry) {
                    break;
                }

                // Only add non-fixed joints
                if (chainEntry.joint_type && chainEntry.joint_type !== "fixed") {
                    joints.unshift(chainEntry.joint_name); // Add to front to maintain order
                }
                currentLink = chainEntry.parent_link;
                iterations++;
            }
            return joints;
        }

        /**
         * Parse SRDF XML to extract move groups and named poses.
         */
        function parseSRDF(srdfString) {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "data:text/xml," + encodeURIComponent(srdfString));
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status !== 200 && xhr.status !== 0) {
                    Ros2.error("MoveIt: Error loading SRDF XML data. Status: " + xhr.status);
                    return;
                }
                let xmlDoc = xhr.responseXML.documentElement;
                if (!xmlDoc) {
                    Ros2.error("MoveIt: Failed to parse SRDF.");
                    return;
                }

                // Parse move groups - only direct children of <robot>, not nested <group> refs
                d.allMoveGroups = {};
                d.moveGroupNames = [];
                let groupElements = XmlUtils.getChildrenByTagName(xmlDoc, "group");
                for (let i = 0; i < groupElements.length; i++) {
                    let groupElement = groupElements[i];
                    const groupName = XmlUtils.getAttributeValue(groupElement, "name");
                    if (!groupName)
                        continue;
                    let joints = [];
                    let chains = [];
                    let subgroups = [];

                    // Get direct joint references
                    let jointRefs = XmlUtils.getChildrenByTagName(groupElement, "joint");
                    for (let j = 0; j < jointRefs.length; j++) {
                        const jointName = XmlUtils.getAttributeValue(jointRefs[j], "name");
                        if (jointName && joints.indexOf(jointName) === -1) {
                            joints.push(jointName);
                        }
                    }

                    // Store chain references for later traversal (after URDF is parsed)
                    let chainRefs = XmlUtils.getChildrenByTagName(groupElement, "chain");
                    for (let j = 0; j < chainRefs.length; j++) {
                        const baseLink = XmlUtils.getAttributeValue(chainRefs[j], "base_link");
                        const tipLink = XmlUtils.getAttributeValue(chainRefs[j], "tip_link");
                        if (baseLink && tipLink) {
                            chains.push({
                                "base_link": baseLink,
                                "tip_link": tipLink
                            });
                        }
                    }

                    // Get subgroup references
                    let subgroupRefs = XmlUtils.getChildrenByTagName(groupElement, "group");
                    for (let j = 0; j < subgroupRefs.length; j++) {
                        const subgroupName = XmlUtils.getAttributeValue(subgroupRefs[j], "name");
                        if (subgroupName && subgroups.indexOf(subgroupName) === -1) {
                            subgroups.push(subgroupName);
                        }
                    }
                    d.allMoveGroups[groupName] = {
                        "name": groupName,
                        "joints": joints,
                        "chains": chains,
                        "subgroups": subgroups
                    };
                    if (d.moveGroupNames.indexOf(groupName) === -1) {
                        d.moveGroupNames.push(groupName);
                    }
                }

                // Update move groups model
                d.moveGroupNames.sort();
                root.moveGroups.clear();
                for (let i = 0; i < d.moveGroupNames.length; i++) {
                    root.moveGroups.append({
                        "name": d.moveGroupNames[i]
                    });
                }

                // Parse named poses (group_state elements)
                d.allNamedPoses = {};
                d.poseNamesPerGroup = {};
                let stateElements = XmlUtils.findElementsByTagName(xmlDoc, "group_state");
                for (let i = 0; i < stateElements.length; i++) {
                    let stateElement = stateElements[i];
                    const stateName = XmlUtils.getAttributeValue(stateElement, "name");
                    const groupName = XmlUtils.getAttributeValue(stateElement, "group");
                    if (!stateName || !groupName)
                        continue;
                    if (!d.allNamedPoses[groupName]) {
                        d.allNamedPoses[groupName] = {};
                        d.poseNamesPerGroup[groupName] = [];
                    }
                    let jointValues = [];
                    let jointRefs = XmlUtils.getChildrenByTagName(stateElement, "joint");
                    for (let j = 0; j < jointRefs.length; j++) {
                        const jointName = XmlUtils.getAttributeValue(jointRefs[j], "name");
                        const jointValue = parseFloat(XmlUtils.getAttributeValue(jointRefs[j], "value"));
                        if (jointName && !isNaN(jointValue)) {
                            jointValues.push({
                                "name": jointName,
                                "value": jointValue
                            });
                        }
                    }
                    d.allNamedPoses[groupName][stateName] = jointValues;
                    if (d.poseNamesPerGroup[groupName].indexOf(stateName) === -1) {
                        d.poseNamesPerGroup[groupName].push(stateName);
                    }
                }

                // Sort pose names per group
                for (let i = 0; i < d.moveGroupNames.length; i++) {
                    const gn = d.moveGroupNames[i];
                    if (d.poseNamesPerGroup[gn]) {
                        d.poseNamesPerGroup[gn].sort();
                    }
                }
                root.hasSrdf = true;

                // Rebuild models for current group
                d._rebuildJointsModel();
                d._rebuildNamedPosesModel();
            };
            xhr.send();
        }

        /**
         * Parse URDF XML to extract joint definitions and build the kinematic chain.
         */
        function parseURDF(urdfString) {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "data:text/xml," + encodeURIComponent(urdfString));
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status !== 200 && xhr.status !== 0) {
                    Ros2.error("MoveIt: Error loading URDF XML data. Status: " + xhr.status);
                    return;
                }
                let xmlDoc = xhr.responseXML.documentElement;
                if (!xmlDoc) {
                    Ros2.error("MoveIt: Failed to parse URDF.");
                    return;
                }
                let jointElements = XmlUtils.findElementsByTagName(xmlDoc, "joint");
                d.allJoints = {};
                d.kinematicChain = {};
                for (let i = 0; i < jointElements.length; i++) {
                    let jointElement = jointElements[i];
                    const type = XmlUtils.getAttributeValue(jointElement, "type");
                    const name = XmlUtils.getAttributeValue(jointElement, "name");

                    // Get parent and child links for kinematic chain
                    const parentLink = XmlUtils.getChildByTagName(jointElement, "parent");
                    const childLink = XmlUtils.getChildByTagName(jointElement, "child");
                    const parentLinkName = parentLink ? XmlUtils.getAttributeValue(parentLink, "link") : "";
                    const childLinkName = childLink ? XmlUtils.getAttributeValue(childLink, "link") : "";

                    // Build kinematic chain (including fixed joints for traversal)
                    if (childLinkName && parentLinkName) {
                        d.kinematicChain[childLinkName] = {
                            "joint_name": name,
                            "joint_type": type,
                            "parent_link": parentLinkName
                        };
                    }

                    // Skip fixed joints for the joint list
                    if (!type || type === "fixed")
                        continue;
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
                    d.addJoint({
                        "name": name,
                        "type": type,
                        "limits": {
                            "upper": limitUpper,
                            "lower": limitLower
                        },
                        "position": 0.0,
                        "goal": 0.0,
                        "initialized": false,
                        "active": false
                    });
                }
                root.hasRobotDescription = true;
                d._rebuildJointsModel();
            };
            xhr.send();
        }
    }
}
