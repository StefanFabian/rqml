#pragma once
#include "qml6_ros2_plugin/qos.hpp"
#include <QJSEngine>
#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariantMap>

class MockRos2;
extern MockRos2 *s_mockRos2;

// =============================================================================
// MockGoalHandle - Represents an active action goal in the mock environment.
// Properties mirror the production GoalHandle exposed by qml6_ros2_plugin.
// =============================================================================
class MockGoalHandle : public QObject
{
  Q_OBJECT
  Q_PROPERTY( int status READ status NOTIFY statusChanged )
  Q_PROPERTY( QString goalId READ goalId CONSTANT )
  Q_PROPERTY( QVariant goalStamp READ goalStamp CONSTANT )
  Q_PROPERTY( bool isActive READ isActive NOTIFY statusChanged )
public:
  explicit MockGoalHandle( QString goal_id, QObject *parent = nullptr );

  int status() const { return status_; }
  QString goalId() const { return goal_id_; }
  QVariant goalStamp() const { return QVariant(); }
  bool isActive() const;

  Q_INVOKABLE void cancel();

  Q_INVOKABLE void setStatus( int status );

signals:
  void statusChanged();

private:
  QString goal_id_;
  int status_;
};

// =============================================================================
// MockRQml - Test double for the RQml file I/O singleton.
// =============================================================================
class MockRQml : public QObject
{
  Q_OBJECT
  Q_PROPERTY( QString clipboard READ clipboard WRITE setClipboard NOTIFY clipboardChanged )
public:
  explicit MockRQml( QObject *p = nullptr ) : QObject( p ) { }
  Q_INVOKABLE QString readFile( const QString &path ) const;
  Q_INVOKABLE bool writeFile( const QString &path, const QString &text );
  Q_INVOKABLE bool fileExists( const QString &path ) const;
  Q_INVOKABLE void copyTextToClipboard( const QString &text );
  Q_INVOKABLE void resetClipboard() { setClipboard( QString() ); }

  QString clipboard() const { return clipboard_; }
  void setClipboard( const QString &s )
  {
    if ( clipboard_ == s )
      return;
    clipboard_ = s;
    emit clipboardChanged();
  }

signals:
  void clipboardChanged();

public:
  QMap<QString, QString> files;

private:
  QString clipboard_;
};

// =============================================================================
// MockSubscription - Test double for `Subscription {}` QML type.
// Mirrors production property names and signals.
// =============================================================================
class MockSubscription : public QObject
{
  Q_OBJECT
  Q_PROPERTY( QString topic READ topic WRITE setTopic NOTIFY topicChanged )
  Q_PROPERTY( QString messageType READ messageType WRITE setMessageType NOTIFY messageTypeChanged )
  Q_PROPERTY( int throttleRate READ throttleRate WRITE setThrottleRate NOTIFY throttleRateChanged )
  Q_PROPERTY( int queueSize READ queueSize WRITE setQueueSize NOTIFY queueSizeChanged )
  Q_PROPERTY( qml6_ros2_plugin::QoSWrapper qos READ qos WRITE setQos NOTIFY qosChanged )
  Q_PROPERTY( QVariant message READ message NOTIFY messageChanged )
  Q_PROPERTY( double frequency READ frequency WRITE setFrequency NOTIFY frequencyChanged )
  Q_PROPERTY( double bandwidth READ bandwidth WRITE setBandwidth NOTIFY bandwidthChanged )
  Q_PROPERTY( bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged )
  Q_PROPERTY( bool subscribed READ subscribed NOTIFY subscribedChanged )
public:
  explicit MockSubscription( QObject *p = nullptr );
  MockSubscription( MockRos2 *parent, QString topic, QString type, qml6_ros2_plugin::QoSWrapper qos,
                    quint32 queue_size );
  ~MockSubscription() override;

  QString topic() const { return topic_; }
  void setTopic( const QString &t );

  QString messageType() const { return type_; }
  void setMessageType( const QString &t )
  {
    if ( type_ == t )
      return;
    type_ = t;
    emit messageTypeChanged();
  }

  int throttleRate() const { return throttleRate_; }
  void setThrottleRate( int r )
  {
    throttleRate_ = r;
    emit throttleRateChanged();
  }

  int queueSize() const { return queueSize_; }
  void setQueueSize( int s )
  {
    queueSize_ = s;
    emit queueSizeChanged();
  }

  qml6_ros2_plugin::QoSWrapper qos() const { return qos_; }
  void setQos( const qml6_ros2_plugin::QoSWrapper &q )
  {
    qos_ = q;
    emit qosChanged();
  }

  QVariant message() const { return lastMessage_; }

  double frequency() const { return frequency_; }
  void setFrequency( double value )
  {
    if ( qFuzzyCompare( frequency_, value ) )
      return;
    frequency_ = value;
    emit frequencyChanged();
  }

  double bandwidth() const { return bandwidth_; }
  void setBandwidth( double value )
  {
    if ( qFuzzyCompare( bandwidth_, value ) )
      return;
    bandwidth_ = value;
    emit bandwidthChanged();
  }

  bool enabled() const { return enabled_; }
  void setEnabled( bool e )
  {
    if ( enabled_ == e )
      return;
    enabled_ = e;
    emit enabledChanged();
  }

  bool subscribed() const { return subscribed_; }

  Q_INVOKABLE int getPublisherCount() const { return 1; }

