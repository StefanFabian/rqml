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
#include "plugin_manager.hpp"

#include <filesystem>

#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>

#include <kddockwidgets/Config.h>
#include <kddockwidgets/qtquick/Platform.h>
#include <kddockwidgets/qtquick/views/DockWidget.h>

using namespace rqml;

class RQml
{
  RQml()
  {
    auto &kd_config = KDDockWidgets::Config::self();
    kd_config.setFlags( KDDockWidgets::Config::Flag_TitleBarHasMinimizeButton |
                        KDDockWidgets::Config::Flag_NativeTitleBar |
                        KDDockWidgets::Config::Flag_TitleBarHasMaximizeButton |
                        KDDockWidgets::Config::Flag_DoubleClickMaximizes |
                        KDDockWidgets::Config::Flag_TitleBarIsFocusable );
    kd_config.setInternalFlags( static_cast<KDDockWidgets::Config::InternalFlag>(
        KDDockWidgets::Config::InternalFlag_DontUseParentForFloatingWindows |
        KDDockWidgets::Config::InternalFlag_NoDeleteLaterWorkaround |
        KDDockWidgets::Config::InternalFlag_DontUseQtToolWindowsForFloatingWindows ) );
    KDDockWidgets::Config::self().setDockWidgetFactoryFunc(
        []( const QString &name ) { return RQml::instance().factoryFn( name ); } );
  }

public:
  static RQml &instance()
  {
    static RQml instance;
    return instance;
  }
  RQml( const RQml & ) = delete;
  RQml &operator=( const RQml & ) = delete;
  RQml( RQml && ) = delete;
  RQml &operator=( RQml && ) = delete;

  void init( QQmlEngine *engine )
  {
    engine_ = engine;
    plugin_loader_ = std::make_shared<PluginManager>( engine );
    config_manager_ = std::make_unique<ConfigManager>( plugin_loader_ );
  }

  QVariantList plugins() const
  {
    QVariantList plugins;
    for ( const auto &plugin : plugin_loader_->plugins() ) {
      plugins.push_back( QVariant::fromValue( plugin ) );
    }
    return plugins;
  }
  KDDockWidgets::Core::DockWidget *factoryFn( const QString &name )
  {
    return plugin_loader_->factoryFn( name );
  }

  KDDockWidgets::QtQuick::DockWidget *createPlugin( const QString &plugin_id )
  {
    return plugin_loader_->createPlugin( plugin_id );
  }

  void save() { config_manager_->save(); }
  void save( const QString &path ) { config_manager_->save( path.toStdString() ); }
  void load( const QString &path ) { config_manager_->load( path.toStdString() ); }

  void setDevMode( bool enabled ) { plugin_loader_->setLiveReloadEnabled( enabled ); }

  ConfigManager &configManager() { return *config_manager_; }

private:
  std::unique_ptr<ConfigManager> config_manager_;
  PluginManager::SharedPtr plugin_loader_;
  QQmlEngine *engine_ = nullptr;
};

class RQmlWrapper : public QObject
{
  Q_OBJECT
  Q_PROPERTY( QVariantList plugins READ plugins CONSTANT )
  Q_PROPERTY( QVariantList configDirectories READ configDirectories NOTIFY configDirectoriesChanged )
  Q_PROPERTY( QVariantMap currentConfig READ currentConfig NOTIFY currentConfigChanged )
  Q_PROPERTY( QVariantList configs READ configs NOTIFY configsChanged )
  Q_PROPERTY( QVariantList recentConfigs READ recentConfigs NOTIFY currentConfigChanged )
  Q_PROPERTY( bool devMode READ devMode WRITE setDevMode NOTIFY devModeChanged )
public:
  using QObject::QObject;

  RQmlWrapper( QObject *parent = nullptr ) : QObject( parent )
  {
    connect( &RQml::instance().configManager(), &ConfigManager::configsChanged, this,
             &RQmlWrapper::configsChanged );
    connect( &RQml::instance().configManager(), &ConfigManager::currentConfigChanged, this,
             &RQmlWrapper::currentConfigChanged );
    connect( &RQml::instance().configManager(), &ConfigManager::configDirectoriesChanged, this,
             &RQmlWrapper::configDirectoriesChanged );
  }

  Q_INVOKABLE QObject *createPlugin( const QString &plugin_id )
  {
    return RQml::instance().createPlugin( plugin_id );
  }

  Q_INVOKABLE void save( const QString &path ) { return RQml::instance().save( path ); }

  Q_INVOKABLE void save() { return RQml::instance().save(); }

  Q_INVOKABLE void load( const QString &path ) { return RQml::instance().load( path ); }

  QVariantList plugins() const { return RQml::instance().plugins(); }

  Q_INVOKABLE bool fileExists( const QString &path ) const
  {
    if ( path.isEmpty() )
      return false;
    return QFile::exists( path );
  }

  Q_INVOKABLE QString readFile( const QString &path ) const
  {
    if ( path.isEmpty() )
      return QString();
    QFile file( path );
    if ( !file.open( QIODevice::ReadOnly | QIODevice::Text ) ) {
      qWarning() << "Failed to open file for reading:" << path;
      return QString();
    }
    return QString::fromUtf8( file.readAll() );
  }

