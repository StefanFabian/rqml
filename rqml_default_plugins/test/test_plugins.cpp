#include "mock_classes.hpp"
#include "mock_ros2.hpp"
#include <QDir>
#include <QGuiApplication>
#include <QObject>
#include <QQmlContext>
#include <QQmlEngine>
#include <QtQml>
#include <QtQuickTest/quicktest.h>
#include <qml6_ros2_plugin/goal_status.hpp>
#include <qml6_ros2_plugin/message_item_model.hpp>

class Setup : public QObject
{
  Q_OBJECT
public:
  Setup();
public slots:
  void qmlEngineAvailable( QQmlEngine *engine );

private:
  MockRQml mockRqml_;
  MockRos2 mockRos2_;
};

Setup::Setup() { s_mockRos2 = &mockRos2_; }

void Setup::qmlEngineAvailable( QQmlEngine *engine )
{
  const QDir testDir( QStringLiteral( QUICK_TEST_SOURCE_DIR ) );

  engine->rootContext()->setContextProperty( "RQml", &mockRqml_ );
  engine->addImportPath( testDir.absoluteFilePath( "../../rqml_core" ) );
  engine->rootContext()->setContextProperty( "Ros2", &mockRos2_ );
  mockRos2_.setEngine( engine );

  // Register Ros2 module types (available under Ros2 namespace if imported)
  qmlRegisterType<qml6_ros2_plugin::MessageItemModel>( "Ros2", 1, 0, "MessageItemModel" );
  qmlRegisterType<MockSubscription>( "Ros2", 1, 0, "Subscription" );
  qmlRegisterType<MockPublisher>( "Ros2", 1, 0, "Publisher" );
  qmlRegisterType<MockServiceClient>( "Ros2", 1, 0, "ServiceClient" );
  qmlRegisterType<MockActionClient>( "Ros2", 1, 0, "ActionClient" );
  qmlRegisterUncreatableMetaObject( qml6_ros2_plugin::action_goal_status::staticMetaObject, "Ros2",
                                    1, 0, "ActionGoalStatus", "Error" );
  qmlRegisterUncreatableMetaObject( action_result_code::staticMetaObject, "Ros2", 1, 0,
                                    "ActionResultCode", "Error" );
}

QUICK_TEST_MAIN_WITH_SETUP( RqmlDefaultPluginsTest, Setup )

#include "test_plugins.moc"
