#include <QJSEngine>
#include <QMap>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTimer>
#include <QtQml>
#include <QtQuickTest/quicktest.h>

#include <qml6_ros2_plugin/goal_status.hpp>
#include <qml6_ros2_plugin/io.hpp>
#include <qml6_ros2_plugin/message_item_model.hpp>
#include <qml6_ros2_plugin/qos.hpp>
#include <qml6_ros2_plugin/ros2.hpp>

// ActionResultCode is used in JointTrajectoryControllerInterface but not provided
// by qml6_ros2_plugin.  We define a matching namespace here.
namespace action_result_code
{
Q_NAMESPACE
enum ResultCode { UNKNOWN = 0, SUCCEEDED = 1, CANCELED = 2, ABORTED = 3 };
Q_ENUM_NS( ResultCode )
} // namespace action_result_code

// Forward declaration
class MockRos2;
static MockRos2 *s_mockRos2 = nullptr;

// =============================================================================
// MockServiceClient
// =============================================================================
class MockServiceClient : public QObject
{
  Q_OBJECT
  Q_PROPERTY( bool ready READ ready CONSTANT )
  Q_PROPERTY( QString name READ name CONSTANT )
  Q_PROPERTY( int pendingRequests READ pendingRequests CONSTANT )
  Q_PROPERTY( int connectionTimeout READ connectionTimeout WRITE setConnectionTimeout NOTIFY
                  connectionTimeoutChanged )
public:
  MockServiceClient( const QString &name, QJSEngine *engine, QJSValue responseCallback,
                     QObject *parent )
      : QObject( parent ), name_( name ), engine_( engine ),
        responseCallback_( std::move( responseCallback ) )
  {
  }

  bool ready() const { return true; }
  QString name() const { return name_; }
  int pendingRequests() const { return 0; }
  int connectionTimeout() const { return timeout_; }
  void setConnectionTimeout( int t )
  {
    timeout_ = t;
    emit connectionTimeoutChanged();
  }

  Q_INVOKABLE void sendRequestAsync( const QVariantMap &req, const QJSValue &callback )
  {
    auto *timer = new QTimer( this );
    timer->setSingleShot( true );
    timer->setInterval( 0 );
    QJSValue cb = callback;
    QJSValue respCb = responseCallback_;
    QJSEngine *eng = engine_;
    connect( timer, &QTimer::timeout, this, [timer, cb, respCb, req, eng]() mutable {
      timer->deleteLater();
      QJSValue response;
      if ( respCb.isCallable() ) {
        QJSValueList args;
        args << eng->toScriptValue( req );
        response = respCb.call( args );
      } else {
        response = QJSValue::NullValue;
      }
      if ( cb.isCallable() ) {
        QJSValueList args;
        args << response;
        cb.call( args );
      }
    } );
    timer->start();
  }

signals:
  void connectionTimeoutChanged();

private:
  QString name_;
  QJSEngine *engine_;
  QJSValue responseCallback_;
  int timeout_ = 5000;
};

// =============================================================================
// MockPublisher — records published messages via Ros2.publishedMessages
// =============================================================================
class MockPublisher : public QObject
{
  Q_OBJECT
  Q_PROPERTY( QString topic READ topic CONSTANT )
  Q_PROPERTY( QString type READ type CONSTANT )
  Q_PROPERTY( bool isAdvertised READ isAdvertised CONSTANT )
public:
  MockPublisher( const QString &topic, const QString &type, QJSEngine *engine, QObject *parent )
      : QObject( parent ), topic_( topic ), type_( type ), engine_( engine )
  {
  }

  QString topic() const { return topic_; }
  QString type() const { return type_; }
  bool isAdvertised() const { return true; }

  // Implemented after MockRos2 is defined
  Q_INVOKABLE bool publish( const QVariantMap &msg );

private:
  QString topic_;
  QString type_;
  QJSEngine *engine_;
};

// =============================================================================
// MockActionClient
// =============================================================================
class MockActionClient : public QObject
{
  Q_OBJECT
  Q_PROPERTY( bool ready READ ready CONSTANT )
public:
  MockActionClient( QJSEngine *engine, QJSValue flowCallback, QObject *parent )
      : QObject( parent ), engine_( engine ), flowCallback_( std::move( flowCallback ) )
  {
  }

  bool ready() const { return true; }