  Q_INVOKABLE bool writeFile( const QString &path, const QString &text ) const
  {
    if ( path.isEmpty() )
      return false;
    QFile file( path );
    if ( !file.open( QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate ) ) {
      qWarning() << "Failed to open file for writing:" << path;
      return false;
    }
    file.write( text.toUtf8() );
    return true;
  }

  QVariantMap currentConfig() const
  {
    const auto &config = RQml::instance().configManager().currentConfig();
    QVariantMap result;
    result["path"] = QString::fromStdString( config );
    return result;
  }

  QVariantList configs() const
  {
    QVariantList result;
    const auto &configs = RQml::instance().configManager().configs();
    for ( const auto &config : configs ) {
      QVariantMap map;
      map["path"] = QString::fromStdString( config.path );
      result.append( map );
    }
    return result;
  }

  QVariantList recentConfigs() const
  {
    QVariantList result;
    const auto &configs = RQml::instance().configManager().recentConfigs();
    for ( const auto &path : configs ) {
      QVariantMap map;
      map["path"] = QString::fromStdString( path );
      result.append( map );
    }
    return result;
  }

  QVariantList configDirectories() const
  {
    QVariantList result;
    const auto &dirs = RQml::instance().configManager().configDirectories();
    for ( const auto &dir : dirs ) { result.append( QString::fromStdString( dir ) ); }
    return result;
  }

  Q_INVOKABLE void addConfigDirectory( const QString &directory )
  {
    RQml::instance().configManager().addConfigDirectory( directory.toStdString() );
  }

  Q_INVOKABLE void removeConfigDirectory( const QString &directory )
  {
    RQml::instance().configManager().removeConfigDirectory( directory.toStdString() );
  }

  bool devMode() const { return dev_mode_; }
  void setDevMode( bool enabled )
  {
    if ( dev_mode_ == enabled )
      return;
    dev_mode_ = enabled;
    RQml::instance().setDevMode( dev_mode_ );
    emit devModeChanged();
  }

  Q_INVOKABLE void copyTextToClipboard( const QString &text ) const
  {
    QGuiApplication::clipboard()->setText( text );
  }

  Q_INVOKABLE bool canCreateDesktopEntry() const
  {
#ifdef Q_OS_LINUX // Check if on linux
    QString applications_path =
        QStandardPaths::writableLocation( QStandardPaths::ApplicationsLocation );
    return QFile::exists( applications_path );
#else
    return false;
#endif
  }

  Q_INVOKABLE bool createDesktopEntry()
  {
#ifdef Q_OS_LINUX // Check if on linux
    QString applications_path =
        QStandardPaths::writableLocation( QStandardPaths::ApplicationsLocation );
    QFile desktop_entry_file( ":/assets/rqml.desktop.in" );
    if ( !desktop_entry_file.exists() ) {
      qWarning() << "Desktop entry template file not found in resources.";
      return false;
    }
    if ( !desktop_entry_file.open( QIODevice::ReadOnly ) ) {
      qWarning() << "Failed to open desktop entry template file.";
      return false;
    }
    QString desktop_entry = desktop_entry_file.readAll();
    desktop_entry.replace( "@CMAKE_INSTALL_PREFIX@", CMAKE_INSTALL_PREFIX );
    QFile out_file( applications_path + "/rqml.desktop" );
    if ( !out_file.open( QIODevice::WriteOnly | QIODevice::Truncate ) ) {
      qWarning() << "Failed to create desktop entry file at" << out_file.fileName();
      return false;
    }
    out_file.write( desktop_entry.toUtf8() );
    out_file.close();
    qInfo() << "Desktop entry created at" << out_file.fileName();
    return true;
#else
    qWarning() << "Desktop entry creation is only supported on Linux.";
    return false;
#endif
  }

signals:
  void configsChanged();
  void devModeChanged();
  void currentConfigChanged();
  void configDirectoriesChanged();

private:
  bool dev_mode_ = false;
};

int main( int argc, char *argv[] )
{
  QGuiApplication app( argc, argv );

  std::string config_dir =
      QStandardPaths::writableLocation( QStandardPaths::AppConfigLocation ).toStdString();
  if ( !std::filesystem::is_directory( config_dir ) ) {
    std::filesystem::create_directories( config_dir );
  }
  // Creating context wrapper before engine so it isn't destroyed before main.qml is unloaded
  std::unique_ptr<RQmlWrapper> rqml_context;
  QQmlApplicationEngine engine;
  KDDockWidgets::QtQuick::Platform::instance()->setQmlEngine( &engine );
  RQml::instance().init( &engine );
  rqml_context = std::make_unique<RQmlWrapper>();
  qRegisterMetaType<RQmlPlugin>();
  engine.rootContext()->setContextProperty( "RQml", rqml_context.get() );
  engine.rootContext()->setContextProperty( "QtVersion", QString( qVersion() ) );
  engine.load( QUrl( QStringLiteral( "qrc:/qml/main.qml" ) ) );
  app.setWindowIcon( QIcon( ":/assets/app_icon.svg" ) );

  // Initialize and load config
  RQml::instance().configManager().init();

  if ( engine.rootObjects().isEmpty() )
    return -1;

  return QGuiApplication::exec();
}

#include "rqml.moc"
