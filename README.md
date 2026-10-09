<img src="client/images/icon.png" height="96">

# LodestarVPN

Windows client of the LodestarVPN service. You enter your subscription ID,
the app gets your servers (AmneziaWG and VLESS+Reality), checks their ping
and connects to a fast server that is not overloaded.

Built on [Dopamine](https://github.com/frkn-dev/dopamine) by FRKN, which is a
fork of [AmneziaVPN](https://github.com/amnezia-vpn/amnezia-client).

Website: https://lodestarvpn.com · [Русский](README_RU.md)

## Building on Windows

You need Visual Studio 2022, Qt 6.10 for MSVC 2022 x64 with the Shader Tools,
5Compat and RemoteObjects modules, CMake 3.25+ and Ninja.

```
git clone --recursive https://github.com/LodeStarVPN/LodestarVPN.git
cd LodestarVPN
cmake -B build_local -G Ninja -DCMAKE_BUILD_TYPE=Release ^
      -DCMAKE_PREFIX_PATH=<Qt dir>\msvc2022_64 ^
      -DLODESTAR_GATEWAY_URL=https://your-gateway.example/ ^
      -DLODESTAR_GATEWAY_KEY=path\to\gateway_public.pem
cmake --build build_local
```

The app talks to a gateway over the AGW protocol. The gateway's URL and RSA
public key are build settings and are not part of this repository.

The installer is built by `package_msi.ps1` (WiX 4 and CMake 3.30+; set
`QT_BIN` and `CPACK` if they are not on PATH). It produces
`build_local\LodestarVPN-<version>-win64.msi`.

## License

[GPL-3.0](LICENSE), the same as Dopamine and AmneziaVPN. The LodestarVPN name
and logo identify this project; please give forks their own.
