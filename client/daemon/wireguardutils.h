/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef WIREGUARDUTILS_H
#define WIREGUARDUTILS_H

#define _WINSOCKAPI_

#include <QCoreApplication>
#include <QHostAddress>
#include <QObject>
#include <QStringList>

#include "interfaceconfig.h"

constexpr const char* WG_INTERFACE = "amn0";

constexpr uint16_t WG_KEEPALIVE_PERIOD = 60;

class WireguardUtils : public QObject {
  Q_OBJECT

 public:
  class PeerStatus {
   public:
    PeerStatus(const QString& pubkey = QString()) { m_pubkey = pubkey; }
    QString m_pubkey;
    qint64 m_handshake = 0;
    qint64 m_rxBytes = 0;
    qint64 m_txBytes = 0;
    // the tunnel's, not the peer's: the apps' data both ways it went, through the VPN and past it
    // (data_rx_bytes, data_tx_bytes of our AmneziaWG; -1 where the tunnel keeps none)
    qint64 m_dataRxBytes = -1;
    qint64 m_dataTxBytes = -1;
    // when they were read: nanoseconds of the steady clock (QDeadlineTimer), the same in every process
    qint64 m_sampleNs = 0;
  };

  explicit WireguardUtils(QObject* parent) : QObject(parent){};
  virtual ~WireguardUtils() = default;

  virtual bool interfaceExists() = 0;
  virtual QString interfaceName() { return WG_INTERFACE; }
  virtual bool addInterface(const InterfaceConfig& config) = 0;
  virtual bool deleteInterface() = 0;

  virtual bool updatePeer(const InterfaceConfig& config) = 0;
  virtual bool deletePeer(const InterfaceConfig& config) = 0;
  virtual QList<PeerStatus> getPeerStatus() = 0;

  virtual bool updateRoutePrefix(const IPAddress& prefix) = 0;
  virtual bool deleteRoutePrefix(const IPAddress& prefix) = 0;
  
  virtual bool addExclusionRoute(const IPAddress& prefix) = 0;
  virtual bool deleteExclusionRoute(const IPAddress& prefix) = 0;
  // many at once (the Russian networks the app sends past the VPN: hundreds); one by one
  // where a platform does no better
  virtual bool addExclusionRoutes(const QList<IPAddress>& prefixes) {
    bool ok = true;
    for (const IPAddress& prefix : prefixes) {
      ok = addExclusionRoute(prefix) && ok;
    }
    return ok;
  }
  virtual void deleteExclusionRoutes(const QList<IPAddress>& prefixes) {
    for (const IPAddress& prefix : prefixes) {
      deleteExclusionRoute(prefix);
    }
  }

  virtual bool excludeLocalNetworks(const QList<IPAddress>& addresses) = 0;

  // the networks whose connections the tunnel opens by the device's own network itself (its
  // sorter, tunnel/awg; none: no more); false where the tunnel cannot, and they go through it
  virtual bool setDirectNetworks(const QStringList& networks) { return networks.isEmpty(); }
};

#endif  // WIREGUARDUTILS_H