  /// Inject a message into this subscription.
  /// The message is wrapped via Ros2.wrap() to ensure it has proper structure
  /// (including #messageType metadata), matching production behavior.
  Q_INVOKABLE void injectMessage( const QVariant &msg );

signals:
  void newMessage( QVariant msg );
  void messageChanged();
  void frequencyChanged();
  void bandwidthChanged();
  void qosChanged();
  void topicChanged();
  void messageTypeChanged();
  void throttleRateChanged();
  void queueSizeChanged();
  void enabledChanged();
  void subscribedChanged();

private:
  QString topic_, type_;
  int throttleRate_ = 0, queueSize_ = 10;
  qml6_ros2_plugin::QoSWrapper qos_;
  QVariant lastMessage_;
  double frequency_ = 0.0;
  double bandwidth_ = 0.0;
  bool enabled_ = true, subscribed_ = true;
};

// =============================================================================
// MockServiceClient - Test double for service clients created via
// `Ros2.createServiceClient()`. Requests are dispatched to the handler
// registered in `Ros2._serviceHandlers[name]`.
// =============================================================================
class MockServiceClient : public QObject
{
  Q_OBJECT
  Q_PROPERTY( bool ready READ ready CONSTANT )
  Q_PROPERTY( QString name READ name CONSTANT )
  Q_PROPERTY( QString type READ type CONSTANT )
  Q_PROPERTY( int pendingRequests READ pendingRequests NOTIFY pendingRequestsChanged )
  Q_PROPERTY( int connectionTimeout READ connectionTimeout WRITE setConnectionTimeout NOTIFY
                  connectionTimeoutChanged )
  Q_PROPERTY( qml6_ros2_plugin::QoSWrapper qos READ qos WRITE setQos NOTIFY qosChanged )
public:
  explicit MockServiceClient( QObject *p = nullptr );
  MockServiceClient( MockRos2 *parent, const QString &name, const QString &type );

  bool ready() const { return true; }
  QString name() const { return name_; }
  QString type() const { return type_; }
  int pendingRequests() const { return pendingRequests_; }
  int connectionTimeout() const { return timeout_; }
  void setConnectionTimeout( int t )
  {
    timeout_ = t;
    emit connectionTimeoutChanged();
  }
  qml6_ros2_plugin::QoSWrapper qos() const { return qos_; }
  void setQos( const qml6_ros2_plugin::QoSWrapper &q )
  {
    qos_ = q;
    emit qosChanged();
  }

  /// Sends a request asynchronously. The handler registered in
  /// `Ros2._serviceHandlers[name]` is called after one event loop tick.
  /// If no handler is registered, the callback receives null.
  Q_INVOKABLE void sendRequestAsync( const QVariantMap &req, const QJSValue &callback );

signals:
  void serviceReadyChanged();
  void connectionTimeoutChanged();
  void pendingRequestsChanged();
  void qosChanged();

private:
  QString name_, type_;
  int timeout_ = 5000, pendingRequests_ = 0;
  qml6_ros2_plugin::QoSWrapper qos_;
};

// =============================================================================
// MockPublisher - Test double for publishers created via
// `Ros2.createPublisher()`. Published messages are recorded in
// `Ros2.publishedMessages`.
// =============================================================================
class MockPublisher : public QObject
{
  Q_OBJECT
  Q_PROPERTY( QString topic READ topic WRITE setTopic NOTIFY topicChanged )
  Q_PROPERTY( QString type READ type WRITE setType NOTIFY typeChanged )
  Q_PROPERTY( bool isAdvertised READ isAdvertised CONSTANT )
  Q_PROPERTY( qml6_ros2_plugin::QoSWrapper qos READ qos WRITE setQos NOTIFY qosChanged )
public:
  explicit MockPublisher( QObject *p = nullptr );
  MockPublisher( MockRos2 *parent, const QString &topic, const QString &type,
                 qml6_ros2_plugin::QoSWrapper qos );
  QString topic() const { return topic_; }
  void setTopic( const QString &t );
  QString type() const { return type_; }
  void setType( const QString &t );
  bool isAdvertised() const { return true; }
  qml6_ros2_plugin::QoSWrapper qos() const { return qos_; }
  void setQos( const qml6_ros2_plugin::QoSWrapper &q )
  {
    qos_ = q;
    emit qosChanged();
  }

  Q_INVOKABLE int getSubscriptionCount() const { return 1; }
  Q_INVOKABLE bool publish( const QVariantMap &msg );
signals:
  void topicChanged();
  void typeChanged();
  void qosChanged();

private:
  QString topic_;
  QString type_;
  qml6_ros2_plugin::QoSWrapper qos_;
};

// =============================================================================
// MockActionClient - Test double for action clients created via
// `Ros2.createActionClient()`. Goals are dispatched to the handler
// registered in `Ros2._actionHandler`.
// =============================================================================
class MockActionClient : public QObject
{
  Q_OBJECT
  Q_PROPERTY( bool ready READ ready CONSTANT )
  Q_PROPERTY( QString name READ name CONSTANT )
  Q_PROPERTY( QString type READ type CONSTANT )
public:
  explicit MockActionClient( QObject *p = nullptr );
  MockActionClient( MockRos2 *parent, const QString &name, const QString &type );
  bool ready() const { return true; }

  QString name() const { return name_; }
  QString type() const { return type_; }

  /// Sends a goal asynchronously. The handler function registered in
  /// `Ros2._actionHandler` is called after one event loop tick with
  /// (goal, callbacks). The test drives the flow by calling
  /// callbacks.onGoalResponse, callbacks.onFeedback, and callbacks.onResult.
  Q_INVOKABLE QJSValue sendGoalAsync( const QJSValue &goal, const QJSValue &options );
  Q_INVOKABLE void cancelAllGoals();
signals:
  void readyChanged();

private:
  QString name_, type_;
};