  Q_INVOKABLE void sendGoalAsync( const QVariantMap &goal, const QJSValue &callbacks )
  {
    auto *timer = new QTimer( this );
    timer->setSingleShot( true );
    timer->setInterval( 0 );
    QJSValue flow = flowCallback_;
    QJSValue cb = callbacks;
    QJSEngine *eng = engine_;
    connect( timer, &QTimer::timeout, this, [timer, flow, cb, goal, eng]() mutable {
      timer->deleteLater();
      if ( flow.isCallable() ) {
        QJSValueList args;
        args << eng->toScriptValue( goal ) << cb;
        flow.call( args );
      } else if ( flow.isObject() && !flow.isNull() ) {
        // flow is a data object: { goalHandle, feedbacks, result }
        QJSValue onGoalResponse = cb.property( "onGoalResponse" );
        QJSValue onFeedback = cb.property( "onFeedback" );
        QJSValue onResult = cb.property( "onResult" );
        QJSValue goalHandle = flow.property( "goalHandle" );

        if ( onGoalResponse.isCallable() ) {
          QJSValueList a;
          a << goalHandle;
          onGoalResponse.call( a );
        }
        QJSValue feedbacks = flow.property( "feedbacks" );
        if ( feedbacks.isArray() && onFeedback.isCallable() ) {
          int len = feedbacks.property( "length" ).toInt();
          for ( int i = 0; i < len; ++i ) {
            QJSValueList a;
            a << goalHandle << feedbacks.property( i );
            onFeedback.call( a );
          }
        }
        QJSValue result = flow.property( "result" );
        if ( !result.isUndefined() && !result.isNull() && onResult.isCallable() ) {
          // Defer result slightly to match real async behavior
          auto *t2 = new QTimer( timer->parent() );
          t2->setSingleShot( true );
          t2->setInterval( 0 );
          QObject::connect( t2, &QTimer::timeout, [t2, onResult, result]() mutable {
            t2->deleteLater();
            QJSValueList a;
            a << result;
            onResult.call( a );
          } );
          t2->start();
        }
      }
    } );
    timer->start();
  }

  Q_INVOKABLE void cancelAllGoals();

private:
  QJSEngine *engine_;
  QJSValue flowCallback_;
};

// =============================================================================
// MockRos2 — the C++ singleton registered as "Ros2" in QML
// =============================================================================
class MockRos2 : public QObject
{
  Q_OBJECT
  Q_PROPERTY( qml6_ros2_plugin::IO io READ io CONSTANT )
  Q_PROPERTY( QJSValue debug READ debug CONSTANT )
  Q_PROPERTY( QJSValue warn READ warn CONSTANT )
  Q_PROPERTY( QJSValue error READ error CONSTANT )

  // Mock state — use READ/WRITE (not MEMBER) to avoid QJSValue operator!= issues
  Q_PROPERTY( QJSValue _mockTopics READ mockTopics WRITE setMockTopics )
  Q_PROPERTY( QJSValue _mockServices READ mockServices WRITE setMockServices )
  Q_PROPERTY( QJSValue _mockActions READ mockActions WRITE setMockActions )
  Q_PROPERTY( QJSValue _mockTypeMap READ mockTypeMap WRITE setMockTypeMap )
  Q_PROPERTY( QJSValue _mockServiceResponses READ mockServiceResponses WRITE setMockServiceResponses )
  Q_PROPERTY( QJSValue _mockActionFlow READ mockActionFlow WRITE setMockActionFlow )
  Q_PROPERTY( QJSValue publishedMessages READ publishedMessages WRITE setPublishedMessages )
  Q_PROPERTY( QJSValue nextSetParameterResult READ nextSetParameterResult WRITE setNextSetParameterResult )
  Q_PROPERTY( QJSValue mockParameters READ mockParameters WRITE setMockParameters )
  Q_PROPERTY( QJSValue _lastActionGoalMessage READ lastActionGoalMessage WRITE setLastActionGoalMessage )
  Q_PROPERTY( bool _lastActionCancelled READ lastActionCancelled WRITE setLastActionCancelled )

public:
  explicit MockRos2( QObject *parent = nullptr ) : QObject( parent ) { }

  void setEngine( QQmlEngine *engine )
  {
    engine_ = engine;
    // Initialize all JS state so nothing is undefined when components load
    reset();
    initParameterEditorFixtures();
  }

  QQmlEngine *engine() const { return engine_; }

