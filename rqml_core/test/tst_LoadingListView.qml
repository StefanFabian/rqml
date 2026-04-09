import QtQuick
import QtQuick.Controls
import QtTest
import RQml.Elements

Item {
    width: 200
    height: 200

    LoadingListView {
        id: listView
        anchors.fill: parent
        model: 3
        delegate: Item {
            width: parent ? parent.width : 0
            height: 20
        }
    }

    LoadingListView {
        id: overflowingListView
        width: 200
        height: 50
        model: 50
        delegate: Item {
            width: parent ? parent.width : 0
            height: 20
        }
    }

    TestCase {
        name: "LoadingListViewTest"
        when: windowShown

        function findOverlay(item) {
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i) {
                var c = children[i];
                // The overlay is a Rectangle with z:1 and a BusyIndicator child.
                if (c && c.hasOwnProperty("color") && c.z === 1)
                    return c;
            }
            return null;
        }

        function findBusyIndicator(item) {
            var children = item.children || [];
            for (var i = 0; i < children.length; ++i) {
                var c = children[i];
                if (c && c.hasOwnProperty("running") && c.toString().indexOf("BusyIndicator") !== -1)
                    return c;
                var inner = findBusyIndicator(c);
                if (inner) return inner;
            }
            return null;
        }

        function test_defaultIsLoadingFalse() {
            compare(listView.isLoading, false);
            var overlay = findOverlay(listView);
            verify(overlay !== null, "overlay rectangle should exist");
            compare(overlay.visible, false, "overlay hidden when not loading");
        }

        function test_isLoadingTogglesOverlay() {
            listView.isLoading = true;
            var overlay = findOverlay(listView);
            compare(overlay.visible, true);

            listView.isLoading = false;
            compare(overlay.visible, false);
        }

        function test_overlayCoversParent() {
            var overlay = findOverlay(listView);
            listView.isLoading = true;
            compare(overlay.width, listView.width);
            compare(overlay.height, listView.height);
            listView.isLoading = false;
        }

        function test_busyIndicatorRunning() {
            listView.isLoading = true;
            var busy = findBusyIndicator(listView);
            verify(busy !== null, "BusyIndicator should exist");
            compare(busy.running, true);
            listView.isLoading = false;
        }

        function test_clipsContentByDefault() {
            compare(listView.clip, true);
        }

        function test_scrollBarVisibilityWhenContentFits() {
            var sb = listView.ScrollBar.vertical;
            verify(sb !== null);
            compare(sb.policy, ScrollBar.AlwaysOff,
                "scroll bar should be off when content fits");
        }

        function test_scrollBarVisibilityWhenContentOverflows() {
            var sb = overflowingListView.ScrollBar.vertical;
            verify(sb !== null);
            compare(sb.policy, ScrollBar.AlwaysOn,
                "scroll bar should be on when content overflows");
        }
    }
}
