import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Rectangle {
    //! possible values: "unconfigured", "inactive", "active", "unloaded", "unknown", "finalized" and the transition
    //! states "configuring", "cleaningup", "shuttingdown", "activating", "deactivating", "errorprocessing"
    property string state: "unknown"

    color: {
        if (state === "active")
            return Material.color(Material.Green);
        if (state === "inactive")
            return Material.color(Material.Blue);
        if (state === "unconfigured")
            return Material.color(Material.Orange);
        if (state === "unloaded")
            return Material.color(Material.Grey);
        if (state === "unknown")
            return Material.color(Material.Purple);
        if (["configuring", "cleaningup", "shuttingdown", "activating", "deactivating"].includes(state))
            return Material.color(Material.Amber);
        if (state === "finalized")
            return Material.color(Material.Grey, Material.Shade700);
        return Material.color(Material.Red);
    }
    height: Math.min(16, parent.height - 8)
    radius: height / 2
    width: height
}
