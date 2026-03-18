#include <QMap>
#include <QQmlContext>
#include <QQmlEngine>
#include <QtQml>
#include <QtQuickTest/quicktest.h>
#include <qml6_ros2_plugin/io.hpp>

class MockRQml : public QObject
{
  Q_OBJECT
public:
  Q_INVOKABLE QString readFile( const QString &path ) const
  {
    return files.value( path, QString() );
  }
  Q_INVOKABLE bool writeFile( const QString &path, const QString &text )
  {
    files[path] = text;
    return true;
  }
  Q_INVOKABLE bool fileExists( const QString &path ) const { return files.contains( path ); }

  QMap<QString, QString> files;
};

class MockRos2IO : public QObject
{
  Q_OBJECT
public:
  // Forward to the real qml6_ros2_plugin::IO to test actual YAML conversion behavior
  Q_INVOKABLE bool writeYaml( const QString &path, const QVariant &value )
  {
    return io_.writeYaml( path, value );
  }
  Q_INVOKABLE QVariant readYaml( const QString &path ) { return io_.readYaml( path ); }

private:
  qml6_ros2_plugin::IO io_;
};

class Setup : public QObject
{
  Q_OBJECT
public:
  Setup() { }

public slots:
  void qmlEngineAvailable( QQmlEngine *engine )
  {
    engine->rootContext()->setContextProperty( "RQml", &mock_rqml_ );
    qmlRegisterSingletonInstance( "MockRos2", 1, 0, "MockRos2IO", &mock_io_ );
  }

private:
  MockRQml mock_rqml_;
  MockRos2IO mock_io_;
};

QUICK_TEST_MAIN_WITH_SETUP( ParameterEditorTest, Setup )
#include "test_parameter_editor.moc"