  // --- Property accessors ---
  QJSValue mockTopics() const { return mockTopics_; }
  void setMockTopics( const QJSValue &v ) { mockTopics_ = v; }
  QJSValue mockServices() const { return mockServices_; }
  void setMockServices( const QJSValue &v ) { mockServices_ = v; }
  QJSValue mockActions() const { return mockActions_; }
  void setMockActions( const QJSValue &v ) { mockActions_ = v; }
  QJSValue mockTypeMap() const { return mockTypeMap_; }
  void setMockTypeMap( const QJSValue &v ) { mockTypeMap_ = v; }
  QJSValue mockServiceResponses() const { return mockServiceResponses_; }
  void setMockServiceResponses( const QJSValue &v ) { mockServiceResponses_ = v; }
  QJSValue mockActionFlow() const { return mockActionFlow_; }
  void setMockActionFlow( const QJSValue &v ) { mockActionFlow_ = v; }
  QJSValue publishedMessages() const { return publishedMessages_; }
  void setPublishedMessages( const QJSValue &v ) { publishedMessages_ = v; }
  QJSValue nextSetParameterResult() const { return nextSetParameterResult_; }
  void setNextSetParameterResult( const QJSValue &v ) { nextSetParameterResult_ = v; }
  QJSValue mockParameters() const { return mockParameters_; }
  void setMockParameters( const QJSValue &v ) { mockParameters_ = v; }
  QJSValue lastActionGoalMessage() const { return lastActionGoalMessage_; }
  void setLastActionGoalMessage( const QJSValue &v ) { lastActionGoalMessage_ = v; }
  bool lastActionCancelled() const { return lastActionCancelled_; }
  void setLastActionCancelled( bool v ) { lastActionCancelled_ = v; }

  // --- Delegate to real Ros2Qml for non-network operations ---

  qml6_ros2_plugin::IO io() const { return io_; }

  Q_INVOKABLE QVariant createEmptyMessage( const QString &datatype ) const
  {
    return qml6_ros2_plugin::Ros2Qml::getInstance().createEmptyMessage( datatype );
  }

  Q_INVOKABLE QVariant createEmptyServiceRequest( const QString &datatype ) const
  {
    return qml6_ros2_plugin::Ros2Qml::getInstance().createEmptyServiceRequest( datatype );
  }

  Q_INVOKABLE QVariant createEmptyActionGoal( const QString &datatype ) const
  {
    return qml6_ros2_plugin::Ros2Qml::getInstance().createEmptyActionGoal( datatype );
  }

  Q_INVOKABLE bool isValidTopic( const QString &topic ) const
  {
    return !topic.isEmpty() && topic.startsWith( "/" ) && topic.size() > 1;
  }

  Q_INVOKABLE qml6_ros2_plugin::QoSWrapper QoS() { return qml6_ros2_plugin::QoSWrapper(); }

  Q_INVOKABLE qml6_ros2_plugin::Time now() const { return qml6_ros2_plugin::Time(); }

  // --- Logging ---

  QJSValue debug()
  {
    if ( !debugFn_.isCallable() && engine_ )
      debugFn_ = engine_->evaluate( "(function() { console.log('MOCK Ros2 DEBUG:', "
                                    "Array.prototype.join.call(arguments, ' ')); })" );
    return debugFn_;
  }
  QJSValue warn()
  {
    if ( !warnFn_.isCallable() && engine_ )
      warnFn_ = engine_->evaluate( "(function() { console.warn('MOCK Ros2 WARN:', "
                                   "Array.prototype.join.call(arguments, ' ')); })" );
    return warnFn_;
  }
  QJSValue error()
  {
    if ( !errorFn_.isCallable() && engine_ )
      errorFn_ = engine_->evaluate( "(function() { console.error('MOCK Ros2 ERROR:', "
                                    "Array.prototype.join.call(arguments, ' ')); })" );
    return errorFn_;
  }

  // --- Query functions ---

  Q_INVOKABLE QStringList queryTopics( const QString &datatype = QString() ) const
  {
    return jsStringList( mockTopics_, datatype );
  }

  Q_INVOKABLE QStringList queryTopicTypes( const QString &name ) const
  {
    return jsStringList( mockTypeMap_, name );
  }

  Q_INVOKABLE QStringList getTopicTypes( const QString &name ) const
  {
    return queryTopicTypes( name );
  }

