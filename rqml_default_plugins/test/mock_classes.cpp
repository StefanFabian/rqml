#include "mock_classes.hpp"
#include "mock_ros2.hpp"
#include <QDateTime>
#include <QJSValue>
#include <QJsonDocument>
#include <QQmlEngine>
#include <QRandomGenerator>
#include <QTimer>

MockRos2 *s_mockRos2 = nullptr;

// =============================================================================
// MockGoalHandle
// =============================================================================
MockGoalHandle::MockGoalHandle( QString goal_id, QObject *parent )
    : QObject( parent ), goal_id_( goal_id ), status_( 0 )
{
}

bool MockGoalHandle::isActive() const
{
  return status_ == 1 || status_ == 2; // Accepted or Executing
}

void MockGoalHandle::cancel()
{
  if ( s_mockRos2 )
    s_mockRos2->setLastActionCancelled( true );
}

void MockGoalHandle::setStatus( int status )
{
  if ( status_ == status )
    return;
  status_ = status;
  emit statusChanged();
}

// =============================================================================
// MockRQml
// =============================================================================
QString MockRQml::readFile( const QString &path ) const { return files.value( path, QString() ); }
bool MockRQml::writeFile( const QString &path, const QString &text )
{
  files[path] = text;
  return true;
}
bool MockRQml::fileExists( const QString &path ) const { return files.contains( path ); }
void MockRQml::copyTextToClipboard( const QString &text ) { setClipboard( text ); }

// =============================================================================
// MockSubscription
// =============================================================================
MockSubscription::MockSubscription( QObject *p )
    : QObject( p ), qos_( qml6_ros2_plugin::QoSWrapper() )
{
}

MockSubscription::MockSubscription( MockRos2 *parent, QString topic, QString type,
                                    qml6_ros2_plugin::QoSWrapper qos, quint32 queue_size )
    : QObject( (QObject *)parent ), topic_( topic ), type_( type ), queueSize_( queue_size ),
      qos_( qos )
{
  if ( parent )
    parent->_registerSubscription( this );
}

MockSubscription::~MockSubscription()
{
  if ( s_mockRos2 )
    s_mockRos2->_unregisterSubscription( this );
}

void MockSubscription::setTopic( const QString &t )
{
  if ( topic_ == t )
    return;
  if ( s_mockRos2 )
    s_mockRos2->_unregisterSubscription( this );
  topic_ = t;
  if ( s_mockRos2 )
    s_mockRos2->_registerSubscription( this );
  emit topicChanged();
}

void MockSubscription::injectMessage( const QVariant &msg )
{
  if ( !s_mockRos2 )
    return;
  // Wrap via babel_fish to ensure the message has proper structure and #messageType
  QJSValue wrapped = s_mockRos2->wrap( type_, msg );
  lastMessage_ = wrapped.toVariant();
  const double nowSeconds = QDateTime::currentMSecsSinceEpoch() / 1000.0;
  static QHash<const MockSubscription *, double> lastReceiveTime;
  const double previousTime = lastReceiveTime.value( this, 0.0 );
  if ( previousTime > 0.0 && nowSeconds > previousTime )
    setFrequency( 1.0 / ( nowSeconds - previousTime ) );
  lastReceiveTime.insert( this, nowSeconds );

  const QByteArray jsonBytes =
      QJsonDocument::fromVariant( lastMessage_ ).toJson( QJsonDocument::Compact );
  setBandwidth( frequency_ * static_cast<double>( jsonBytes.size() ) );
  emit newMessage( lastMessage_ );
  emit messageChanged();
}

// =============================================================================
// MockServiceClient
// =============================================================================
MockServiceClient::MockServiceClient( QObject *p )
    : QObject( p ), qos_( qml6_ros2_plugin::QoSWrapper() )
{
}
MockServiceClient::MockServiceClient( MockRos2 *parent, const QString &name, const QString &type )
    : QObject( (QObject *)parent ), name_( name ), type_( type ),
      qos_( qml6_ros2_plugin::QoSWrapper() )
{
}

