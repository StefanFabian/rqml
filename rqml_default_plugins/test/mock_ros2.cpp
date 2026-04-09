#include "mock_ros2.hpp"
#include "mock_classes.hpp"
#include <QJSValueIterator>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTimer>
#include <qml6_ros2_plugin/message_item_model.hpp>

extern MockRos2 *s_mockRos2;

namespace
{
void appendUniqueEntry( QJSEngine *engine, QJSValue &map, const QString &key, const QString &value )
{
  if ( !engine || key.isEmpty() || value.isEmpty() )
    return;
  if ( !map.isObject() )
    map = engine->newObject();

  QJSValue arr = map.property( key );
  if ( !arr.isArray() )
    arr = engine->newArray();

  const int len = arr.property( "length" ).toInt();
  for ( int i = 0; i < len; ++i ) {
    if ( arr.property( i ).toString() == value )
      return;
  }

  arr.setProperty( len, value );
  map.setProperty( key, arr );
}
} // namespace

void MockRos2::setEngine( QQmlEngine *engine )
{
  engine_ = engine;
  infoFn_ = engine_->evaluate( "(function() { console.log.apply(console, arguments); })" );
  debugFn_ = engine_->evaluate( "(function() { console.debug.apply(console, arguments); })" );
  warnFn_ = engine_->evaluate( "(function() { console.warn.apply(console, arguments); })" );
  errorFn_ = engine_->evaluate( "(function() { console.error.apply(console, arguments); })" );
  fatalFn_ = engine_->evaluate( "(function() { console.error.apply(console, arguments); })" );
  reset();
}

QVariant MockRos2::createEmptyMessage( const QString &datatype ) const
{
  try {
    ros_babel_fish::BabelFish fish = qml6_ros2_plugin::BabelFishDispenser::getBabelFish();
    auto message = fish.create_message_shared( datatype.toStdString() );
    return qml6_ros2_plugin::conversion::msgToMap( message );
  } catch ( ros_babel_fish::BabelFishException &ex ) {
    qWarning( "Failed to create empty message for datatype '%s': %s",
              datatype.toStdString().c_str(), ex.what() );
  }
  return QVariant();
}

QVariant MockRos2::createEmptyServiceRequest( const QString &datatype ) const
{
  try {
    ros_babel_fish::BabelFish fish = qml6_ros2_plugin::BabelFishDispenser::getBabelFish();
    auto message = fish.create_service_request_shared( datatype.toStdString() );
    return qml6_ros2_plugin::conversion::msgToMap( message );
  } catch ( ros_babel_fish::BabelFishException &ex ) {
    qWarning( "Failed to create empty service request for datatype '%s': %s",
              datatype.toStdString().c_str(), ex.what() );
  }
  return QVariant();
}

QVariant MockRos2::createEmptyServiceResponse( const QString &datatype ) const
{
  try {
    ros_babel_fish::BabelFish fish = qml6_ros2_plugin::BabelFishDispenser::getBabelFish();
    const auto &type_support = fish.get_service_type_support( datatype.toStdString() );
    auto message = ros_babel_fish::CompoundMessage::make_shared( type_support->response() );
    return qml6_ros2_plugin::conversion::msgToMap( message );
  } catch ( ros_babel_fish::BabelFishException &ex ) {
    qWarning( "Failed to create empty service response for datatype '%s': %s",
              datatype.toStdString().c_str(), ex.what() );
  }
  return QVariant();
}

QVariant MockRos2::createEmptyActionGoal( const QString &datatype ) const
{
  try {
    ros_babel_fish::BabelFish fish = qml6_ros2_plugin::BabelFishDispenser::getBabelFish();
    auto message = fish.create_action_goal_shared( datatype.toStdString() );
    return qml6_ros2_plugin::conversion::msgToMap( message );
  } catch ( ros_babel_fish::BabelFishException &ex ) {
    qWarning( "Failed to create empty action goal request for datatype '%s': %s",
              datatype.toStdString().c_str(), ex.what() );
  }
  return QVariant();
}

