pragma Singleton
/*
 * Copyright (C) 2025  Stefan Fabian
 *
 * This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import QtQuick

FontLoader {

    // Icon mappings sorted alphabetically (please keep it that way)
    readonly property string iconAdd: "\x2b"
    readonly property string iconArrowsLeftRight: "\uf07e"
    readonly property string iconArrowsUpDown: "\uf07d"
    readonly property string iconChevronDown: "\uf078"
    readonly property string iconChevronLeft: "\uf053"
    readonly property string iconChevronRight: "\uf054"
    readonly property string iconChevronUp: "\uf077"
    readonly property string iconClose: "\uf00d"
    readonly property string iconCopy: "\uf0c5"
    readonly property string iconCrosshairs: "\uf05b"
    readonly property string iconDebug: "\uf188"
    readonly property string iconEdit: "\uf044"
    readonly property string iconError: "\uf057"
    readonly property string iconExpand: "\uf065"
    readonly property string iconFatal: "\uf714"
    readonly property string iconFilter: "\uf0b0"
    readonly property string iconInfo: "\uf05a"
    readonly property string iconLoad: "\uf56f"
    readonly property string iconMagnifyingGlassMinus: "\uf010"
    readonly property string iconMagnifyingGlassPlus: "\uf00e"
    readonly property string iconMessage: "\uf075"
    readonly property string iconPause: "\uf04c"
    readonly property string iconPlay: "\uf04b"
    readonly property string iconRefresh: "\uf021"
    readonly property string iconRightLeft: "\uf362"
    readonly property string iconRotateLeft: "\uf0e2"
    readonly property string iconRotateRight: "\uf01e"
    readonly property string iconSave: "\uf0c7"
    readonly property string iconSearch: "\uf002"
    readonly property string iconSettings: "\uf013"
    readonly property string iconStar: "\uf005"
    readonly property string iconTrash: "\uf1f8"
    readonly property string iconWarning: "\uf071"

    source: "./Font Awesome 7 Free-Solid-900.otf"
}
