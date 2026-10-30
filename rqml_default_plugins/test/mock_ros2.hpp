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

// shortcut: mirrors qml6_ros2_plugin's QoS policy enums for CI against releases without them, register the
// plugin's own qos_*_policy namespaces instead once a release with them is in the ROS testing repo.
namespace qos_reliability_policy
{
Q_NAMESPACE
enum ReliabilityPolicy {
  BestEffort = RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT,
  Reliable = RMW_QOS_POLICY_RELIABILITY_RELIABLE,
  SystemDefault = RMW_QOS_POLICY_RELIABILITY_SYSTEM_DEFAULT,
  BestAvailable = RMW_QOS_POLICY_RELIABILITY_BEST_AVAILABLE,
  Unknown = RMW_QOS_POLICY_RELIABILITY_UNKNOWN
};
Q_ENUM_NS( ReliabilityPolicy )
} // namespace qos_reliability_policy

namespace qos_durability_policy
{
Q_NAMESPACE
enum DurabilityPolicy {
  Volatile = RMW_QOS_POLICY_DURABILITY_VOLATILE,
  TransientLocal = RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL,
  SystemDefault = RMW_QOS_POLICY_DURABILITY_SYSTEM_DEFAULT,
  BestAvailable = RMW_QOS_POLICY_DURABILITY_BEST_AVAILABLE,
  Unknown = RMW_QOS_POLICY_DURABILITY_UNKNOWN
};
Q_ENUM_NS( DurabilityPolicy )
} // namespace qos_durability_policy

namespace qos_history_policy
{
Q_NAMESPACE
enum HistoryPolicy {
  KeepLast = RMW_QOS_POLICY_HISTORY_KEEP_LAST,
  KeepAll = RMW_QOS_POLICY_HISTORY_KEEP_ALL,
  SystemDefault = RMW_QOS_POLICY_HISTORY_SYSTEM_DEFAULT,
  Unknown = RMW_QOS_POLICY_HISTORY_UNKNOWN
};
Q_ENUM_NS( HistoryPolicy )
} // namespace qos_history_policy

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
 *
 * Nodes are added with `registerNode(fullName, info)`; `info` holds the interface lists of the
 * node's getAllNodeInfo() entry ({ publishers, subscriptions, serviceServers, ... }), {} if omitted.
 * Without serviceServers in `info`, the node serves the services registered with registerService() whose name
 * starts with its full name and '/'.
 * registerNode() emits graphChanged(). Publisher and subscriber entries may carry the mock-only
 * `qos`, one QoS per endpoint of the node on that topic, which getPublishersInfoByTopic() and
 * getSubscriptionsInfoByTopic() report.
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
  //! RQml's own node, as named by Ros2.init("rqml") in main.qml.
  Q_INVOKABLE QString getName() const { return QStringLiteral( "rqml" ); }
  Q_INVOKABLE QString getNamespace() const { return QStringLiteral( "/" ); }
  Q_INVOKABLE QJSValue getNodeNamesAndNamespaces() const;
  Q_INVOKABLE QJSValue getAllNodeInfo() const;
  Q_INVOKABLE QJSValue getPublishersInfoByTopic( const QString &topic ) const;
  Q_INVOKABLE QJSValue getSubscriptionsInfoByTopic( const QString &topic ) const;

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
  Q_INVOKABLE void registerNode( const QString &full_name, const QJSValue &info = QJSValue() );

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

signals:
  void graphChanged();

private:
  QStringList jsStringList( const QJSValue &map, const QString &key ) const;
  //! The endpoints on @p topic of the registered nodes' @p role lists, e.g. "publishers".
  QJSValue endpointsInfoByTopic( const QString &topic, const char *role ) const;

  QQmlEngine *engine_ = nullptr;
  qml6_ros2_plugin::IO io_;
  QJSValue infoFn_, debugFn_, warnFn_, errorFn_, fatalFn_;
  QJSValue mockTopics_, mockServices_, mockActions_, mockTypeMap_;
  QJSValue serviceHandlers_, actionHandler_;
  QJSValue actionHandlers_;
  QJSValue publishedMessages_, lastActionGoalMessage_;
  QJSValue mockNodes_, mockNodeInfos_;
  bool lastActionCancelled_ = false;
  QList<QObject *> subscriptions_;

public:
  QList<QObject *> subscriptions() const { return subscriptions_; }
};