QVariant MockRos2::createEmptyActionFeedback( const QString &datatype ) const
{
  try {
    ros_babel_fish::BabelFish fish = qml6_ros2_plugin::BabelFishDispenser::getBabelFish();
    auto message = fish.create_message_shared( datatype.toStdString() + "_Feedback" );
    return qml6_ros2_plugin::conversion::msgToMap( message );
  } catch ( ros_babel_fish::BabelFishException &ex ) {
    qWarning( "Failed to create empty action feedback for datatype '%s': %s",
              datatype.toStdString().c_str(), ex.what() );
  }
  return QVariant();
}

QVariant MockRos2::createEmptyActionResult( const QString &datatype ) const
{
  try {
    ros_babel_fish::BabelFish fish = qml6_ros2_plugin::BabelFishDispenser::getBabelFish();
    auto message = fish.create_message_shared( datatype.toStdString() + "_Result" );
    return qml6_ros2_plugin::conversion::msgToMap( message );
  } catch ( ros_babel_fish::BabelFishException &ex ) {
    qWarning( "Failed to create empty action result for datatype '%s': %s",
              datatype.toStdString().c_str(), ex.what() );
  }
  return QVariant();
}

QObject *MockRos2::createGoalHandle( const QString &goal_id )
{
  return new MockGoalHandle( goal_id, this );
}

bool MockRos2::isValidTopic( const QString &topic ) const
{
  return !topic.isEmpty() && topic.startsWith( "/" ) && topic.size() > 1;
}
qml6_ros2_plugin::QoSWrapper MockRos2::QoS() { return qml6_ros2_plugin::QoSWrapper(); }
qml6_ros2_plugin::Time MockRos2::now() const { return qml6_ros2_plugin::Time(); }

QJSValue MockRos2::info()
{
  if ( !engine_ )
    return QJSValue::NullValue;
  if ( !infoFn_.isCallable() )
    infoFn_ = engine_->evaluate( "(function() { console.log('MOCK Ros2 INFO:', "
                                 "Array.prototype.join.call(arguments, ' ')); })" );
  return infoFn_;
}

QJSValue MockRos2::debug()
{
  if ( !debugFn_.isCallable() && engine_ )
    debugFn_ = engine_->evaluate( "(function() { console.log('MOCK Ros2 DEBUG:', "
                                  "Array.prototype.join.call(arguments, ' ')); })" );
  return debugFn_;
}
QJSValue MockRos2::warn()
{
  if ( !warnFn_.isCallable() && engine_ )
    warnFn_ = engine_->evaluate( "(function() { console.warn('MOCK Ros2 WARN:', "
                                 "Array.prototype.join.call(arguments, ' ')); })" );
  return warnFn_;
}
QJSValue MockRos2::error()
{
  if ( !errorFn_.isCallable() && engine_ )
    errorFn_ = engine_->evaluate( "(function() { console.error('MOCK Ros2 ERROR:', "
                                  "Array.prototype.join.call(arguments, ' ')); })" );
  return errorFn_;
}
QJSValue MockRos2::fatal()
{
  if ( !fatalFn_.isCallable() && engine_ )
    fatalFn_ = engine_->evaluate( "(function() { console.error('MOCK Ros2 FATAL:', "
                                  "Array.prototype.join.call(arguments, ' ')); })" );
  return fatalFn_;
}

QJSValue MockRos2::getServiceHandler( const QString &name )
{
  if ( !engine_ || !serviceHandlers_.isObject() )
    return QJSValue::NullValue;
  QJSValue handler = serviceHandlers_.property( name );
  if ( handler.isCallable() )
    return handler;
  return QJSValue::NullValue;
}

QJSValue MockRos2::getActionHandler( const QString &name )
{
  if ( !engine_ )
    return QJSValue::NullValue;

  if ( actionHandlers_.isObject() ) {
    QJSValue handler = actionHandlers_.property( name );
    if ( handler.isCallable() )
      return handler;
  }

  if ( actionHandler_.isCallable() )
    return actionHandler_;
  return QJSValue::NullValue;
}

