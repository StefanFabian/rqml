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

#include "config_manager.hpp"
#include "helpers/file_system_watcher.hpp"
#include "qqml_property_map_json.h"
#include <QByteArray>
#include <QStandardPaths>
#include <fstream>
#include <kddockwidgets/LayoutSaver.h>
#include <kddockwidgets/core/DockRegistry.h>
#include <nlohmann/json.hpp>

namespace rqml
{
ConfigManager::ConfigManager( PluginManager::SharedPtr plugin_manager )
    : settings_( "rqml" ), plugin_manager_( std::move( plugin_manager ) ),
      layout_saver_( std::make_unique<KDDockWidgets::LayoutSaver>() )
{
  file_system_watcher_ = std::make_unique<FileSystemWatcher>();

  // Load config directories
  settings_.beginReadArray( "configDirectories" );
  int size = settings_.value( "size", 0 ).toInt();
  for ( int i = 0; i < size; ++i ) {
    settings_.setArrayIndex( i );
    config_directories_.emplace_back( settings_.value( "directory" ).toString().toStdString() );
  }
  settings_.endArray();
  if ( config_directories_.empty() ) {
    config_directories_.push_back(
        QStandardPaths::writableLocation( QStandardPaths::AppConfigLocation ).toStdString() );
  }

  loadConfigs();

  // Load recent configs
  if ( settings_.contains( "maxRecentConfigs" ) ) {
    max_recent_configs_ = settings_.value( "maxRecentConfigs" ).toUInt();
  } else {
    settings_.setValue( "maxRecentConfigs", QVariant::fromValue<size_t>( max_recent_configs_ ) );
  }
  settings_.beginReadArray( "recentConfigs" );
  size = settings_.value( "size", 0 ).toInt();
  for ( int i = 0; i < size; ++i ) {
    settings_.setArrayIndex( i );
    std::filesystem::path path = settings_.value( "configPath" ).toString().toStdString();
    std::error_code error;
    if ( std::filesystem::exists( path, error ) )
      recent_configs_.emplace_back( path );
  }
  settings_.endArray();

  // Load current config
  if ( !settings_.contains( "currentConfig" ) ) {
    auto it = configs_.begin();
    if ( it == configs_.end() )
      it = configs_.insert( it, Config{ config_directories_.front() + "/default.rqml" } );
    current_config_ = it->path;
  } else {
    current_config_ = settings_.value( "currentConfig" ).toString().toStdString();
    if ( std::find_if( configs_.begin(), configs_.end(), [this]( const Config &config ) {
           return config.path == current_config_;
         } ) == configs_.end() ) {
      configs_.insert( configs_.begin(), Config{ current_config_ } );
    }
  }

  file_check_timer_.setInterval( 1000 );
  connect( &file_check_timer_, &QTimer::timeout, this, &ConfigManager::checkForFileChanges );
  file_check_timer_.start();
}

ConfigManager::~ConfigManager() = default;

void ConfigManager::init()
{
  if ( std::filesystem::is_regular_file( current_config_ ) ) {
    load( current_config_ );
  } else {
    save();
  }
}

void ConfigManager::addConfigDirectory( const std::filesystem::path &directory )
{
  std::string path = directory;
  if ( path.substr( 0, 7 ) == "file://" ) {
    path = path.substr( 7 );
  }
  if ( std::find( config_directories_.begin(), config_directories_.end(), path ) !=
       config_directories_.end() )
    return;
  if ( !std::filesystem::is_directory( path ) ) {
    qWarning() << "Config directory does not exist:" << QString::fromStdString( path );
    return;
  }
  config_directories_.push_back( path );
  saveConfigDirectories();
  emit configDirectoriesChanged();
  loadConfigs();
}

void ConfigManager::removeConfigDirectory( const std::filesystem::path &directory )
{
  std::string path = directory;
  if ( path.substr( 0, 7 ) == "file://" ) {
    path = path.substr( 7 );
  }
  auto it = std::find( config_directories_.begin(), config_directories_.end(), path );
  if ( it == config_directories_.end() )
    return;
  config_directories_.erase( it );
  saveConfigDirectories();
  emit configDirectoriesChanged();
  loadConfigs();
}

const std::filesystem::path &ConfigManager::currentConfig() const { return current_config_; }

Config ConfigManager::getConfig( const std::filesystem::path &path ) const
{
  auto it = std::find_if( configs_.begin(), configs_.end(),
                          [&path]( const Config &config ) { return config.path == path; } );
  if ( it == configs_.end() ) {
    throw std::out_of_range( "Config not found: " + path.string() );
  }
  return *it;
}

const std::vector<std::filesystem::path> &ConfigManager::recentConfigs() const
{
  return recent_configs_;
}

const std::vector<Config> &ConfigManager::configs() const { return configs_; }

const std::vector<std::string> &ConfigManager::configDirectories() const
{
  return config_directories_;
}
void ConfigManager::save() { save( current_config_ ); }
void ConfigManager::save( const std::string &path )
{
  QByteArray array = layout_saver_->serializeLayout();
  nlohmann::json json = nlohmann::json::parse( array.toStdString() );
  json["enableLiveReload"] = plugin_manager_->liveReloadEnabled();
  // Remove closed widgets
  if ( json["allDockWidgets"].is_array() ) {
    json["allDockWidgets"].erase(
        std::remove_if( json["allDockWidgets"].begin(), json["allDockWidgets"].end(),
                        []( const nlohmann::json &widget ) {
                          auto dw = KDDockWidgets::DockRegistry::self()->dockByName(
                              QString::fromStdString( widget["uniqueName"] ) );
                          return !dw || !dw->isOpen();
                        } ),
        json["allDockWidgets"].end() );
    json["closedDockWidgets"] = nlohmann::json::array();
  }
  for ( auto &widget : json["allDockWidgets"] ) {
    const std::string instance_name = widget["uniqueName"];
    if ( !plugin_manager_->hasInstance( instance_name ) )
      continue;
    widget["context"] = plugin_manager_->getInstance( instance_name ).context_;
  }
  std::string s_path = path;
  if ( path.substr( 0, 7 ) == "file://" ) {
    s_path = s_path.substr( 7 );
  }
  std::ofstream file( s_path );
  if ( !file.is_open() ) {
    qWarning() << "Failed to open file for writing:" << s_path.c_str();
    return;
  }
  file << json.dump( 2 );
  file.close();
  auto it = std::find_if( configs_.begin(), configs_.end(),
                          [&s_path]( const Config &config ) { return config.path == s_path; } );
  if ( it == configs_.end() ) {
    configs_.insert( configs_.begin(), Config{ s_path } );
    emit configsChanged();
  }
  setCurrentConfig( s_path );
}

void ConfigManager::load( const std::string &path )
{
  std::string s_path = path;
  if ( path.substr( 0, 7 ) == "file://" ) {
    s_path = path.substr( 7 );
  }
  std::ifstream file( s_path );
  if ( !file.is_open() ) {
    qWarning() << "Failed to open file:" << s_path.c_str();
    return;
  }
  nlohmann::json json;
  try {
    file >> json;
  } catch ( nlohmann::json::exception &e ) {
    qWarning() << "Failed to parse json data from file: " << s_path.c_str() << "\r\n"
               << "Error: " << e.what();
    file.close();
    return;
  }
  file.close();
  plugin_manager_->setLiveReloadEnabled( json.value( "enableLiveReload", false ) );

  auto *registry = KDDockWidgets::DockRegistry::self();
  for ( auto *widget : registry->dockwidgets() ) { delete widget; }

  plugin_manager_->clearInstances();
  for ( auto &widget : json["allDockWidgets"] ) {
    auto instance = std::make_unique<RQmlPluginInstance>( widget["uniqueName"].get<std::string>() );
    QVariantMap map = widget["context"].get<QVariantMap>();
    for ( auto it = map.begin(); it != map.end(); ++it ) {
      instance->context_.insert( it.key(), it.value() );
    }
    plugin_manager_->registerInstance( std::move( instance ) );
  }
  qDebug() << "Restoring layout";
  if ( !layout_saver_->restoreLayout( QByteArray::fromStdString( json.dump( 2 ) ) ) ) {
    qWarning() << "Failed to restore layout from: " << s_path.c_str();
    plugin_manager_->clearInstances();
  }
  setCurrentConfig( s_path );
}

void ConfigManager::loadConfigs()
{
  std::vector<Config> configs;
  file_system_watcher_->removeAllWatches();
  for ( const auto &dir : config_directories_ ) {
    if ( !std::filesystem::is_directory( dir ) )
      continue;
    file_system_watcher_->addWatch( dir );
    for ( const auto &entry : std::filesystem::directory_iterator(
              dir, std::filesystem::directory_options::skip_permission_denied ) ) {
      if ( entry.is_regular_file() ) {
        const auto &path = entry.path();
        if ( path.extension() == ".rqml" ) {
          configs.emplace_back( Config{ path.string() } );
        }
      }
    }
  }
  if ( configs_.size() != configs.size() ||
       !std::equal( configs_.begin(), configs_.end(), configs.begin(),
                    []( const Config &a, const Config &b ) { return a.path == b.path; } ) ) {
    configs_ = std::move( configs );
    emit configsChanged();
  }
}
void ConfigManager::saveConfigDirectories()
{
  settings_.beginWriteArray( "configDirectories" );
  settings_.setValue( "size", static_cast<int>( config_directories_.size() ) );
  for ( size_t i = 0; i < config_directories_.size(); ++i ) {
    settings_.setArrayIndex( static_cast<int>( i ) );
    settings_.setValue( "directory", QString::fromStdString( config_directories_[i] ) );
  }
  settings_.endArray();
}

void ConfigManager::saveRecentConfigs()
{
  if ( recent_configs_.size() > max_recent_configs_ ) {
    recent_configs_.resize( max_recent_configs_ );
  }
  settings_.beginWriteArray( "recentConfigs" );
  settings_.setValue( "size", static_cast<int>( recent_configs_.size() ) );
  for ( size_t i = 0; i < recent_configs_.size(); ++i ) {
    settings_.setArrayIndex( static_cast<int>( i ) );
    settings_.setValue( "configPath", QString::fromStdString( recent_configs_[i] ) );
  }
  settings_.endArray();
}

void ConfigManager::checkForFileChanges()
{
  if ( !file_system_watcher_->checkForChanges() )
    return;
  loadConfigs();
}

void ConfigManager::setCurrentConfig( const std::string &path )
{
  if ( current_config_ == path )
    return;
  settings_.setValue( "currentConfig", QString::fromStdString( path ) );
  current_config_ = path;
  // Update recent configs
  recent_configs_.erase(
      std::remove( recent_configs_.begin(), recent_configs_.end(), current_config_ ),
      recent_configs_.end() );
  recent_configs_.insert( recent_configs_.begin(), current_config_ );
  saveRecentConfigs();
  emit currentConfigChanged();
}

} // namespace rqml
