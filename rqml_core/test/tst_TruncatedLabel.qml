import QtQuick
import QtTest
import RQml.Elements

Item {
    width: 100
    height: 400

    TruncatedLabel {
        id: label
        text: "This is a very long text that should be truncated"
        width: 50
    }

    TestCase {
        name: "TruncatedLabelTest"
        when: windowShown

        function test_truncation() {
            compare(label.elide, Text.ElideRight);
            // wait for layout
            wait(50);
            verify(label.truncated);
        }
    }
}
