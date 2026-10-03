#include "version.h"
#include "localserver.h"
#include "router.h"
#include "systemservice.h"
#include "xray.h"


#ifdef Q_OS_WIN
#include "platforms/windows/daemon/windowsdaemontunnel.h"

namespace {
int s_argc = 0;
char** s_argv = nullptr;
}  // namespace
#endif

SystemService::SystemService(int argc, char **argv)
    : QtService<QCoreApplication>(argc, argv, SERVICE_NAME)
{
    setServiceDescription("Service for Dopamine");

#ifdef Q_OS_WIN
    if(argc > 2){
        s_argc = argc;
        s_argv = argv;
        QStringList tokens;

        for (int i = 1; i < argc; ++i) {
            tokens.append(QString(argv[i]));
        }

        if (!tokens.empty() && tokens[0] == "tunneldaemon") {
            WindowsDaemonTunnel *daemon = new WindowsDaemonTunnel();
            daemon->run(tokens);
        }

    }
#endif

}

void SystemService::start()
{
    QCoreApplication* app = application();
    m_localServer  = new LocalServer();
}

void SystemService::stop()
{
    // stopped under a VLESS session (an upgrade, say): the app never gets to
    // tear it down, and IPv6 would stay blocked until a reboot
    if (Xray::getInstance().isRunning()) {
        Router::StartRoutingIpv6();
        Xray::getInstance().stopXray();
    }
    delete m_localServer;
}
