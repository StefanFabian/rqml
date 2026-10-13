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

#include "last_window_quit.hpp"

#include <algorithm>

#include <QEvent>
#include <QGuiApplication>
#include <QWindow>

namespace rqml
{
namespace
{
void quitIfNoWindowVisible()
{
  // Same windows Qt counts for quitOnLastWindowClosed: transient windows (dialogs) don't count.
  const auto windows = QGuiApplication::topLevelWindows();
  const bool any_visible = std::any_of( windows.begin(), windows.end(), []( const QWindow *window ) {
    return window->isVisible() && window->transientParent() == nullptr &&
           window->type() != Qt::ToolTip;
  } );
  if ( !any_visible )
    QGuiApplication::quit();
}
} // namespace

bool LastWindowQuitFilter::eventFilter( QObject *watched, QEvent *event )
{
  // Queued so the check runs after a deleted window is gone and ignores hides followed by a show.
  if ( event->type() == QEvent::Hide && watched->isWindowType() )
    QMetaObject::invokeMethod( this, &quitIfNoWindowVisible, Qt::QueuedConnection );
  return QObject::eventFilter( watched, event );
}

} // namespace rqml