  Q_INVOKABLE QStringList queryServices( const QString &datatype = QString() ) const
  {
    QStringList result = jsStringList( mockServices_, datatype );
    if ( !result.isEmpty() )
      return result;
    // ParameterEditor backward-compat: hardcoded parameter service endpoints
    if ( datatype == "rcl_interfaces/srv/ListParameters" )
      return { "/mock_node/list_parameters" };
    if ( datatype == "rcl_interfaces/srv/GetParameters" )
      return { "/mock_node/get_parameters" };
    if ( datatype == "rcl_interfaces/srv/SetParameters" )
      return { "/mock_node/set_parameters" };
    if ( datatype == "rcl_interfaces/srv/DescribeParameters" )
      return { "/mock_node/describe_parameters" };
    return result;
  }

  Q_INVOKABLE QStringList getServiceTypes( const QString &name ) const
  {
    return jsStringList( mockTypeMap_, name );
  }

  Q_INVOKABLE QStringList queryActions( const QString &datatype = QString() ) const
  {
    if ( mockActions_.isArray() ) {
      QStringList result;
      int len = mockActions_.property( "length" ).toInt();
      for ( int i = 0; i < len; ++i ) result.append( mockActions_.property( i ).toString() );
      return result;
    }
    return jsStringList( mockActions_, datatype );
  }

  Q_INVOKABLE QStringList getActionTypes( const QString &name ) const
  {
    return jsStringList( mockTypeMap_, name );
  }

  // --- Factory functions ---

  Q_INVOKABLE QObject *createPublisher( const QString &topic, const QString &type,
                                        quint32 /*queue_size*/ = 10 )
  {
    return new MockPublisher( topic, type, engine_, this );
  }

  Q_INVOKABLE QObject *createServiceClient( const QString &name, const QString & /*type*/ )
  {
    QJSValue respCb;
    if ( engine_ && mockServiceResponses_.isObject() ) {
      QJSValue val = mockServiceResponses_.property( name );
      if ( val.isCallable() ) {
        respCb = val;
      } else if ( val.isObject() && !val.isUndefined() && !val.isNull() ) {
        QJSValue wrapper =
            engine_->evaluate( "(function(resp) { return function() { return resp; }; })" );
        QJSValueList args;
        args << val;
        respCb = wrapper.call( args );
      }
    }
    // ParameterEditor backward-compat: hardcoded parameter service handling
    if ( !respCb.isCallable() && engine_ && isParameterServiceEndpoint( name ) ) {
      respCb = buildParameterServiceCallback( name );
    }
    return new MockServiceClient( name, engine_, respCb, this );
  }

  Q_INVOKABLE QObject *createActionClient( const QString & /*name*/, const QString & /*type*/ )
  {
    return new MockActionClient( engine_, mockActionFlow_, this );
  }

  // --- Mock state management ---

  Q_INVOKABLE void reset()
  {
    if ( !engine_ )
      return;
    mockTopics_ = engine_->newObject();
    mockServices_ = engine_->newObject();
    mockActions_ = engine_->newObject();
    mockTypeMap_ = engine_->newObject();
    mockServiceResponses_ = engine_->newObject();
    mockActionFlow_ = QJSValue::NullValue;
    publishedMessages_ = engine_->newArray();
    nextSetParameterResult_ = QJSValue::NullValue;
    lastActionGoalMessage_ = QJSValue::NullValue;
    lastActionCancelled_ = false;
  }

  // --- Subscription registry ---

  Q_INVOKABLE void _registerSubscription( QObject *sub ) { subscriptions_.append( sub ); }
  Q_INVOKABLE void _unregisterSubscription( QObject *sub ) { subscriptions_.removeAll( sub ); }

  Q_INVOKABLE QObject *findSubscription( const QString &topic ) const
  {
    for ( QObject *sub : subscriptions_ ) {
      if ( sub->property( "topic" ).toString() == topic )
        return sub;
    }
    return nullptr;
  }

  // --- ParameterEditor helpers ---

  Q_INVOKABLE void addMockParameter( const QJSValue &paramObj )
  {
    if ( mockParameters_.isArray() ) {
      int len = mockParameters_.property( "length" ).toInt();
      mockParameters_.setProperty( len, paramObj );
    }
  }