QObject *MockRos2::getLogger( const QString & ) { return this; }

QStringList MockRos2::queryTopics( const QString &datatype ) const
{
  return jsStringList( mockTopics_, datatype );
}
QStringList MockRos2::queryTopicTypes( const QString &name ) const
{
  return jsStringList( mockTypeMap_, name );
}
QStringList MockRos2::getTopicTypes( const QString &name ) const { return queryTopicTypes( name ); }
QStringList MockRos2::queryServices( const QString &datatype ) const
{
  return jsStringList( mockServices_, datatype );
}
QStringList MockRos2::getServiceTypes( const QString &name ) const
{
  return jsStringList( mockTypeMap_, name );
}
QStringList MockRos2::queryActions( const QString &datatype ) const
{
  QStringList result;
  if ( mockActions_.isArray() ) {
    int len = mockActions_.property( "length" ).toInt();
    for ( int i = 0; i < len; ++i ) result.append( mockActions_.property( i ).toString() );
  } else {
    result = jsStringList( mockActions_, datatype );
  }
  return result;
}
QStringList MockRos2::getActionTypes( const QString &name ) const
{
  return jsStringList( mockTypeMap_, name );
}

// Factory implementations
QObject *MockRos2::createPublisher( const QString &topic, const QString &type, quint32 )
{
  registerTopic( topic, type );
  return new MockPublisher( this, topic, type, qml6_ros2_plugin::QoSWrapper() );
}
QObject *MockRos2::createServiceClient( const QString &name, const QString &type )
{
  return new MockServiceClient( this, name, type );
}
QObject *MockRos2::createActionClient( const QString &name, const QString &type )
{
  registerAction( name, type );
  return new MockActionClient( this, name, type );
}
QObject *MockRos2::createSubscription( const QString &topic, const QString &type, quint32 )
{
  return new MockSubscription( this, topic, type, qml6_ros2_plugin::QoSWrapper(), 10 );
}

void MockRos2::registerTopic( const QString &topic, const QString &type )
{
  appendUniqueEntry( engine_, mockTopics_, type, topic );
  appendUniqueEntry( engine_, mockTypeMap_, topic, type );
}

void MockRos2::registerAction( const QString &name, const QString &type, const QJSValue &handler )
{
  appendUniqueEntry( engine_, mockActions_, type, name );
  appendUniqueEntry( engine_, mockTypeMap_, name, type );
  if ( handler.isCallable() ) {
    if ( !actionHandlers_.isObject() )
      actionHandlers_ = engine_ ? engine_->newObject() : QJSValue::NullValue;
    if ( actionHandlers_.isObject() )
      actionHandlers_.setProperty( name, handler );
  }
}

void MockRos2::registerService( const QString &name, const QString &type, const QJSValue &handler )
{
  appendUniqueEntry( engine_, mockServices_, type, name );
  appendUniqueEntry( engine_, mockTypeMap_, name, type );
  if ( handler.isCallable() ) {
    if ( !serviceHandlers_.isObject() )
      serviceHandlers_ = engine_ ? engine_->newObject() : QJSValue::NullValue;
    if ( serviceHandlers_.isObject() )
      serviceHandlers_.setProperty( name, handler );
  }
}

void MockRos2::reset()
{
  mockTopics_ = QJSValue::NullValue;
  mockServices_ = QJSValue::NullValue;
  mockActions_ = QJSValue::NullValue;
  mockTypeMap_ = QJSValue::NullValue;
  serviceHandlers_ = QJSValue::NullValue;
  actionHandler_ = QJSValue::NullValue;
  actionHandlers_ = QJSValue::NullValue;
  publishedMessages_ = QJSValue::NullValue;
  lastActionGoalMessage_ = QJSValue::NullValue;
  lastActionCancelled_ = false;

  if ( engine_ ) {
    mockTopics_ = engine_->newObject();
    mockServices_ = engine_->newObject();
    mockActions_ = engine_->newObject();
    mockTypeMap_ = engine_->newObject();
    serviceHandlers_ = engine_->newObject();
    actionHandlers_ = engine_->newObject();
    publishedMessages_ = engine_->newArray();
  }

  subscriptions_.clear();
}

