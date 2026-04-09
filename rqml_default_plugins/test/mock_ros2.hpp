#pragma once
#include <QJSEngine>
#include <QObject>
#include <QQmlEngine>
#include <QStringList>
#include <QVariant>
#include <qml6_ros2_plugin/babel_fish_dispenser.hpp>
#include <qml6_ros2_plugin/conversion/message_conversions.hpp>
#include <qml6_ros2_plugin/io.hpp>
#include <qml6_ros2_plugin/qos.hpp>
#include <qml6_ros2_plugin/ros2.hpp>
#include <qml6_ros2_plugin/time.hpp>

#include <vector>

namespace action_result_code
{
Q_NAMESPACE
enum ResultCode { SUCCEEDED = 4, ABORTED = 5, CANCELED = 6 };
Q_ENUM_NS( ResultCode )
} // namespace action_result_code

class MockServiceClient;
class MockPublisher;
class MockActionClient;

/**
 * MockRos2 - A test double for the production Ros2 singleton.
 *
 * Tests interact with it via QML properties:
 *   - `_mockTopics`      : JS object mapping type → [topics]
 *   - `_mockServices`    : JS object mapping type → [service names]
 *   - `_mockActions`     : JS object/array of action names
 *   - `_mockTypeMap`     : JS object mapping name → [types]
 *   - `_serviceHandlers` : JS object mapping service name → handler function(request) → response
 *   - `_actionHandler`   : fallback JS function(goal, callbacks) driving action flow
 *   - `_actionHandlers`  : JS object mapping action name to handler(goal, callbacks)
 *   - `publishedMessages`: JS array of {topic, type, message} entries
 *
 * Service handlers are plain JS functions: `function(request) { return response; }`
 * The handler receives the request map and must return the response (built via
 * `Ros2.createEmptyMessage(type)` + field population). MockServiceClient calls
 * the handler asynchronously (1 event loop tick) and passes the result to the
 * caller's callback.
 */
class MockRos2 : public QObject
{
  Q_OBJECT
  Q_PROPERTY( qml6_ros2_plugin::IO io READ io CONSTANT )
  Q_PROPERTY( QJSValue info READ info CONSTANT )
  Q_PROPERTY( QJSValue debug READ debug CONSTANT )
  Q_PROPERTY( QJSValue warn READ warn CONSTANT )
  Q_PROPERTY( QJSValue error READ error CONSTANT )
  Q_PROPERTY( QJSValue fatal READ fatal CONSTANT )
  Q_PROPERTY( QJSValue _mockTopics READ mockTopics WRITE setMockTopics )
  Q_PROPERTY( QJSValue _mockServices READ mockServices WRITE setMockServices )
  Q_PROPERTY( QJSValue _mockActions READ mockActions WRITE setMockActions )
  Q_PROPERTY( QJSValue _mockTypeMap READ mockTypeMap WRITE setMockTypeMap )
  Q_PROPERTY( QJSValue _serviceHandlers READ serviceHandlers WRITE setServiceHandlers )
  Q_PROPERTY( QJSValue _actionHandler READ actionHandler WRITE setActionHandler )
  Q_PROPERTY( QJSValue _actionHandlers READ actionHandlers WRITE setActionHandlers )
  Q_PROPERTY( QJSValue publishedMessages READ publishedMessages WRITE setPublishedMessages )
  Q_PROPERTY( QJSValue _lastActionGoalMessage READ lastActionGoalMessage WRITE setLastActionGoalMessage )
  Q_PROPERTY( bool _lastActionCancelled READ lastActionCancelled WRITE setLastActionCancelled )

public:
  explicit MockRos2( QObject *parent = nullptr ) : QObject( parent ) { }
  void setEngine( QQmlEngine *engine );
  QQmlEngine *engine() const { return engine_; }

  QJSValue mockTopics() const { return mockTopics_; }
  void setMockTopics( const QJSValue &v ) { mockTopics_ = v; }
  QJSValue mockServices() const { return mockServices_; }
  void setMockServices( const QJSValue &v ) { mockServices_ = v; }
  QJSValue mockActions() const { return mockActions_; }
  void setMockActions( const QJSValue &v ) { mockActions_ = v; }
  QJSValue mockTypeMap() const { return mockTypeMap_; }
  void setMockTypeMap( const QJSValue &v ) { mockTypeMap_ = v; }
  QJSValue serviceHandlers() const { return serviceHandlers_; }
  void setServiceHandlers( const QJSValue &v ) { serviceHandlers_ = v; }
  QJSValue actionHandler() const { return actionHandler_; }
  void setActionHandler( const QJSValue &v ) { actionHandler_ = v; }
  QJSValue actionHandlers() const { return actionHandlers_; }
  void setActionHandlers( const QJSValue &v ) { actionHandlers_ = v; }
  QJSValue publishedMessages() const { return publishedMessages_; }
  void setPublishedMessages( const QJSValue &v ) { publishedMessages_ = v; }
  QJSValue lastActionGoalMessage() const { return lastActionGoalMessage_; }
  void setLastActionGoalMessage( const QJSValue &v ) { lastActionGoalMessage_ = v; }
  bool lastActionCancelled() const { return lastActionCancelled_; }
  void setLastActionCancelled( bool v ) { lastActionCancelled_ = v; }