  Q_INVOKABLE QJSValue withAt( const QJSValue &arr )
  {
    if ( !engine_ || !arr.isArray() )
      return arr;
    if ( !addAtFn_.isCallable() ) {
      addAtFn_ = engine_->evaluate(
          "(function(a) { a.at = function(i) { return this[i]; }; return a; })" );
    }
    QJSValueList args;
    args << arr;
    return addAtFn_.call( args );
  }

  Q_INVOKABLE QJSValue wrapCppMessage( const QJSValue &obj )
  {
    if ( !engine_ )
      return obj;
    if ( !wrapFn_.isCallable() ) {
      wrapFn_ = engine_->evaluate( R"((function wrap(obj) {
        if (obj === null || obj === undefined) return obj;
        if (Array.isArray(obj)) {
          var w = [];
          for (var i = 0; i < obj.length; i++) w.push(wrap(obj[i]));
          w.at = function(idx) { return this[idx]; };
          return w;
        }
        if (typeof obj === "object") {
          var r = {};
          var keys = Object.keys(obj);
          for (var k = 0; k < keys.length; k++) r[keys[k]] = wrap(obj[keys[k]]);
          return r;
        }
        return obj;
      }))" );
    }
    QJSValueList args;
    args << obj;
    return wrapFn_.call( args );
  }

  // Called by MockPublisher::publish
  void recordPublishedMessage( const QJSValue &entry )
  {
    if ( publishedMessages_.isArray() ) {
      int len = publishedMessages_.property( "length" ).toInt();
      publishedMessages_.setProperty( len, entry );
    }
  }

  // --- ParameterEditor backward-compat: hardcoded parameter service ---

  void initParameterEditorFixtures()
  {
    if ( !engine_ )
      return;
    // Build the mockParameters array matching the old QML mock
    mockParameters_ = engine_->evaluate( R"([
      { name: "mock_group.mock_param_1", type: 4, string_value: "hello mock",
        description: "Mock string param", read_only: false,
        floating_point_range: [], integer_range: [] },
      { name: "mock_group.mock_param_2", type: 2, integer_value: 42,
        description: "Mock int param", read_only: true,
        floating_point_range: [],
        integer_range: [{from_value: 0, to_value: 100, step: 1}] },
      { name: "mock_group.mock_param_3", type: 2, integer_value: 10,
        description: "Mock int min", read_only: false,
        floating_point_range: [],
        integer_range: [{from_value: 5, step: 1}] },
      { name: "mock_group.mock_param_4", type: 2, integer_value: 50,
        description: "Mock int max", read_only: false,
        floating_point_range: [],
        integer_range: [{to_value: 100, step: 1}] },
      { name: "mock_group.mock_param_5", type: 3, double_value: 3.14,
        description: "Mock double param", read_only: false,
        floating_point_range: [{from_value: 0.0, to_value: 10.0, step: 0.1}],
        integer_range: [] }
    ])" );
  }

  bool isParameterServiceEndpoint( const QString &name ) const
  {
    return name.endsWith( "/list_parameters" ) || name.endsWith( "/get_parameters" ) ||
           name.endsWith( "/set_parameters" ) || name.endsWith( "/describe_parameters" );
  }

  QJSValue buildParameterServiceCallback( const QString &name )
  {
    // QML singletons aren't accessible from QJSEngine::evaluate(), so we
    // pass a reference to `this` (the MockRos2 object) via the engine's
    // global object, then use it inside the callback closures.
    engine_->globalObject().setProperty( "_mockRos2", engine_->newQObject( this ) );

    if ( name.endsWith( "/list_parameters" ) ) {
      return engine_->evaluate( R"((function(request) {
        var mock = _mockRos2;
        var names = [];
        var params = mock.mockParameters;
        for (var i = 0; i < params.length; i++) names.push(params[i].name);
        names.at = function(i) { return this[i]; };
        return { result: { names: names } };
      }))" );
    }
    if ( name.endsWith( "/get_parameters" ) ) {
      return engine_->evaluate( R"((function(request) {
        var mock = _mockRos2;
        var values = [];
        var params = mock.mockParameters;
        for (var i = 0; i < params.length; i++) {
          var p = params[i], pv = { type: p.type };
          if (p.type === 4) pv.string_value = p.string_value;
          if (p.type === 2) pv.integer_value = p.integer_value;
          if (p.type === 3) pv.double_value = p.double_value;
          values.push(pv);
        }
        values.at = function(i) { return this[i]; };
        return { values: values };
      }))" );
    }
    if ( name.endsWith( "/describe_parameters" ) ) {
      return engine_->evaluate( R"((function(request) {
        var mock = _mockRos2;
        var descs = [];
        var params = mock.mockParameters;
        for (var i = 0; i < params.length; i++) {
          var p = params[i];
          var fpr = p.floating_point_range.slice();
          fpr.at = function(i) { return this[i]; };
          var ir = p.integer_range.slice();
          ir.at = function(i) { return this[i]; };
          descs.push({
            name: p.name, description: p.description, read_only: p.read_only,
            floating_point_range: fpr, integer_range: ir
          });
        }
        descs.at = function(i) { return this[i]; };
        return { descriptors: descs };
      }))" );
    }
    if ( name.endsWith( "/set_parameters" ) ) {
      return engine_->evaluate( R"((function(request) {
        var mock = _mockRos2;
        var result = { successful: true };
        var nsp = mock.nextSetParameterResult;
        if (nsp !== null && nsp !== undefined) {
          result = nsp;
          mock.nextSetParameterResult = null;
        }
        var results = [result];
        results.at = function(i) { return this[i]; };
        return { results: results };
      }))" );
    }
    return QJSValue::NullValue;
  }

