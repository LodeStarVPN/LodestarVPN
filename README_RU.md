<img src="client/images/icon.png" height="96">

# LodestarVPN

Клиент сервиса LodestarVPN для Windows. Вы вводите ID подписки, приложение
получает ваши серверы (AmneziaWG и VLESS+Reality), проверяет пинг и
подключается к быстрому и не перегруженному серверу.

Основан на [Dopamine](https://github.com/frkn-dev/dopamine) от FRKN, который
в свою очередь является форком [AmneziaVPN](https://github.com/amnezia-vpn/amnezia-client).

Сайт: https://lodestarvpn.com · [English](README.md)

## Сборка под Windows

Нужны Visual Studio 2022, Qt 6.10 для MSVC 2022 x64 с модулями Shader Tools,
5Compat и RemoteObjects, CMake 3.25+ и Ninja.

```
git clone --recursive https://github.com/zZDraculaZz/LodestarVPN.git
cd LodestarVPN
cmake -B build_local -G Ninja -DCMAKE_BUILD_TYPE=Release ^
      -DCMAKE_PREFIX_PATH=<папка Qt>\msvc2022_64 ^
      -DLODESTAR_GATEWAY_URL=https://your-gateway.example/ ^
      -DLODESTAR_GATEWAY_KEY=path\to\gateway_public.pem
cmake --build build_local
```

Приложение работает через шлюз по протоколу AGW. Адрес шлюза и его
открытый RSA-ключ задаются при сборке и в репозиторий не входят.

Установщик собирает `package_msi.ps1` (нужны WiX 4 и CMake 3.30+; если Qt и
cpack не в PATH, укажите `QT_BIN` и `CPACK`). Результат:
`build_local\LodestarVPN-<версия>-win64.msi`.

## Лицензия

[GPL-3.0](LICENSE), как у Dopamine и AmneziaVPN. Название и логотип
LodestarVPN обозначают этот проект, для форков, пожалуйста, используйте свои.
