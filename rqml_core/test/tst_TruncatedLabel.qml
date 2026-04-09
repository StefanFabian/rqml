import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 400
    height: 400

    TruncatedLabel {
        id: label
        text: "This is a very long text that should be truncated"
        width: 50
    }

    TruncatedLabel {
        id: shortLabel
        text: "hi"
        width: 200
        height: 40
    }

    // Helper: locate the internal MouseArea hosting the ToolTip attached props.
    function findMouseArea(item) {
        var children = item.children || [];
        for (var i = 0; i < children.length; ++i) {
            var c = children[i];
            if (c && c.hasOwnProperty("containsMouse") && c.hasOwnProperty("hoverEnabled"))
                return c;
        }
        return null;
    }

    TestCase {
        name: "TruncatedLabelTest"
        when: windowShown

        function test_truncation() {
            compare(label.elide, Text.ElideRight);
            wait(50);
            verify(label.truncated);
        }

        function test_notTruncatedWhenTextFits() {
            wait(50);
            verify(!shortLabel.truncated, "short text should not be truncated");
            var ma = findMouseArea(shortLabel);
            verify(ma !== null);
            verify(ma.fullyVisible, "fullyVisible should be true when text fits");
        }

        function test_fullyVisibleFalseWhenTruncated() {
            wait(50);
            var ma = findMouseArea(label);
            verify(ma !== null);
            verify(!ma.fullyVisible, "fullyVisible should be false when truncated");
        }

        function test_toolTipVisibilityExpression() {
            // The MouseArea binds ToolTip.visible to (!fullyVisible && (containsMouse || pressed)).
            // Synthetic hover dispatch is unreliable on the offscreen platform,
            // so we instead verify the gating predicate directly: fullyVisible
            // is the deciding factor and reflects truncation correctly.
            wait(50);
            var trunc = findMouseArea(label);
            var fits = findMouseArea(shortLabel);
            verify(trunc !== null && fits !== null);
            verify(!trunc.fullyVisible,
                "truncated label MUST allow tooltip (fullyVisible=false)");
            verify(fits.fullyVisible,
                "fitting label MUST suppress tooltip (fullyVisible=true)");
        }

        function test_fullyVisibleFollowsTextChanges() {
            // Replacing with an even longer string must keep the label truncated
            // and fullyVisible === false.
            label.text = "Another very long piece of text that will also be elided away for sure";
            wait(50);
            var ma = findMouseArea(label);
            verify(!ma.fullyVisible);
            verify(label.truncated);
        }
    }
}