private:
  QStringList jsStringList( const QJSValue &map, const QString &key ) const
  {
    QStringList result;
    if ( !map.isObject() )
      return result;

    // Try the exact key first, then fall back to the "" (default) key
    QJSValue arr = map.property( key );
    if ( !arr.isArray() && !key.isEmpty() )
      arr = map.property( "" );
    if ( !arr.isArray() )
      return result;

    int len = arr.property( "length" ).toInt();
    result.reserve( len );
    for ( int i = 0; i < len; ++i ) result.append( arr.property( i ).toString() );
    return result;
  }

  QQmlEngine *engine_ = nullptr;
  qml6_ros2_plugin::IO io_;
  QJSValue debugFn_, warnFn_, errorFn_;
  QJSValue addAtFn_, wrapFn_;

  QJSValue mockTopics_;
  QJSValue mockServices_;
  QJSValue mockActions_;
  QJSValue mockTypeMap_;
  QJSValue mockServiceResponses_;
  QJSValue mockActionFlow_;
  QJSValue publishedMessages_;
  QJSValue nextSetParameterResult_;
  QJSValue mockParameters_;
  QJSValue lastActionGoalMessage_;
  bool lastActionCancelled_ = false;

  QList<QObject *> subscriptions_;
};

// --- Deferred implementations that need MockRos2 to be complete ---

bool MockPublisher::publish( const QVariantMap &msg )
{
  if ( !engine_ )
    return false;
  QJSValue entry = engine_->newObject();
  entry.setProperty( "topic", topic_ );
  entry.setProperty( "type", type_ );
  entry.setProperty( "message", engine_->toScriptValue( msg ) );
  s_mockRos2->recordPublishedMessage( entry );
  return true;
}

void MockActionClient::cancelAllGoals()
{
  if ( s_mockRos2 )
    s_mockRos2->setLastActionCancelled( true );
}

// =============================================================================
// MockRQml — in-memory file system mock for ParameterEditor save/load tests
// =============================================================================
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

// =============================================================================
// Setup
// =============================================================================
class Setup : public QObject
{
  Q_OBJECT
public:
  Setup() { s_mockRos2 = &mockRos2_; }

public slots:
  void qmlEngineAvailable( QQmlEngine *engine )
  {
    engine->rootContext()->setContextProperty( "RQml", &mockRqml_ );

    mockRos2_.setEngine( engine );
    qmlRegisterSingletonInstance( "Ros2", 1, 0, "Ros2", &mockRos2_ );

    qmlRegisterType<qml6_ros2_plugin::MessageItemModel>( "Ros2", 1, 0, "MessageItemModel" );
    qmlRegisterUncreatableMetaObject( qml6_ros2_plugin::action_goal_status::staticMetaObject,
                                      "Ros2", 1, 0, "ActionGoalStatus",
                                      "Error: Can not create enum object." );
    qmlRegisterUncreatableMetaObject( action_result_code::staticMetaObject, "Ros2", 1, 0,
                                      "ActionResultCode", "Error: Can not create enum object." );
  }

private:
  MockRQml mockRqml_;
  MockRos2 mockRos2_;
};

QUICK_TEST_MAIN_WITH_SETUP( DefaultPluginsTest, Setup )
#include "test_plugins.moc"
