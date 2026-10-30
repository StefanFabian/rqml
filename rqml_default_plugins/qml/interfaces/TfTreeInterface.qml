import QtQuick
import Ros2
import RQml.Utils

/**
 * Backend interface for TF tree visualization.
 * Obtains frame data from a TfBuffer and builds a hierarchical ListModel
 * for the list view.
 */
Object {
    id: root

    //! The TfBuffer providing frame data
    property var buffer: null

    //! Whether data collection is enabled
    property bool enabled: true

    //! Total number of frames in the tree
    property int frameCount: 0

    //! ListModel containing all frames with their properties
    property var frames: ListModel {
    }

    //! Whether any TF data has been received
    readonly property bool hasData: frameCount > 0

    //! The root frame IDs (frames with no parent)
    property var rootFrames: []

    //! Signal emitted when the frame tree structure changes
    signal treeChanged

    // ========================================================================
    // Public Functions
    // ========================================================================

    /**
     * Clear all collected TF data and reset the tree.
     */
    function clear() {
        if (root.buffer)
            root.buffer.clear();
        d.resetData();
    }

    // ========================================================================
    // Formatting Helpers
    // ========================================================================

    //! Format an age value (seconds) for display
    function formatAge(age) {
        if (age < 0)
            return "N/A";
        if (age < 1)
            return (age * 1000).toFixed(0) + " ms";
        if (age < 60)
            return age.toFixed(1) + " s";
        return (age / 60).toFixed(1) + " min";
    }

    //! Format a frequency value for display
    function formatFrequency(freq, isStatic) {
        if (isStatic)
            return "static";
        if (freq <= 0)
            return "-";
        if (freq < 1)
            return freq.toFixed(2) + " Hz";
        if (freq < 9.95)
            return freq.toFixed(1) + " Hz";
        return freq.toFixed(0) + " Hz";
    }

    /**
     * Get children of a frame.
     */
    function getChildren(frameId) {
        if (!root.buffer)
            return [];
        const frame = root.buffer.getFrame(frameId);
        return frame ? frame.children : [];
    }

    /**
     * Get frame data by frame ID.
     * Returns a TfFrameInfo object from the buffer, or null if not found.
     */
    function getFrame(frameId) {
        if (!root.buffer)
            return null;
        return root.buffer.getFrame(frameId) || null;
    }

    /**
     * Toggle the collapsed state of a frame in the list view.
     */
    function toggleCollapse(frameId) {
        if (d.collapsedFrames[frameId]) {
            delete d.collapsedFrames[frameId];
        } else {
            d.collapsedFrames[frameId] = true;
        }
        d.rebuildModel();
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================
    QtObject {
        id: d

        property var collapsedFrames: ({})
        property var knownFrameIds: []  // Sorted list of known frame IDs for change detection

        function addFrameToModel(frameId, depth) {
            const frame = root.buffer.getFrame(frameId);
            if (!frame)
                return;
            const age = root.buffer.getTransformAge(frameId);
            const isCollapsed = d.collapsedFrames[frameId] === true;
            root.frames.append({
                "frameId": frame.frameId,
                "parentId": frame.parentId,
                "depth": depth,
                "isStatic": frame.isStatic,
                "hasChildren": frame.children.length > 0,
                "isCollapsed": isCollapsed,
                "age": age,
                "frequency": frame.frequency,
                "translationX": frame.translation.x,
                "translationY": frame.translation.y,
                "translationZ": frame.translation.z,
                "rotationX": frame.rotation.x,
                "rotationY": frame.rotation.y,
                "rotationZ": frame.rotation.z,
                "rotationW": frame.rotation.w
            });
            if (isCollapsed)
                return;
            const children = frame.children.slice().sort();
            for (let i = 0; i < children.length; ++i) {
                d.addFrameToModel(children[i], depth + 1);
            }
        }

        /**
         * Poll the buffer for frame changes and rebuild the model if needed.
         */
        function pollFrames() {
            if (!root.buffer)
                return;
            const allFrames = root.buffer.getAllFrames();
            if (!allFrames)
                return;

            // Detect structural changes by comparing frame IDs
            const currentIds = [];
            const parentMap = {};
            for (let i = 0; i < allFrames.length; ++i) {
                currentIds.push(allFrames[i].frameId);
                parentMap[allFrames[i].frameId] = allFrames[i].parentId;
            }
            currentIds.sort();
            let structureChanged = currentIds.length !== d.knownFrameIds.length;
            if (!structureChanged) {
                for (let i = 0; i < currentIds.length; ++i) {
                    if (currentIds[i] !== d.knownFrameIds[i]) {
                        structureChanged = true;
                        break;
                    }
                }
            }

            // Also check for reparenting
            if (!structureChanged) {
                for (let i = 0; i < root.frames.count; ++i) {
                    const item = root.frames.get(i);
                    if (parentMap[item.frameId] !== item.parentId) {
                        structureChanged = true;
                        break;
                    }
                }
            }
            if (structureChanged) {
                d.knownFrameIds = currentIds;
                d.rebuildModel();
            } else {
                d.updateModelInPlace();
            }
        }
        function rebuildModel() {
            if (!root.buffer) {
                root.frames.clear();
                root.rootFrames = [];
                root.frameCount = 0;
                root.treeChanged();
                return;
            }
            const allFrames = root.buffer.getAllFrames();
            if (!allFrames) {
                root.frames.clear();
                root.rootFrames = [];
                root.frameCount = 0;
                root.treeChanged();
                return;
            }

            // Build lookup of known frame IDs for root detection
            const frameSet = {};
            for (let i = 0; i < allFrames.length; ++i) {
                frameSet[allFrames[i].frameId] = true;
            }

            // Find root frames (no parent or parent not in the set)
            let roots = [];
            for (let i = 0; i < allFrames.length; ++i) {
                const f = allFrames[i];
                if (!f.parentId || f.parentId === "" || !frameSet[f.parentId]) {
                    roots.push(f.frameId);
                }
            }
            roots.sort();
            root.rootFrames = roots;
            root.frames.clear();
            for (let i = 0; i < roots.length; ++i) {
                d.addFrameToModel(roots[i], 0);
            }
            root.frameCount = allFrames.length;
            root.treeChanged();
        }

        /**
         * Reset all internal data structures.
         */
        function resetData() {
            d.collapsedFrames = {};
            d.knownFrameIds = [];
            root.frames.clear();
            root.rootFrames = [];
            root.frameCount = 0;
            root.treeChanged();
        }

        /**
         * Update age, frequency, and transform values in-place without rebuilding.
         */
        function updateModelInPlace() {
            for (let i = 0; i < root.frames.count; ++i) {
                const item = root.frames.get(i);
                const frame = root.buffer.getFrame(item.frameId);
                if (!frame)
                    continue;
                const age = root.buffer.getTransformAge(item.frameId);
                root.frames.setProperty(i, "age", age);
                root.frames.setProperty(i, "frequency", frame.frequency);
                root.frames.setProperty(i, "isStatic", frame.isStatic);
                root.frames.setProperty(i, "translationX", frame.translation.x);
                root.frames.setProperty(i, "translationY", frame.translation.y);
                root.frames.setProperty(i, "translationZ", frame.translation.z);
                root.frames.setProperty(i, "rotationX", frame.rotation.x);
                root.frames.setProperty(i, "rotationY", frame.rotation.y);
                root.frames.setProperty(i, "rotationZ", frame.rotation.z);
                root.frames.setProperty(i, "rotationW", frame.rotation.w);
            }
        }
    }

    // ========================================================================
    // Polling Timer
    // ========================================================================
    Timer {
        interval: 200
        repeat: true
        running: root.enabled && root.buffer !== null

        onTriggered: d.pollFrames()
    }
}
