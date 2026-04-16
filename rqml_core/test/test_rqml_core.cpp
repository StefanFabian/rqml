#include <QQmlContext>
#include <QQmlEngine>
#include <QtQuickTest>

class TestContextBridge : public QObject
{
  Q_OBJECT
public:
  explicit TestContextBridge( QQmlEngine *engine ) : engine_( engine ) { }

  Q_INVOKABLE void setContextProperty( const QString &name, QObject *value )
  {
    if ( !engine_ )
      return;
    engine_->rootContext()->setContextProperty( name, value );
  }

private:
  QQmlEngine *engine_ = nullptr;
};

class Setup : public QObject
{
  Q_OBJECT
public:
  Setup() { }

public slots:
  void qmlEngineAvailable( QQmlEngine *engine )
  {
    bridge_ = std::make_unique<TestContextBridge>( engine );
    engine->rootContext()->setContextProperty( "TestContextBridge", bridge_.get() );
  }

private:
  std::unique_ptr<TestContextBridge> bridge_;
};

QUICK_TEST_MAIN_WITH_SETUP( RqmlCoreTest, Setup )

#include "test_rqml_core.moc"
