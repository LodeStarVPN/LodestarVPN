/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef DAEMONLOCALSERVER_H
#define DAEMONLOCALSERVER_H

#include <QLocalServer>

class DaemonLocalServer final : public QObject {
  Q_DISABLE_COPY_MOVE(DaemonLocalServer)

 public:
  explicit DaemonLocalServer(QObject* parent);
  ~DaemonLocalServer();

  bool initialize();
#ifdef MZ_WINDOWS
  // an instance of the daemon's pipe is still there (an old service's)
  bool pipeLeftOver() const;
#endif

 private:
  QString daemonPath() const;

 private:
  QLocalServer m_server;
};

#endif  // DAEMONLOCALSERVER_H
