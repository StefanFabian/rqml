pragma Singleton
import QtQuick

// Test double for the AmentIndex singleton of qml6_ros2_plugin.
QtObject {
    //! Package names returned by getPackages().
    property var packages: []

    //! Maps "<resource type>/<resource name>" to the resource content.
    property var resources: ({})

    function getPackages() {
        return packages;
    }
    function getResource(resourceType, resourceName) {
        const content = resources[resourceType + "/" + resourceName];
        return content === undefined ? undefined : {
            "content": content,
            "prefix": "/mock"
        };
    }
}
