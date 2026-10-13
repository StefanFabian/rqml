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

#ifndef RQML_LAST_WINDOW_QUIT_HPP
#define RQML_LAST_WINDOW_QUIT_HPP

#include <QObject>

namespace rqml
{

//! Application event filter that quits the application once no top-level window is visible.
//! Complements QGuiApplication::quitOnLastWindowClosed, which only reacts to window close events
//! and misses floating windows that KDDockWidgets hides or deletes directly.
class LastWindowQuitFilter : public QObject
{
public:
  using QObject::QObject;

  bool eventFilter( QObject *watched, QEvent *event ) override;
};

} // namespace rqml

#endif // RQML_LAST_WINDOW_QUIT_HPP