void MockServiceClient::sendRequestAsync( const QVariantMap &req, const QJSValue &callback )
{
  pendingRequests_++;
  emit pendingRequestsChanged();

  // Defer by one event loop tick to match production async behavior
  auto *timer = new QTimer( this );
  timer->setSingleShot( true );
  timer->setInterval( 0 );
  QJSValue cb = callback;
  QJSEngine *eng = s_mockRos2 ? s_mockRos2->engine() : nullptr;

  connect( timer, &QTimer::timeout, this, [this, timer, cb, req, eng]() mutable {
    timer->deleteLater();
    pendingRequests_--;
    emit pendingRequestsChanged();

    QJSValue handler = s_mockRos2 ? s_mockRos2->getServiceHandler( name_ ) : QJSValue::NullValue;
    if ( !handler.isCallable() ) {
      qWarning() << "MOCK: No handler registered for service:" << name_;
      if ( cb.isCallable() )
        cb.call( { QJSValue::NullValue } );
      return;
    }

    // Call handler: response = handler(request)
    QJSValue response = handler.call( { eng->toScriptValue( req ) } );

    // Wrap the response so it provides the same interface (.at()) as real ROS 2 messages
    QJSValue wrappedResponse = response;
    if ( s_mockRos2 ) {
      wrappedResponse = s_mockRos2->wrap( type_ + "_Response", response.toVariant() );
    }

    if ( cb.isCallable() )
      cb.call( { wrappedResponse } );
  } );
  timer->start();
}

// =============================================================================
// MockPublisher
// =============================================================================
MockPublisher::MockPublisher( QObject *p )
    : QObject( p ), qos_( qml6_ros2_plugin::QoSWrapper() ) { }
MockPublisher::MockPublisher( MockRos2 *parent, const QString &topic, const QString &type,
                              qml6_ros2_plugin::QoSWrapper qos )
    : QObject( (QObject *)parent ), topic_( topic ), type_( type ), qos_( qos )
{
  if ( parent )
    parent->registerTopic( topic_, type_ );
}

void MockPublisher::setTopic( const QString &t )
{
  if ( topic_ == t )
    return;
  topic_ = t;
  if ( s_mockRos2 )
    s_mockRos2->registerTopic( topic_, type_ );
  emit topicChanged();
}

void MockPublisher::setType( const QString &t )
{
  if ( type_ == t )
    return;
  type_ = t;
  if ( s_mockRos2 )
    s_mockRos2->registerTopic( topic_, type_ );
  emit typeChanged();
}

bool MockPublisher::publish( const QVariantMap &msg )
{
  QJSEngine *eng = s_mockRos2 ? s_mockRos2->engine() : nullptr;
  if ( !eng || !s_mockRos2 )
    return false;
  s_mockRos2->registerTopic( topic_, type_ );

  // Record it
  QJSValue entry = eng->newObject();
  entry.setProperty( "topic", topic_ );
  entry.setProperty( "type", type_ );
  entry.setProperty( "message", eng->toScriptValue( msg ) );
  s_mockRos2->recordPublishedMessage( entry );

  // Broadcast to local mock subscriptions
  const QList<QObject *> &subs = s_mockRos2->subscriptions();
  for ( QObject *obj : subs ) {
    MockSubscription *sub = qobject_cast<MockSubscription *>( obj );
    if ( sub && sub->topic() == topic_ && sub->messageType() == type_ ) {
      sub->injectMessage( msg );
    }
  }
  return true;
}

// =============================================================================
// MockActionClient
// =============================================================================
MockActionClient::MockActionClient( QObject *p ) : QObject( p ) { }
MockActionClient::MockActionClient( MockRos2 *parent, const QString &name, const QString &type )
    : QObject( (QObject *)parent ), name_( name ), type_( type )
{
}

QJSValue MockActionClient::sendGoalAsync( const QJSValue &goal, const QJSValue &options )
{
  if ( !s_mockRos2 )
    return QJSValue::NullValue;
  QJSValue handler = s_mockRos2->getActionHandler( name_ );
  if ( !handler.isCallable() ) {
    qWarning() << "MOCK: No action handler registered for:" << name_;
    return QJSValue::NullValue;
  }

  QTimer::singleShot( 0, [handler, goal, options]() mutable {
    QJSValueList args;
    args << goal << options;
    QJSValue mutableHandler = handler;
    mutableHandler.call( args );
  } );
  return QJSValue::NullValue;
}

void MockActionClient::cancelAllGoals()
{
  if ( s_mockRos2 )
    s_mockRos2->setLastActionCancelled( true );
}

#include "mock_classes.moc"
