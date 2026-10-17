# Свои готовые библиотеки

`amneziawg/` — туннель AmneziaWG с «сортировщиком» (Российские сайты напрямую). Он
собирается из `tunnel/awg` (исходники, заплатки и `build.sh` — там) и заменяет туннель из
`client/3rd-prebuilt`:

- `windows/x64/tunnel.dll` — его кладёт в MSI `package_msi.ps1`;
- `android/<abi>/libwg-go.so` — его берёт `client/cmake/android.cmake`.

Рядом с каждым файлом лежит его SHA-256. Руками не менять — только пересобрать.
