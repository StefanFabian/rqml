import QtQuick
import QtQuick.Controls

/**
 * Mock FileDialog for UI tests.
 * Allows programmatic control of selected files and simple accept/reject simulation.
 */
QtObject {
    id: root

    // FileDialog properties
    property string title: ""
    property url fileUrl: ""
    property var fileUrls: []
    property url folder: ""
    property string selectedFile: "" // Convenience for tests
    property bool visible: false
    property bool modal: true
    property var nameFilters: []
    enum FileModes { OpenFile, OpenFiles, SaveFile, Folder }
    property int fileMode: FileDialog.OpenFile
    property string defaultSuffix: ""

    signal accepted()
    signal rejected()

    function open() {
        visible = true;
    }

    function close() {
        visible = false;
    }

    // Test helper to simulate user accepting the dialog
    function accept(url) {
        if (url !== undefined) {
            fileUrl = url;
            fileUrls = [url];
        }
        accepted();
        close();
    }

    // Test helper to simulate user cancelling the dialog
    function reject() {
        rejected();
        close();
    }
}
