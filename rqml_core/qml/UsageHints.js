// Shortcut hints shown in the empty-state message.
var shortcuts = [
    qsTr("Press Ctrl+S to save the current configuration."),
    qsTr("Press Ctrl+Shift+S to save the configuration as a new file."),
    qsTr("Press Ctrl+O to open a configuration."),
    qsTr("Press Ctrl+R to open recent configurations."),
    qsTr("Press Ctrl+P to open the plugin picker."),
    qsTr("Press Ctrl+W to close the selected plugin."),
    qsTr("Press Ctrl+Shift+W to close all plugins."),
    qsTr("Press Ctrl+Tab (or Ctrl+Shift+Tab) to cycle through plugins.")
];

function getHint(previousHint) {
    if (!shortcuts || shortcuts.length === 0)
        return "";
    if (shortcuts.length === 1)
        return shortcuts[0];

    var nextHint = shortcuts[Math.floor(Math.random() * shortcuts.length)];
    if (nextHint === previousHint)
        nextHint = shortcuts[(shortcuts.indexOf(nextHint) + 1) % shortcuts.length];
    return nextHint;
}
