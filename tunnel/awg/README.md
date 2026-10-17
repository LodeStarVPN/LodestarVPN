# Туннель AmneziaWG с «сортировщиком»

Свой туннель AmneziaWG для Windows (`tunnel.dll`) и Android (`libwg-go.so`) — те же версии,
из которых собраны туннели FRKN в `client/3rd-prebuilt`, плюс «сортировщик»: соединения к
российским сетям, которые приложение пускает мимо VPN (переключатель «Российские сайты
напрямую»), туннель открывает сам, через сеть устройства, а не через сервер. Всё остальное —
как было: шифруется и уходит на сервер. Системных маршрутов для России нет вовсе, сколько бы
сетей ни было (система держит 450 на Windows и 150 на Android, а у страны их около 8 700).

## Как это устроено

- `amneziawg-go.patch` — пакет `sorter/` и три места в `device/`:
  - `send.go`: пакет IPv4 по TCP или UDP к сети из списка уходит не к серверу, а в сортировщик;
  - `uapi.go`: список задают строки `direct_network=<сеть>`. Строки одной команды `set`
    заменяют список целиком, `replace_direct_networks=true` без строк — очищает;
  - `device.go`: при закрытии туннель закрывает сортировщик.

  Сортировщик — сетевой стек gVisor (та же версия, что уже есть в amneziawg-go). Он играет
  дальнюю сторону соединения приложения, а данные несёт через обычный сокет устройства.
  Сокет выводится из VPN способом системы (`sorter.SetDialControl`); если вывести нельзя,
  соединение не открывается, чтобы не вернуться в туннель. ICMP (ping) идёт на сервер, как
  раньше. Проверки: `sorter/sorter_test.go` (без сети: второй стек играет приложения) и
  `device/sorter_test.go` (через весь туннель).
- `amneziawg-windows.patch` — прямые сокеты привязаны к интерфейсу лучшего маршрута по
  умолчанию, кроме туннельного (`IP_UNICAST_IF`, как WireGuard привязывает свой сокет); при
  смене сети привязка следует за ней (`directroute.go`). Защита от утечек их пропускает:
  туннель работает в процессе `lodestar-service.exe`, а ему разрешено всё
  (`WindowsFirewall::enableInterface`). Там же журнал туннеля остаётся в
  `Program Files\Dopamine` — там, где его ищет приложение, как было у FRKN.
- `amneziawg-android.patch` — каждый прямой сокет защищает служба VPN: `jni.c` вызывает
  `protect(fd)` у объекта, переданного через `GoBackend.awgSetProtector` до запуска туннеля
  (`SocketProtector` в `Wireguard.kt`).

Приложение: `VpnConnection::appendSplitTunnelingConfig` отдаёт весь список. На Windows он
идёт службе (`directNetworks`), а та передаёт его туннелю (`WireguardUtilsWindows::setDirectNetworks`).
На Android он идёт файлом (`directNetworksFile`, `DirectNetworks::saveForService`): настройки
доходят до службы VPN одним системным сообщением, а оно держит около 500 КБ.

## Сборка

`tunnel/awg/build.sh` в WSL (Ubuntu) или Linux. Нужны Go 1.25+, MinGW
(`gcc-mingw-w64-x86-64-posix`) и Android NDK (`ANDROID_NDK`, по умолчанию
`/opt/android-ndk/android-ndk-r26b`). Скрипт:

1. берёт upstream на закреплённых версиях: amneziawg-go `v3.1.20260814`,
   amneziawg-windows `e90531d1`, amneziawg-android `ff15093b`;
2. кладёт заплатки;
3. прогоняет проверки;
4. собирает в `client/3rd-lodestar/amneziawg/` (`windows/x64/tunnel.dll`,
   `android/<abi>/libwg-go.so`, у каждого файл `.sha256`).

Готовые файлы лежат в git: сборки приложения берут их оттуда (`package_msi.ps1`,
`client/cmake/android.cmake`), туннель пересобирается, только когда меняются заплатки.

Без сети (WSL на ПК владельца): клоны upstream в каталоге `AWG_UPSTREAM`, модули Go — из
локального зеркала (`GOPROXY=file://...`, `GOSUMDB=off`). Каждый модуль сверяется со
строками `go.sum`, которые upstream проверил по sum.golang.org. Обёртка, которая готовит всё
это со стороны Windows, лежит в репозитории сервера: `local-tools/client/build_awg_tunnel.ps1`.

Проверка `TestAWGDevicePing` из amneziawg-go в прогон не входит: в нетронутом upstream она
падает в 7 запусках из 10.