  qml6_ros2_plugin::IO io() const { return io_; }
  Q_INVOKABLE QVariant createEmptyMessage( const QString &datatype ) const;
  Q_INVOKABLE QVariant createEmptyServiceRequest( const QString &datatype ) const;
  Q_INVOKABLE QVariant createEmptyServiceResponse( const QString &datatype ) const;
  Q_INVOKABLE QVariant createEmptyActionGoal( const QString &datatype ) const;
  Q_INVOKABLE QVariant createEmptyActionFeedback( const QString &datatype ) const;
  Q_INVOKABLE QVariant createEmptyActionResult( const QString &datatype ) const;
  Q_INVOKABLE QObject *createGoalHandle( const QString &goal_id );
  Q_INVOKABLE bool isValidTopic( const QString &topic ) const;
  Q_INVOKABLE qml6_ros2_plugin::QoSWrapper QoS();
  Q_INVOKABLE qml6_ros2_plugin::Time now() const;

  QJSValue info();
  QJSValue debug();
  QJSValue warn();
  QJSValue error();
  QJSValue fatal();

  Q_INVOKABLE QStringList queryTopics( const QString &datatype = QString() ) const;
  Q_INVOKABLE QStringList queryTopicTypes( const QString &name ) const;
  Q_INVOKABLE QStringList getTopicTypes( const QString &name ) const;
  Q_INVOKABLE QStringList queryServices( const QString &datatype = QString() ) const;
  Q_INVOKABLE QStringList getServiceTypes( const QString &name ) const;
  Q_INVOKABLE QStringList queryActions( const QString &datatype = QString() ) const;
  Q_INVOKABLE QStringList getActionTypes( const QString &name ) const;

  Q_INVOKABLE QObject *createPublisher( const QString &topic, const QString &type,
                                        quint32 queue_size = 10 );
  Q_INVOKABLE QObject *createServiceClient( const QString &name, const QString &type );
  Q_INVOKABLE QObject *createActionClient( const QString &name, const QString &type );
  Q_INVOKABLE QObject *createSubscription( const QString &topic, const QString &type,
                                           quint32 queue_size = 10 );
  Q_INVOKABLE void registerTopic( const QString &topic, const QString &type );
  Q_INVOKABLE void registerAction( const QString &name, const QString &type,
                                   const QJSValue &handler = QJSValue() );
  Q_INVOKABLE void registerService( const QString &name, const QString &type,
                                    const QJSValue &handler = QJSValue() );

  Q_INVOKABLE void reset();
  // Test-only API. Prefixed with _ to mark as internal; intentionally invoked
  // from tst_*.qml to inject QML Subscription stubs into the mock registry.
  Q_INVOKABLE void _registerSubscription( QObject *sub );
  Q_INVOKABLE void _unregisterSubscription( QObject *sub );
  Q_INVOKABLE QObject *findSubscription( const QString &topic ) const;
  Q_INVOKABLE QJSValue wrap( const QString &type, const QVariant &value );
  Q_INVOKABLE void setContextProperty( const QString &name, const QJSValue &value );

  Q_INVOKABLE QObject *getLogger( const QString &name = QString() );

  /// Look up the registered handler for a service name. Returns NullValue if none.
  QJSValue getServiceHandler( const QString &name );
  /// Look up the registered handler for an action name. Returns NullValue if none.
  QJSValue getActionHandler( const QString &name );

  void recordPublishedMessage( const QJSValue &entry );

private:
  QStringList jsStringList( const QJSValue &map, const QString &key ) const;

  QQmlEngine *engine_ = nullptr;
  qml6_ros2_plugin::IO io_;
  QJSValue infoFn_, debugFn_, warnFn_, errorFn_, fatalFn_;
  QJSValue mockTopics_, mockServices_, mockActions_, mockTypeMap_;
  QJSValue serviceHandlers_, actionHandler_;
  QJSValue actionHandlers_;
  QJSValue publishedMessages_, lastActionGoalMessage_;
  bool lastActionCancelled_ = false;
  QList<QObject *> subscriptions_;

public:
  QList<QObject *> subscriptions() const { return subscriptions_; }
};