void MockRos2::_registerSubscription( QObject *sub ) { subscriptions_.append( sub ); }
void MockRos2::_unregisterSubscription( QObject *sub ) { subscriptions_.removeAll( sub ); }
QObject *MockRos2::findSubscription( const QString &topic ) const
{
  for ( QObject *sub : subscriptions_ ) {
    if ( sub->property( "topic" ).toString() == topic )
      return sub;
  }
  return nullptr;
}

QJSValue MockRos2::wrap( const QString &type, const QVariant &value )
{
  if ( !engine_ )
    return QJSValue::NullValue;

  ros_babel_fish::BabelFish fish = qml6_ros2_plugin::BabelFishDispenser::getBabelFish();
  auto msg = fish.create_message_shared( type.toStdString() );
  if ( !msg ) {
    qWarning() << "MOCK wrap: Failed to create message of type:" << type;
    if ( value.userType() == QMetaType::QVariantMap ) {
      QVariantMap m = value.toMap();
      m["#messageType"] = type;
      return engine_->toScriptValue( m );
    }
    return engine_->toScriptValue( value );
  }
  if ( !qml6_ros2_plugin::conversion::fillMessage( *msg, value ) ) {
    qWarning() << "MOCK wrap: Failed to fill message of type:" << type;
  }
  QVariant wrapped = qml6_ros2_plugin::conversion::msgToMap( msg );
  if ( wrapped.userType() == QMetaType::QVariantMap ) {
    QVariantMap map = wrapped.toMap();
    map["#messageType"] = type;
    wrapped = map;
  } else {
    qWarning() << "MOCK wrap: msgToMap did not return a map for type:" << type
               << ". Attempting fallback.";
    if ( value.userType() == QMetaType::QVariantMap ) {
      QVariantMap m = value.toMap();
      m["#messageType"] = type;
      wrapped = m;
    }
  }
  return engine_->toScriptValue( wrapped );
}

void MockRos2::setContextProperty( const QString &name, const QJSValue &value )
{
  if ( engine_ )
    engine_->rootContext()->setContextProperty( name, value.toVariant() );
}

void MockRos2::recordPublishedMessage( const QJSValue &entry )
{
  if ( publishedMessages_.isArray() ) {
    int len = publishedMessages_.property( "length" ).toInt();
    publishedMessages_.setProperty( len, entry );
  }
}

QStringList MockRos2::jsStringList( const QJSValue &map, const QString &key ) const
{
  QStringList result;
  if ( !map.isObject() )
    return result;

  if ( key.isEmpty() ) {
    // If no key/datatype is specified, return all unique entries from all keys
    if ( map.isArray() ) {
      int len = map.property( "length" ).toInt();
      for ( int i = 0; i < len; ++i ) result.append( map.property( i ).toString() );
    } else {
      QJSValueIterator it( map );
      while ( it.hasNext() ) {
        it.next();
        QJSValue arr = it.value();
        if ( arr.isArray() ) {
          int len = arr.property( "length" ).toInt();
          for ( int i = 0; i < len; ++i ) {
            QString val = arr.property( i ).toString();
            if ( !result.contains( val ) )
              result.append( val );
          }
        }
      }
    }
    return result;
  }

  QJSValue arr = map.property( key );
  if ( !arr.isArray() )
    arr = map.property( "" );
  if ( !arr.isArray() )
    return result;

  int len = arr.property( "length" ).toInt();
  result.reserve( len );
  for ( int i = 0; i < len; ++i ) result.append( arr.property( i ).toString() );
  return result;
}
