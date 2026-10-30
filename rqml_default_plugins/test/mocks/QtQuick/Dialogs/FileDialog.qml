import QtQuick
import QtQuick.Controls

/**
 * Mock FileDialog for UI tests.
 * Allows programmatic control of selected files and simple accept/reject simulation.
 */
QtObject {
    id: root

    enum FileModes {
        OpenFile,
        OpenFiles,
        SaveFile,
        Folder
    }

    property string defaultSuffix: ""
    property int fileMode: FileDialog.OpenFile
    property url fileUrl: ""
    property var fileUrls: []
    property url folder: ""
    property bool modal: true
    property var nameFilters: []
    property string selectedFile: "" // Convenience for tests

    // FileDialog properties
    property string title: ""
    property bool visible: false

    signal accepted
    signal rejected

    // Test helper to simulate user accepting the dialog
    function accept(url) {
        if (url !== undefined) {
            fileUrl = url;
            fileUrls = [url];
        }
        accepted();
        close();
    }
    function close() {
        visible = false;
    }
    function open() {
        visible = true;
    }

    // Test helper to simulate user cancelling the dialog
    function reject() {
        rejected();
        close();
    }
}
