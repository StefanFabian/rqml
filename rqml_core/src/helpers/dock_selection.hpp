/*
 * Copyright (C) 2026  Stefan Fabian
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

#ifndef RQML_DOCK_SELECTION_HPP
#define RQML_DOCK_SELECTION_HPP

#include <QObject>

namespace rqml
{

//! Application event filter that selects (focuses) the plugin under a mouse press, so the
//! selection follows the plugin the user interacts with even if the clicked content is not
//! focusable.
class DockSelectionFilter : public QObject
{
public:
  using QObject::QObject;

  bool eventFilter( QObject *watched, QEvent *event ) override;
};

//! Closes the selected plugin, or the only open one, and selects another open plugin.
//! Does nothing if multiple plugins are open and none is selected.
void closeFocusedPlugin();

//! Selects the next (@p forward) or previous open plugin, wrapping around.
//! With nothing selected, selects the first (or last) open plugin.
void cycleFocusedPlugin( bool forward );

} // namespace rqml

#endif // RQML_DOCK_SELECTION_HPP
