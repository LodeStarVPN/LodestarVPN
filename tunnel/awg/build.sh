#!/bin/bash
# LodestarVPN's AmneziaWG tunnel: amneziawg-go with the sorter (its sorter/ package: the Russian
# networks the app sends past the VPN are opened by the device's own network, not by a peer),
# built for Windows (tunnel.dll, from amneziawg-windows) and Android (libwg-go.so, from
# amneziawg-android) into client/3rd-lodestar/amneziawg. Upstream is taken at the versions the
# prebuilt tunnels of client/3rd-prebuilt were built from, and the patches next to this script
# are put on top.
#
# In WSL (Ubuntu) or any Linux: Go 1.25+ (go on PATH), MinGW (gcc-mingw-w64-x86-64-posix), the
# Android NDK (ANDROID_NDK, default /opt/android-ndk/android-ndk-r26b).
#   tunnel/awg/build.sh [work dir]
# AWG_UPSTREAM: a directory with clones of the three repositories (a machine without network;
# then GOPROXY points at a local module mirror, see README.md). Otherwise cloned from GitHub.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="${1:-$HOME/awg-build/work}"
ndk="${ANDROID_NDK:-/opt/android-ndk/android-ndk-r26b}"
out="$repo/client/3rd-lodestar/amneziawg"

AWG_GO_REF=v3.1.20260814
AWG_WINDOWS_REF=e90531d15802cb976773f3b63443bc281f738ca3
AWG_ANDROID_REF=ff15093bf3856fea0947923474870b86efb682f0

git_() { git -c core.autocrlf=false -c advice.detachedHead=false "$@"; }
fetch() { # repository, ref
    if [ -n "${AWG_UPSTREAM:-}" ]; then
        git_ clone -q "$AWG_UPSTREAM/$1" "$work/$1"
    else
        git_ clone -q --filter=blob:none "https://github.com/amnezia-vpn/$1.git" "$work/$1"
    fi
    git_ -C "$work/$1" checkout -q "$2"
    git_ -C "$work/$1" apply "$here/$1.patch"
    echo "$1 $2 + $1.patch"
}
rm -rf "$work"
mkdir -p "$work"
fetch amneziawg-go "$AWG_GO_REF"
fetch amneziawg-windows "$AWG_WINDOWS_REF"
fetch amneziawg-android "$AWG_ANDROID_REF"
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly
go version

echo "== tests of the sorter (TestAWGDevicePing is upstream's and fails most runs as it is)"
(cd "$work/amneziawg-go" && go vet ./sorter && go test -count=1 -skip TestAWGDevicePing ./sorter ./device)

echo "== tunnel.dll (the flags of amneziawg-windows' build.cmd)"
mkdir -p "$out/windows/x64"
(cd "$work/amneziawg-windows" && \
  GOOS=windows GOARCH=amd64 CGO_ENABLED=1 CC=x86_64-w64-mingw32-gcc \
  CGO_CFLAGS="-O3 -Wall -Wno-unused-function -Wno-switch -std=gnu11 -DWINVER=0x0601" \
  CGO_LDFLAGS="-Wl,--dynamicbase -Wl,--nxcompat -Wl,--export-all-symbols -Wl,--high-entropy-va" \
  go build -buildmode c-shared -ldflags="-w -s" -trimpath -o "$out/windows/x64/tunnel.dll" . )
rm -f "$out/windows/x64/tunnel.h"

echo "== libwg-go.so (the flags of amneziawg-android's libwg-go Makefile)"
tc="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
build_android() { # abi, GOARCH, clang, GOARM
    mkdir -p "$out/android/$1"
    (cd "$work/amneziawg-android/tunnel/tools/libwg-go" && \
      GOOS=android GOARCH="$2" GOARM="${4:-}" CGO_ENABLED=1 CC="$tc/$3" \
      CGO_CFLAGS="-O2" CGO_LDFLAGS="-Wl,-soname=libwg-go.so -Wl,--build-id=none" \
      go build -tags linux -ldflags="-s -w -buildid=" -trimpath -buildvcs=false -buildmode c-shared \
        -o "$out/android/$1/libwg-go.so" . )
    rm -f "$out/android/$1/libwg-go.h"
}
build_android arm64-v8a arm64 aarch64-linux-android21-clang
build_android armeabi-v7a arm armv7a-linux-androideabi21-clang 7
build_android x86_64 amd64 x86_64-linux-android21-clang

for f in "$out"/windows/x64/tunnel.dll "$out"/android/*/libwg-go.so; do
    sha256sum "$f" | cut -d' ' -f1 > "$f.sha256"
    echo "$(cut -c1-16 "$f.sha256")  $(du -h "$f" | cut -f1)  ${f#$repo/}"
done
