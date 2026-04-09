import Qt.labs.qmlmodels
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import "elements"

Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(800, 300)
    color: palette.base

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 8

        RowLayout {
            IconButton {
                id: filterButton
                objectName: "consoleFilterButton"
                text: IconFont.iconFilter
                tooltipText: "Set filters"

                onClicked: {
                    if (!filterPopup.visible)
                        filterPopup.open();
                }
            }
            TextField {
                id: filterTextField
                objectName: "consoleFilterTextField"
                Layout.fillWidth: true
                placeholderText: "Filter logs..."
                onTextChanged: searchDebounceTimer.start()
            }
            IconButton {
                objectName: "consoleSettingsButton"
                text: IconFont.iconSettings
                tooltipText: "Settings"
                onClicked: {
                    settingsDialog.open();
                }
            }
            IconToggleButton {
                objectName: "consoleEnableToggle"
                iconOn: IconFont.iconPause
                iconOff: IconFont.iconPlay
                tooltipTextOn: "Click to pause"
                tooltipTextOff: "Click to start"
                checked: context.enabled ?? true
                onToggled: {
                    if (context.enabled === checked)
                        return;
                    context.enabled = checked;
                }
            }
            IconButton {
                objectName: "consoleClearButton"
                text: IconFont.iconTrash
                tooltipText: "Clear logs"
                onClicked: d.clear()
            }
        }
        Subscription {
            id: logSubscription
            qos: Ros2.QoS().reliable().keep_last(1000).transient_local()
            messageType: "rcl_interfaces/msg/Log"
            throttleRate: 0
            topic: context.topic ?? "/rosout"
            onNewMessage: function (message) {
                if (!(context.enabled ?? true))
                    return;
                d.addLog({
                    "level": parseInt(message.level),
                    "name": message.name,
                    "message": message.msg.trim(),
                    "location": message.file + ":" + message.line + " (" + message.function + ")",
                    "timestamp": d.formatDate(message.stamp.toJSDate())
                });
            }
        }

        ListView {
            id: listView
            objectName: "consoleListView"
            Layout.fillWidth: true
            Layout.fillHeight: true
            ScrollBar.vertical: ScrollBar {
                policy: listView.contentHeight > listView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }
            onMovementStarted: {
                if (context.autoScroll ?? true) {
                    context.autoScroll = false;
                }
            }
            reuseItems: true // When reusing items, the binding for the width in the truncated label breaks sometimes
            clip: true
            model: ListModel {
                id: listModel
            }

            delegate: Rectangle {
                required property var model
                required property int index
                ListView.onPooled: {
                    if (contextMenu.visible)
                        contextMenu.close();
                }
                implicitHeight: rowLayout.implicitHeight
                width: listView.width
                color: index % 2 == 0 ? palette.base : palette.alternateBase
                border.width: contextMenu.visible ? 2 : 0
                border.color: palette.highlight
                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    spacing: 8
                    LogLevelIndicator {
                        Layout.margins: 8
                        Layout.alignment: Qt.AlignVCenter
                        level: model.level
                    }
                    TruncatedLabel {
                        Layout.margins: 8
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                        maximumLineCount: 4
                        text: model.message
                    }
                    TruncatedLabel {
                        Layout.margins: 8
                        Layout.preferredWidth: 160
                        text: model.name
                    }
                    TruncatedLabel {
                        Layout.margins: 8
                        Layout.preferredWidth: 160
                        text: model.location
                    }
                    TruncatedLabel {
                        Layout.margins: 8
                        Layout.preferredWidth: 160
                        text: model.timestamp
                    }
                }

                MouseArea {
                    anchors.fill: parent

                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            contextMenu.popup();
                        }
                    }
                    onPressAndHold: mouse => {
                        if (mouse.source === Qt.MouseEventNotSynthesized) {
                            contextMenu.popup();
                        }
                    }

                    Menu {
                        id: contextMenu
                        objectName: "consoleContextMenu"
                        MenuItem {
                            objectName: "consoleCopyMessageAction"
                            text: qsTr("Copy Message")
                            onTriggered: RQml.copyTextToClipboard(model.message)
                        }
                        MenuItem {
                            objectName: "consoleCopyNodeNameAction"
                            text: qsTr("Copy Node Name")
                            onTriggered: RQml.copyTextToClipboard(model.name)
                        }
                        MenuItem {
                            objectName: "consoleCopyLocationAction"
                            text: qsTr("Copy Location")
                            onTriggered: RQml.copyTextToClipboard(model.location)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: qsTr("Total logs: %1 / %2").arg(listModel.count).arg(d.logCount)
            }

            Item {
                Layout.fillWidth: true
            }

            CheckBox {
                objectName: "consoleAutoScrollCheckbox"
                text: "Scroll to end"
                checked: context.autoScroll ?? true
                onToggled: {
                    context.autoScroll = checked;
                }
            }
        }
    }

    Dialog {
        id: settingsDialog
        objectName: "consoleSettingsDialog"
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, 400)
        title: "Console Settings"
        standardButtons: Dialog.Ok
        modal: true

        ColumnLayout {
            anchors.fill: parent
            Label {
                font.bold: true
                text: "Rosout Topic:"
            }
            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: topicSelect
                    objectName: "consoleSettingsTopicSelect"
                    Layout.fillWidth: true
                    editable: true
                    selectTextByMouse: true
                    editText: context.topic
                    onEditTextChanged: {
                        if (editText == null || editText == context.topic)
                            return;
                        if (!Ros2.isValidTopic(editText))
                            return;
                        context.topic = editText;
                    }
                    function refresh() {
                        let topics = Ros2.queryTopics("rcl_interfaces/msg/Log");
                        if (!!context.topic) {
                            const index = topics.indexOf(context.topic);
                            if (index != -1)
                                topics.splice(index, 1);
                            topics.unshift(context.topic);
                        }
                        model = topics;
                    }
                    Component.onCompleted: refresh()
                }
                RefreshButton {
                    objectName: "consoleSettingsRefreshButton"
                    onClicked: {
                        animate = true;
                        topicSelect.refresh();
                        animate = false;
                    }
                }
            }
        }
    }

    Popup {
        id: filterPopup
        objectName: "consoleFilterPopup"
        focus: true
        padding: 8
        x: filterButton.mapToItem(root, 0, filterButton.height).x + 8
        y: filterButton.mapToItem(root, 0, filterButton.height).y + 8

        ColumnLayout {

            Label {
                text: "Filter logs by level:"
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [
                        {
                            "icon": IconFont.iconDebug,
                            "text": "Debug",
                            "level": 10
                        },
                        {
                            "icon": IconFont.iconInfo,
                            "text": "Info",
                            "level": 20
                        },
                        {
                            "icon": IconFont.iconWarning,
                            "text": "Warning",
                            "level": 30
                        },
                        {
                            "icon": IconFont.iconError,
                            "text": "Error",
                            "level": 40
                        },
                        {
                            "icon": IconFont.iconFatal,
                            "text": "Fatal",
                            "level": 50
                        }
                    ]
                    IconButton {
                        id: debugCheckBox
                        objectName: "filterLevelToggle_" + modelData.level
                        text: modelData.icon
                        tooltipText: modelData.text
                        checkable: true
                        checked: d.filter.levels.indexOf(modelData.level) !== -1
                        onToggled: {
                            let index = d.filter.levels.indexOf(modelData.level);
                            if (checked) {
                                if (index === -1)
                                    d.filter.levels.push(modelData.level);
                            } else if (index !== -1) {
                                d.filter.levels.splice(index, 1);
                            }
                            d.applyFilter();
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: searchDebounceTimer
        interval: 300
        repeat: false
        onTriggered: {
            d.filter.searchText = filterTextField.text.toLowerCase();
            d.applyFilter();
        }
    }

    Timer {
        id: scrollTimer
        property int lastRowCount: 0
        interval: 50
        repeat: true
        running: context.autoScroll ?? true
        onTriggered: {
            if (listModel.count == lastRowCount) {
                return;
            }
            lastRowCount = listModel.count;
            listView.positionViewAtEnd();
        }
    }

    QtObject {
        id: d
        property var allLogs: []
        property int logCount: 0
        property var filter: {
            "levels": [10, 20, 30, 40, 50],
            "searchText": ""
        }

        function addLog(entry) {
            entry.searchString = (entry.message + "/" + entry.name + "/" + entry.location).toLowerCase();
            entry.filtered = matchesFilters(entry);
            allLogs.push(entry);
            logCount = allLogs.length;

            if (!entry.filtered) {
                return;
            }

            listModel.append(entry);
        }

        function matchesFilters(entry) {
            if (d.filter.levels.indexOf(entry.level) === -1) {
                return false;
            }
            if (d.filter.searchText?.length > 0) {
                if (entry.searchString.indexOf(d.filter.searchText) === -1) {
                    return false;
                }
            }
            return true;
        }

        function applyFilter() {
            let modelIndex = 0;
            for (let i = 0; i < allLogs.length; i++) {
                const entry = allLogs[i];
                const matches = matchesFilters(entry);
                if (matches == entry.filtered) {
                    if (matches)
                        modelIndex++;
                    continue;
                }
                entry.filtered = matches;
                if (matches) {
                    listModel.insert(modelIndex, entry);
                    modelIndex++;
                } else {
                    listModel.remove(modelIndex, 1);
                }
            }
        }

        function clear() {
            allLogs = [];
            logCount = 0;
            listModel.clear();
        }

        function formatDate(date) {
            if (!date)
                return "";
            let result = date.getHours().toString().padStart(2, '0') + ":";
            result += date.getMinutes().toString().padStart(2, '0') + ":";
            result += date.getSeconds().toString().padStart(2, '0') + ".";
            result += date.getMilliseconds().toString().padStart(3, '0');
            result += " (" + date.getFullYear() + "-";
            result += (date.getMonth() + 1).toString().padStart(2, '0') + "-";
            result += date.getDate().toString().padStart(2, '0') + ")";
            return result;
        }
    }
}
