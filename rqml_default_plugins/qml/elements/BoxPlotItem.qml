/*
 * BoxPlotItem.qml - Horizontal boxplot visualization component
 *
 * Displays a boxplot (min, Q1, median, Q3, max) with smooth animations
 * and optional formatted statistics labels below the plot.
 *
 * Usage:
 *   BoxPlotItem {
 *       minValue: 10; q1Value: 25; medianValue: 50; q3Value: 75; maxValue: 100
 *       displayMin: 0; displayMax: 120  // Shared scale across multiple plots
 *       formatValue: function(v) { return v.toFixed(1) + " ms" }  // Optional
 *   }
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Elements

Item {
    id: root

    // Animated values - must live on root for Behavior bindings to work
    property real _animMax: maxValue
    property real _animMedian: medianValue
    property real _animMin: minValue
    property real _animQ1: q1Value
    property real _animQ3: q3Value

    // Display range for consistent scaling across multiple boxplots
    property real displayMax: 100
    property real displayMin: 0

    // Optional value formatter callback. When set, statistics labels are shown
    // below the plot. Signature: function(value: real) -> string
    property var formatValue: null
    property real maxValue: 0
    property real medianValue: 0

    // Statistics values (will be animated when changed)
    property real minValue: 0
    property real q1Value: 0
    property real q3Value: 0

    implicitHeight: d.boxHeight + 12 + (labelsRow.visible ? labelsRow.implicitHeight + 4 : 0)
    implicitWidth: 200

    Behavior on _animMax {
        NumberAnimation {
            duration: d.animationDuration
            easing.type: Easing.OutQuad
        }
    }
    Behavior on _animMedian {
        NumberAnimation {
            duration: d.animationDuration
            easing.type: Easing.OutQuad
        }
    }
    Behavior on _animMin {
        NumberAnimation {
            duration: d.animationDuration
            easing.type: Easing.OutQuad
        }
    }
    Behavior on _animQ1 {
        NumberAnimation {
            duration: d.animationDuration
            easing.type: Easing.OutQuad
        }
    }
    Behavior on _animQ3 {
        NumberAnimation {
            duration: d.animationDuration
            easing.type: Easing.OutQuad
        }
    }

    onDisplayMaxChanged: canvas.requestPaint()
    onDisplayMinChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onMaxValueChanged: _animMax = maxValue
    onMedianValueChanged: _animMedian = medianValue
    onMinValueChanged: _animMin = minValue
    onQ1ValueChanged: _animQ1 = q1Value
    onQ3ValueChanged: _animQ3 = q3Value
    onWidthChanged: canvas.requestPaint()

    QtObject {
        id: d

        readonly property int animationDuration: 300
        readonly property color boxBaseColor: Material.color(Material.Blue, Material.Shade700)
        readonly property color boxBorderColor: Material.color(Material.Blue, Material.Shade900)
        readonly property color boxColor: Qt.rgba(boxBaseColor.r, boxBaseColor.g, boxBaseColor.b, 0.8)
        readonly property real boxHeight: 18
        readonly property color boxLabelColor: isDark ? Qt.lighter(boxBaseColor, 1.5) : Qt.darker(boxBaseColor, 1.3)
        readonly property bool isDark: palette.window.hslLightness < 0.5
        readonly property real marginH: 8
        readonly property color medianColor: Material.color(Material.Red, Material.Shade600)
        readonly property color medianLabelColor: isDark ? Qt.lighter(medianColor, 1.4) : Qt.darker(medianColor, 1.2)
        readonly property color whiskerColor: palette.text
    }

    // Background track
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: d.marginH
        anchors.right: parent.right
        anchors.rightMargin: d.marginH
        anchors.verticalCenter: canvas.verticalCenter
        color: palette.mid
        height: 2
        opacity: 0.3
        radius: 1
    }

    // Boxplot canvas
    Canvas {
        id: canvas

        anchors.left: parent.left
        anchors.leftMargin: d.marginH
        anchors.right: parent.right
        anchors.rightMargin: d.marginH
        anchors.top: parent.top
        height: d.boxHeight + 12

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (width < 2 || height < 2)
                return;
            const range = root.displayMax - root.displayMin;
            if (range <= 0)
                return;
            const drawWidth = width;
            const centerY = height / 2;
            const halfBox = d.boxHeight / 2;
            function mapX(val) {
                const normalized = (val - root.displayMin) / range;
                return Math.max(1, Math.min(normalized * drawWidth, drawWidth - 1));
            }
            const minX = mapX(root._animMin);
            const q1X = mapX(root._animQ1);
            const medX = mapX(root._animMedian);
            const q3X = mapX(root._animQ3);
            const maxX = mapX(root._animMax);

            // Whisker lines
            ctx.strokeStyle = d.whiskerColor;
            ctx.lineWidth = 1.5;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(minX, centerY);
            ctx.lineTo(q1X, centerY);
            ctx.moveTo(q3X, centerY);
            ctx.lineTo(maxX, centerY);
            ctx.stroke();

            // Whisker end caps
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(minX, centerY - halfBox * 0.5);
            ctx.lineTo(minX, centerY + halfBox * 0.5);
            ctx.moveTo(maxX, centerY - halfBox * 0.5);
            ctx.lineTo(maxX, centerY + halfBox * 0.5);
            ctx.stroke();

            // Box (Q1 to Q3)
            const boxWidth = Math.max(q3X - q1X, 4);
            const boxRadius = 3;
            ctx.fillStyle = d.boxColor;
            ctx.beginPath();
            ctx.roundedRect(q1X, centerY - halfBox, boxWidth, d.boxHeight, boxRadius, boxRadius);
            ctx.fill();
            ctx.strokeStyle = d.boxBorderColor;
            ctx.lineWidth = 1.5;
            ctx.stroke();

            // Median line
            ctx.strokeStyle = d.medianColor;
            ctx.lineWidth = 2.5;
            ctx.beginPath();
            ctx.moveTo(medX, centerY - halfBox + 2);
            ctx.lineTo(medX, centerY + halfBox - 2);
            ctx.stroke();
        }
    }

    // Statistics labels
    RowLayout {
        id: labelsRow

        anchors.left: parent.left
        anchors.leftMargin: d.marginH
        anchors.right: parent.right
        anchors.rightMargin: d.marginH
        anchors.top: canvas.bottom
        spacing: 6
        visible: !!root.formatValue

        Caption {
            Layout.preferredWidth: 90
            text: root.formatValue ? "min " + root.formatValue(root.minValue) : ""
        }
        Caption {
            Layout.preferredWidth: 90
            color: d.boxLabelColor
            text: root.formatValue ? "Q1 " + root.formatValue(root.q1Value) : ""
        }
        Caption {
            Layout.preferredWidth: 90
            color: d.medianLabelColor
            font.bold: true
            text: root.formatValue ? "med " + root.formatValue(root.medianValue) : ""
        }
        Caption {
            Layout.preferredWidth: 90
            color: d.boxLabelColor
            text: root.formatValue ? "Q3 " + root.formatValue(root.q3Value) : ""
        }
        Caption {
            text: root.formatValue ? "max " + root.formatValue(root.maxValue) : ""
        }
        Item {
            Layout.fillWidth: true
        }
    }

    // Repaint when animated values change
    Connections {
        function on_AnimMaxChanged() {
            canvas.requestPaint();
        }
        function on_AnimMedianChanged() {
            canvas.requestPaint();
        }
        function on_AnimMinChanged() {
            canvas.requestPaint();
        }
        function on_AnimQ1Changed() {
            canvas.requestPaint();
        }
        function on_AnimQ3Changed() {
            canvas.requestPaint();
        }

        target: root
    }
}
