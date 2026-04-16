import QtQuick
import QtTest
import RQml.Utils

Item {
    TestCase {
        function test_caseInsensitive() {
            verify(FuzzySearch.score("APPLE", "app") > 0);
            verify(FuzzySearch.score("Apple", "APP") > 0);
        }
        function test_consecutiveRunBonus() {
            var consecutive = FuzzySearch.singleTermScore("abcdef", "abc");
            var spaced = FuzzySearch.singleTermScore("axbxcx", "abc");
            verify(consecutive > spaced, "consecutive run should outscore spaced matches");
        }
        function test_multiFieldScore() {
            verify(FuzzySearch.scoreFields(["Image View", "Sensors"], "img sens") > 0);
            verify(FuzzySearch.scoreFields(["Image View", "Sensors"], "img ctrl") === -1);
        }
        function test_multiTermAndSemantics() {
            verify(FuzzySearch.score("image raw", "img raw") > 0);
            verify(FuzzySearch.score("image raw", "img depth") === -1);
        }
        function test_score() {
            verify(FuzzySearch.score("apple", "app") > 0);
            verify(FuzzySearch.score("banana", "app") === -1);
            let score1 = FuzzySearch.score("apricot", "ap");
            let score2 = FuzzySearch.score("apple", "ap");
            verify(score1 > 0);
            verify(score2 > 0);
        }
        function test_whitespaceIsNormalized() {
            const compact = FuzzySearch.score("image raw topic", "image raw");
            const spaced = FuzzySearch.score("image raw topic", "  image   raw  ");
            compare(spaced, compact);
        }
        function test_wordBoundaryBonus() {
            var atStart = FuzzySearch.singleTermScore("apple", "a");
            var notAtStart = FuzzySearch.singleTermScore("banana", "a");
            verify(atStart > notAtStart, "start-of-string match should score higher than mid-word");
            var afterSeparator = FuzzySearch.singleTermScore("foo/bar", "b");
            var midWord = FuzzySearch.singleTermScore("foobar", "b");
            verify(afterSeparator > midWord, "post-separator match should score higher than mid-word");
        }

        name: "FuzzySearchTest"
    }
}
