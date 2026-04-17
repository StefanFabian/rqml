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

#include "plugin_manager.hpp"
#include "helpers/file_system_watcher.hpp"

#if __has_include( <ament_index_cpp/version.h> )
  #include <ament_index_cpp/version.h>
#else
  #define AMENT_INDEX_CPP_VERSION_GTE( major, minor, patch ) false
#endif

#include <QQmlAbstractUrlInterceptor>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QtCore>
#include <algorithm>
#include <ament_index_cpp/get_resource.hpp>
#include <ament_index_cpp/get_resources.hpp>
#include <filesystem>
#include <yaml-cpp/yaml.h>

#include <kddockwidgets/KDDockWidgets.h>
#include <kddockwidgets/core/DockRegistry.h>
#include <kddockwidgets/core/DockWidget.h>
#include <kddockwidgets/qtquick/views/DockWidget.h>

namespace rqml
{
class PluginManager::UrlInterceptor : public QQmlAbstractUrlInterceptor
{
public:
  explicit UrlInterceptor( PluginManager *loader ) : loader_( loader ) { }

  QUrl intercept( const QUrl &path, DataType type ) override
  {
    if ( type != QmlFile && type != JavaScriptFile )
      return path;
    if ( !path.isLocalFile() )
      return path;
    std::string local_path = path.toLocalFile().toStdString();
    loader_->onFileLoaded( path.toLocalFile() );
    return path;
  }

private:
  PluginManager *loader_;
};

PluginManager::PluginManager( QQmlEngine *engine ) : engine_( engine )
{
#if AMENT_INDEX_CPP_VERSION_GTE( 1, 13, 0 )
  auto resources = ament_index_cpp::get_resources_by_name( "rqml_plugin" );
#else
  auto resources = ament_index_cpp::get_resources( "rqml_plugin" );
#endif
  for ( const auto &[name, path] : resources ) {
    qDebug() << "Loading plugins from" << name.c_str() << "at" << path.c_str();
    loadPluginsFromResource( name, path );
  }
  std::sort( plugins_.begin(), plugins_.end(), []( const RQmlPlugin &lhs, const RQmlPlugin &rhs ) {
    const bool lhs_ungrouped = lhs.group_.isEmpty();
    const bool rhs_ungrouped = rhs.group_.isEmpty();
    if ( lhs_ungrouped != rhs_ungrouped )
      return lhs_ungrouped;

    const int group_cmp = QString::compare( lhs.group_, rhs.group_, Qt::CaseInsensitive );
    if ( group_cmp != 0 )
      return group_cmp < 0;

    const int name_cmp = QString::compare( lhs.name_, rhs.name_, Qt::CaseInsensitive );
    if ( name_cmp != 0 )
      return name_cmp < 0;

    return QString::compare( lhs.id_, rhs.id_, Qt::CaseInsensitive ) < 0;
  } );

  connect( &changed_check_timer_, &QTimer::timeout, this, &PluginManager::checkForChanges );
  changed_check_timer_.setInterval( 1000 );
}

PluginManager::~PluginManager() = default;

KDDockWidgets::Core::DockWidget *PluginManager::factoryFn( const QString &name )
{
  auto it = KDDockWidgets::DockRegistry::self()->dockByName( name );
  if ( it )
    return it;
  qDebug() << "Creating new DockWidget for name" << name;
  QString plugin_id = extractPluginId( name );
  auto it_plugin = findPluginById( plugin_id );
  if ( it_plugin == plugins_.end() )
    return nullptr;

  auto *dw = new KDDockWidgets::QtQuick::DockWidget( name );
  dw->enableAttribute( Qt::WA_DeleteOnClose );
  dw->setTitle( it_plugin->name_ );
  auto *context = new QQmlContext( engine_ );
  auto instance_it = instances_.find( name.toStdString() );
  if ( instance_it == instances_.end() ) {
    qDebug() << "Could not find context to restore. Creating new one for " << name;
    auto instance = std::make_unique<RQmlPluginInstance>( name.toStdString() );
    bool success;
    std::tie( instance_it, success ) =
        instances_.try_emplace( name.toStdString(), std::move( instance ) );
    if ( !success ) {
      qWarning() << "Failed to create new instance for " << name;
      delete dw;
      delete context;
      return nullptr;
    }
  }
  context->setContextObject( instance_it->second.get() );
  dw->setGuestItem( "file://" + it_plugin->path_, context );
  connect( dw, &KDDockWidgets::QtQuick::DockWidget::isOpenChanged, this,
           &PluginManager::onOpenChanged );
  it = KDDockWidgets::DockRegistry::self()->dockByName( name );
  if ( it )
    return it;
  return nullptr;
}

KDDockWidgets::QtQuick::DockWidget *PluginManager::createPlugin( const QString &plugin_id )
{
  auto it_plugin = findPluginById( plugin_id );
  if ( it_plugin == plugins_.end() ) {
    return nullptr;
  }

  if ( auto it_instance = std::find_if( instances_.begin(), instances_.end(),
                                        [&plugin_id]( const auto &pair ) {
                                          return extractPluginId( pair.first ) ==
                                                 plugin_id.toStdString();
                                        } );
       it_plugin->single_instance_ && it_instance != instances_.end() ) {
    auto *widget = KDDockWidgets::DockRegistry::self()->dockByName(
        QString::fromStdString( it_instance->first ) );
    if ( widget && widget->isOpen() ) {
      qWarning() << "Plugin" << plugin_id << "already exists and it is single instance.";
      return nullptr;
    }
    if ( widget ) {
      auto *qdw = dynamic_cast<KDDockWidgets::QtQuick::DockWidget *>( widget->view() );
      if ( !qdw ) {
        qWarning() << "Failed to cast existing widget to QtQuick DockWidget for plugin" << plugin_id;
        return nullptr;
      }
      widget->open();
      return qdw;
    }
  }
  std::string name = createUniqueName( plugin_id.toStdString() );
  auto instance = new RQmlPluginInstance( name );
  if ( !instances_.try_emplace( name, instance ).second ) {
    qWarning() << "Failed to create new instance for " << name.c_str();
    delete instance;
    return nullptr;
  }

  auto *dw = new KDDockWidgets::QtQuick::DockWidget( instance->unique_name_ );
  dw->setTitle( it_plugin->name_ );
  dw->enableAttribute( Qt::WA_DeleteOnClose );
  auto *context = new QQmlContext( engine_->rootContext() );
  context->setContextObject( instance );
  dw->setGuestItem( "file://" + it_plugin->path_, context );
  connect( dw, &KDDockWidgets::QtQuick::DockWidget::isOpenChanged, this,
           &PluginManager::onOpenChanged );
  dw->open();
  return dw;
}

bool PluginManager::canCreatePlugin( const QString &plugin_id ) const
{
  auto it_plugin =
      std::find_if( plugins_.begin(), plugins_.end(),
                    [&plugin_id]( const RQmlPlugin &plugin ) { return plugin.id_ == plugin_id; } );
  if ( it_plugin == plugins_.end() )
    return false;

  if ( !it_plugin->single_instance_ )
    return true;

  auto it_instance =
      std::find_if( instances_.begin(), instances_.end(), [&plugin_id]( const auto &pair ) {
        return extractPluginId( pair.first ) == plugin_id.toStdString();
      } );
  if ( it_instance == instances_.end() )
    return true;

  auto *widget =
      KDDockWidgets::DockRegistry::self()->dockByName( QString::fromStdString( it_instance->first ) );
  return !( widget && widget->isOpen() );
}

std::vector<RQmlPlugin>::const_iterator PluginManager::findPluginById( const QString &plugin_id )
{
  auto it_plugin =
      std::find_if( plugins_.begin(), plugins_.end(),
                    [&plugin_id]( const RQmlPlugin &plugin ) { return plugin.id_ == plugin_id; } );
  if ( it_plugin == plugins_.end() ) {
    qWarning() << "Plugin" << plugin_id << "not found.";
    qWarning() << "Available plugins:";
    for ( const auto &plugin : plugins_ ) {
      qWarning() << "-" << plugin.id_ << " " << plugin.name_ << " " << plugin.path_;
    }
  }
  return it_plugin;
}

void PluginManager::setLiveReloadEnabled( bool value )
{
  if ( live_reload_enabled_ == value )
    return;
  live_reload_enabled_ = value;
  if ( !value ) {
    watcher_.reset();
    engine_->removeUrlInterceptor( interceptor_.get() );
    changed_check_timer_.stop();
    return;
  }

  watcher_ = std::make_unique<FileSystemWatcher>();
  if ( !interceptor_ ) {
    interceptor_ = std::make_unique<UrlInterceptor>( this );
  }
  engine_->addUrlInterceptor( interceptor_.get() );

  reloadWidgets();
  changed_check_timer_.start();
}

void PluginManager::reloadWidgets()
{
  engine_->clearComponentCache();
  for ( auto &dw : KDDockWidgets::DockRegistry::self()->dockwidgets() ) {
    auto qdw = dynamic_cast<KDDockWidgets::QtQuick::DockWidget *>( dw->view() );

    if ( !qdw )
      continue;

    auto *context = qmlContext( qdw->guestItem() );
    auto plugin_id = extractPluginId( qdw->uniqueName() );
    auto it_plugin = findPluginById( plugin_id );
    if ( it_plugin == plugins_.end() )
      continue;
    qdw->setGuestItem( "file://" + it_plugin->path_, context );
  }
}

void PluginManager::onFileLoaded( const QString &path )
{
  watcher_->addWatch( path.toStdString() );
}

void PluginManager::checkForChanges()
{
  if ( !watcher_->checkForChanges() )
    return;
  qInfo() << "Detected changes in plugin files, reloading widgets.";
  reloadWidgets();
}

void PluginManager::loadPluginsFromResource( const std::string &name, const std::string &path )
{
  std::string plugin_description;
  try {
#if AMENT_INDEX_CPP_VERSION_GTE( 1, 13, 0 )
    auto path_with_resource = ament_index_cpp::get_resource( "rqml_plugin", name );
    plugin_description = path_with_resource.contents;
#else
    ament_index_cpp::get_resource( "rqml_plugin", name, plugin_description );
#endif
  } catch ( const std::runtime_error &e ) {
    qWarning() << "Failed to load plugin description for" << name.c_str() << ":" << e.what();
    return;
  }
  YAML::Node plugins;
  try {
    YAML::Node node = YAML::Load( plugin_description );
    plugins = node["plugins"];
  } catch ( const YAML::ParserException &e ) {
    qWarning() << "Failed to parse plugin description for" << name.c_str() << ":" << e.what();
  }
  if ( !plugins || !plugins.IsSequence() ) {
    qWarning() << "Plugin description for" << name.c_str()
               << "does not contain a key plugins or it is not a sequence.";
    return;
  }

  for ( const auto &plugin : plugins ) {
    try {
      const auto &plugin_id = plugin["id"].as<std::string>();
      const auto &plugin_name = plugin["name"].as<std::string>();
      const auto &plugin_path = plugin["path"].as<std::string>();
      const auto &plugin_group = plugin["group"].as<std::string>( "" );
      const auto &single_instance = plugin["single_instance"].as<bool>( false );
      if ( plugin_id.empty() || plugin_name.empty() || plugin_path.empty() ) {
        qWarning() << "Plugin description for" << name.c_str() << "is missing id, name or path.";
        continue;
      }
      const auto &full_path = std::filesystem::path( path ) / plugin_path;
      qDebug() << "Loaded plugin" << plugin_name.c_str() << "from" << full_path.c_str();
      plugins_.emplace_back( plugin_id, plugin_name, full_path, plugin_group, single_instance );
    } catch ( const YAML::Exception &e ) {
      qWarning() << "Failed to parse plugin description for" << name.c_str() << ":" << e.what();
      continue;
    }
  }
}

void PluginManager::onOpenChanged( bool open )
{
  if ( open )
    return;
  auto *widget = dynamic_cast<KDDockWidgets::QtQuick::DockWidget *>( QObject::sender() );
  if ( widget == nullptr )
    return;
  qDebug() << "Deleting " << widget->uniqueName();
  widget->deleteLater();
}
} // namespace rqml
