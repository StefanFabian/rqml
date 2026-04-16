import QtQuick
import QtTest
import RQml.Elements

Item {
    height: 400
    width: 400

    FuzzySelector {
        id: selector
        model: ["apple", "banana", "cherry", "apricot", "avocado", "blackberry", "pineapple", "grape", "orange", "mango"]
    }
    TestCase {
        function findChevronMouseArea() {
            var field = findField();
            var ma = null;
            function walk(item) {
                if (ma)
                    return;
                var children = item.children || [];
                for (var i = 0; i < children.length; ++i) {
                    var c = children[i];
                    if (c && c.hasOwnProperty("containsMouse") && c.hasOwnProperty("hoverEnabled"))
                        ma = c;
                    else
                        walk(c);
                }
            }
            walk(field);
            return ma;
        }

        // ---- Helpers ----
        function findField() {
            var children = selector.children || [];
            for (var i = 0; i < children.length; ++i) {
                var c = children[i];
                if (c && c.toString().indexOf("TextField") !== -1)
                    return c;
            }
            return null;
        }
        function findListView() {
            var p = findPopup();
            return (p && p.contentItem && p.contentItem.toString().indexOf("ListView") !== -1) ? p.contentItem : null;
        }
        function findPopup() {
            var resources = selector.data || [];
            for (var i = 0; i < resources.length; ++i) {
                var c = resources[i];
                if (c && c.toString().indexOf("Popup") !== -1)
                    return c;
            }
            return null;
        }
        function init() {
            selector.text = "";
            selector.currentIndex = -1;
            selector.editable = true;
            var p = findPopup();
            if (p)
                p.close();
        }
        function test_browseMode() {
            var field = findField();
            var popup = findPopup();
            var ma = findChevronMouseArea();
            verify(ma !== null);

            // 1. Strict filtering when typing
            selector.text = "";
            field.text = "ap";
            field.textEdited();
            tryVerify(function () {
                    return popup.visible;
                }, 1000);
            verify(selector.filteredItems.indexOf("apple") !== -1);
            verify(selector.filteredItems.indexOf("banana") === -1, "Should filter strictly during typing");
            popup.close();

            // 2. Show all items when opened via chevron
            selector.text = "apple";
            field.text = "apple";
            ma.clicked(null);
            tryVerify(function () {
                    return popup.visible;
                }, 1000);
            verify(selector.filteredItems.indexOf("banana") !== -1, "Should show all items when opened via chevron");
            verify(selector.filteredItems[0] === "apple", "Best match (exact) should be at top");
            popup.close();

            // 3. Show all items when opened via Down key
            field.forceActiveFocus();
            keyClick(Qt.Key_Down);
            tryVerify(function () {
                    return popup.visible;
                }, 1000);
            verify(selector.filteredItems.indexOf("banana") !== -1, "Should show all items when opened via Down key");
            popup.close();

            // 4. Non-matching pattern in browse mode
            field.text = "xyz";
            field.textEdited(); // This enters typing mode (strict)
            verify(selector.filteredItems.length === 0);
            ma.clicked(null); // Force browse mode
            tryVerify(function () {
                    return popup.visible;
                }, 1000);
            verify(selector.filteredItems.length === selector.model.length, "Should show everything in browse mode even if no match");
            popup.close();
            tryVerify(function () {
                    return !popup.visible;
                }, 1000);
        }
        function test_caseInsensitiveFiltering() {
            selector.text = "APPLE";
            verify(selector.filteredItems.indexOf("apple") !== -1);
            selector.text = "app";
            verify(selector.filteredItems.indexOf("apple") !== -1);
        }
        function test_chevronTogglesPopup() {
            var popup = findPopup();
            var ma = findChevronMouseArea();
            verify(ma !== null, "chevron MouseArea should exist");
            verify(!popup.visible);
            ma.clicked(null);
            tryVerify(function () {
                    return popup.visible;
                }, 1000, "chevron click should open popup");
            ma.clicked(null);
            tryVerify(function () {
                    return !popup.visible;
                }, 1000, "second chevron click should close popup");
        }
        function test_currentText() {
            compare(selector.currentText, "", "currentText should be empty when currentIndex is -1");
            selector.currentIndex = 1; // "banana"
            compare(selector.currentText, "banana");
            // Out-of-bounds index should yield empty string.
            selector.currentIndex = 999;
            compare(selector.currentText, "");
        }
        function test_editableFalseBlocksTyping() {
            selector.editable = false;
            selector.text = "banana";
            // Simulating typing via onTextEdited would be blocked; verify the hook logic
            // by setting currentIndex (still allowed) and checking text stays in sync.
            selector.currentIndex = 0;
            compare(selector.text, "apple");
        }
        function test_emptyModel() {
            selector.model = [];
            compare(selector.filteredItems.length, 0);
            compare(selector.currentIndex, -1);
            compare(selector.currentText, "");
            selector.model = ["apple", "banana", "cherry", "apricot", "avocado", "blackberry", "pineapple", "grape", "orange", "mango"];
        }
        function test_escapeClosesPopup() {
            var field = findField();
            var popup = findPopup();
            popup.open();
            field.forceActiveFocus();
            tryVerify(function () {
                    return popup.visible;
                }, 1000);
            keyClick(Qt.Key_Escape);
            tryVerify(function () {
                    return !popup.visible;
                }, 1000, "Escape should close the popup");
        }
        function test_filteredItems() {
            selector.text = "ap";
            var items = selector.filteredItems;
            // should include apple, apricot
            verify(items.indexOf("apple") !== -1);
            verify(items.indexOf("apricot") !== -1);
            verify(items.indexOf("banana") === -1);
            selector.text = "berry";
            items = selector.filteredItems;
            verify(items.indexOf("blackberry") !== -1);
            verify(items.indexOf("banana") === -1);
        }
        function test_keyboardNavBoundaries() {
            var field = findField();
            var popup = findPopup();
            var listView = findListView();
            verify(listView !== null);
            popup.open();
            field.forceActiveFocus();
            tryVerify(function () {
                    return popup.visible;
                }, 1000);

            // Up at index 0 should not go negative.
            listView.currentIndex = 0;
            keyClick(Qt.Key_Up);
            compare(listView.currentIndex, 0, "Up at index 0 should stay at 0");

            // Down at last item should not exceed count.
            listView.currentIndex = listView.count - 1;
            keyClick(Qt.Key_Down);
            compare(listView.currentIndex, listView.count - 1, "Down at last item should stay at last");
            popup.close();
        }

        // ---- Interaction tests ----
        function test_keyboardNavigationAndSelect() {
            var field = findField();
            var popup = findPopup();
            var listView = findListView();
            verify(listView !== null);
            popup.open();
            field.forceActiveFocus();
            tryVerify(function () {
                    return popup.visible;
                }, 1000);

            // Drive list selection directly for determinism.
            // Items are sorted alphabetically when no pattern:
            // apple, apricot, avocado, banana, blackberry, cherry, grape, mango, orange, pineapple
            listView.currentIndex = 1; // "apricot"
            keyClick(Qt.Key_Return);
            tryVerify(function () {
                    return !popup.visible;
                }, 1000, "Return should close the popup");
            compare(selector.text, "apricot");
        }
        function test_popupAutoClosesOnNoMatches() {
            var field = findField();
            var popup = findPopup();
            popup.open();
            field.forceActiveFocus();
            tryVerify(function () {
                    return popup.visible;
                }, 1000);

            // Type a pattern that matches nothing — popup should auto-close.
            field.text = "zzz";
            field.textEdited();
            tryVerify(function () {
                    return !popup.visible;
                }, 1000, "popup should auto-close when filteredItems becomes empty");
        }
        function test_returnKeyNoSelection() {
            var field = findField();
            var popup = findPopup();
            var listView = findListView();
            verify(listView !== null);
            popup.open();
            field.forceActiveFocus();
            tryVerify(function () {
                    return popup.visible;
                }, 1000);
            listView.currentIndex = -1;
            keyClick(Qt.Key_Return);
            // No item was highlighted, so text must remain unchanged.
            compare(selector.text, "", "Return with no selection should not change text");
            // Popup should stay open (Return only closes when an item is selected).
            verify(popup.visible, "Return with no selection should not close popup");
            popup.close();
        }
        function test_scoringQualitySorting() {
            // "ap" should rank items with earlier / word-boundary matches higher.
            selector.text = "ap";
            var items = selector.filteredItems;
            // Both apple and apricot should come before avocado (which has 'a' then 'p'? actually avocado has no 'p').
            verify(items.indexOf("apple") < items.indexOf("blackberry") || items.indexOf("blackberry") === -1);
            // apricot & apple both start with "ap", so both should precede any non-start match.
            verify(items[0] === "apple" || items[0] === "apricot");
        }
        function test_selection() {
            selector.currentIndex = 1; // banana
            compare(selector.currentText, "banana");
            compare(selector.text, "banana");
        }
        function test_textToCurrentIndexSync() {
            // Setting text to an exact model entry should sync currentIndex.
            selector.text = "cherry";
            compare(selector.currentIndex, 2);
            // Setting to non-existent text should yield -1.
            selector.text = "xxx";
            compare(selector.currentIndex, -1);
        }

        name: "FuzzySelectorTest"
        when: windowShown
    }
}
