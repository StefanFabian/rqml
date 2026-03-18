#include <QQmlEngine>
#include <QtQuickTest>

class Setup : public QObject
{
  Q_OBJECT
public:
  Setup() { }

public slots:
  void qmlEngineAvailable( QQmlEngine *engine ) { Q_UNUSED( engine ); }
};

QUICK_TEST_MAIN_WITH_SETUP( RqmlCoreTest, Setup )

#include "test_rqml_core.moc"
