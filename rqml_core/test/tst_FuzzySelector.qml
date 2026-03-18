import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 400
    height: 400

    FuzzySelector {
        id: selector
        model: ["apple", "banana", "cherry", "apricot", "avocado", "blackberry"]
    }

    TestCase {
        name: "FuzzySelectorTest"
        when: windowShown

        function init() {
            selector.text = "";
            selector.currentIndex = -1;
        }

        function test_fuzzyScore() {
            // apple matches apple
            verify(selector.fuzzyScore("apple", "app") > 0);
            verify(selector.fuzzyScore("banana", "app") === -1);

            // better match vs worse match
            let score1 = selector.fuzzyScore("apricot", "ap");
            let score2 = selector.fuzzyScore("apple", "ap");
            verify(score1 > 0);
            verify(score2 > 0);
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

        function test_selection() {
            selector.currentIndex = 1; // banana
            compare(selector.currentText, "banana");
            compare(selector.text, "banana");
        }
    }
}
