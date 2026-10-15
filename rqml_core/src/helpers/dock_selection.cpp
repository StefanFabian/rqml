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

#include "dock_selection.hpp"

#include <QMouseEvent>
#include <QQuickItem>
#include <QQuickWindow>

#include <kddockwidgets/core/DockRegistry.h>
#include <kddockwidgets/core/FloatingWindow.h>
#include <kddockwidgets/core/Layout.h>
#include <kddockwidgets/core/MainWindow.h>
#include <kddockwidgets/qtquick/views/DockWidget.h>

namespace rqml
{
namespace
{
using DockWidget = KDDockWidgets::Core::DockWidget;

//! Returns the open, currently visible plugin in @p window at @p scene_pos.
DockWidget *dockAt( const QQuickWindow *window, const QPointF &scene_pos )
{
  for ( auto *dock_widget : KDDockWidgets::DockRegistry::self()->dockwidgets() ) {
    if ( dock_widget == nullptr || !dock_widget->isOpen() || !dock_widget->isCurrentTab() )
      continue;

    auto *dock_item = KDDockWidgets::QtQuick::asQQuickItem( dock_widget );
    // Window-local coordinates since global window positions are unknown on Wayland.
    if ( dock_item == nullptr || dock_item->window() != window )
      continue;

    if ( dock_item->contains( dock_item->mapFromScene( scene_pos ) ) )
      return dock_widget;
  }
  return nullptr;
}

//! Returns whether @p scene_pos in @p window is on an open popup (e.g. a ComboBox list), which may
//! extend over another plugin.
bool isOnPopup( const QQuickWindow *window, const QPointF &scene_pos )
{
  for ( const auto *child : window->contentItem()->childItems() ) {
    if ( !child->isVisible() || !child->inherits( "QQuickOverlay" ) )
      continue;
    for ( const auto *popup : child->childItems() ) {
      if ( popup->isVisible() && popup->contains( popup->mapFromScene( scene_pos ) ) )
        return true;
    }
  }
  return false;
}

//! Returns the open plugins in layout order: main windows first, then floating windows, each in
//! split order with tabs in tab bar order. Plugins outside a layout (e.g. side bar) are skipped.
QVector<DockWidget *> openDocks()
{
  auto *registry = KDDockWidgets::DockRegistry::self();
  QVector<DockWidget *> open_docks;
  const auto append_open = [&open_docks]( const KDDockWidgets::Core::Layout *layout ) {
    for ( auto *dock_widget : layout->dockWidgets() ) {
      if ( dock_widget->isOpen() )
        open_docks.push_back( dock_widget );
    }
  };
  for ( const auto *main_window : registry->mainwindows() ) append_open( main_window->layout() );
  for ( const auto *floating_window : registry->floatingWindows() )
    append_open( floating_window->layout() );
  return open_docks;
}

//! Returns another open plugin to select after @p closing is closed, preferring a currently
//! visible one. Returns nullptr if @p closing is the only open plugin.
DockWidget *nextDockAfter( const DockWidget *closing, const QVector<DockWidget *> &open_docks )
{
  DockWidget *fallback = nullptr;
  for ( auto *dock_widget : open_docks ) {
    if ( dock_widget == closing )
      continue;
    if ( dock_widget->isCurrentTab() )
      return dock_widget;
    if ( fallback == nullptr )
      fallback = dock_widget;
  }
  return fallback;
}

//! Makes @p dock_widget the selected (focused) plugin, revealing it if it is a background tab
//! and activating its window.
void focusDock( DockWidget *dock_widget, Qt::FocusReason reason )
{
  if ( dock_widget == nullptr )
    return;
  dock_widget->raise();
  auto *dock_item = KDDockWidgets::QtQuick::asQQuickItem( dock_widget );
  if ( dock_item == nullptr )
    return;
  dock_item->forceActiveFocus( reason );
  // Focus inside an inactive window does not change the application focus object.
  if ( auto *window = dock_item->window() )
    window->requestActivate();
}

//! Selects the plugin at @p scene_pos in @p window. A focusable child under the press still
//! receives focus afterwards.
void selectDockAt( const QQuickWindow *window, const QPointF &scene_pos )
{
  // Moving focus would close the popup before it receives the press.
  if ( isOnPopup( window, scene_pos ) )
    return;
  auto *dock_widget = dockAt( window, scene_pos );
  if ( dock_widget == nullptr ||
       KDDockWidgets::DockRegistry::self()->focusedDockWidget() == dock_widget )
    return;
  focusDock( dock_widget, Qt::MouseFocusReason );
}

//! Moves focus from a selected plugin that holds the focus itself (nothing inside is focused) to
//! its neighbor in the tab focus chain. Qt would otherwise start the chain at the window start
//! since plugins are not tab stops. Returns whether focus was moved.
bool tabFromSelectedDock( const QQuickWindow *window, const QKeyEvent *event )
{
  if ( event->modifiers() & ( Qt::ControlModifier | Qt::AltModifier ) )
    return false;
  const bool backward = event->key() == Qt::Key_Backtab ||
                        ( event->key() == Qt::Key_Tab && ( event->modifiers() & Qt::ShiftModifier ) );
  if ( !backward && event->key() != Qt::Key_Tab )
    return false;
  auto *dock_item = qobject_cast<KDDockWidgets::QtQuick::DockWidget *>( window->activeFocusItem() );
  if ( dock_item == nullptr )
    return false;
  auto *next_item = dock_item->nextItemInFocusChain( !backward );
  if ( next_item == nullptr )
    return false;
  next_item->forceActiveFocus( backward ? Qt::BacktabFocusReason : Qt::TabFocusReason );
  return true;
}
} // namespace

bool DockSelectionFilter::eventFilter( QObject *watched, QEvent *event )
{
  // Handle only the delivery to the window, the filter also sees the event for every item.
  if ( event->type() == QEvent::MouseButtonPress ) {
    if ( const auto *window = qobject_cast<QQuickWindow *>( watched ) )
      selectDockAt( window, static_cast<QMouseEvent *>( event )->scenePosition() );
  } else if ( event->type() == QEvent::KeyPress ) {
    if ( const auto *window = qobject_cast<QQuickWindow *>( watched );
         window != nullptr && tabFromSelectedDock( window, static_cast<QKeyEvent *>( event ) ) )
      return true;
  }
  return QObject::eventFilter( watched, event );
}

void closeFocusedPlugin()
{
  const auto open_docks = openDocks();
  if ( open_docks.isEmpty() )
    return;

  DockWidget *target = open_docks.first();
  if ( open_docks.size() > 1 ) {
    // Only close the highlighted plugin rather than guess, so the user sees what will be closed.
    target = KDDockWidgets::DockRegistry::self()->focusedDockWidget();
    if ( target == nullptr || !target->isOpen() )
      return;
  }

  // Selection follows the close so repeated Ctrl+W keeps closing the highlighted plugin.
  auto *next = nextDockAfter( target, open_docks );
  target->close();
  focusDock( next, Qt::OtherFocusReason );
}

void cycleFocusedPlugin( bool forward )
{
  const auto open_docks = openDocks();
  if ( open_docks.isEmpty() )
    return;

  const int count = open_docks.size();
  const int current = open_docks.indexOf( KDDockWidgets::DockRegistry::self()->focusedDockWidget() );
  const int next = current < 0 ? ( forward ? 0 : count - 1 )
                               : ( current + ( forward ? 1 : -1 ) + count ) % count;
  focusDock( open_docks[next], Qt::TabFocusReason );
}
} // namespace rqml
