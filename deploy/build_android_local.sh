#!/bin/bash
# LodestarVPN for Android, built on Linux (WSL): release APKs signed with our own key.
#
# Everything comes from the environment, so no address or key lives in the tree:
#   LODESTAR_GATEWAY_URL, LODESTAR_GATEWAY_FALLBACK_URL, LODESTAR_GATEWAY_CA,
#   LODESTAR_GATEWAY_KEY        - as for the Windows build (client/CMakeLists.txt)
#   ANDROID_KEYSTORE_PATH       - the release key (PKCS12/JKS)
#   ANDROID_KEYSTORE_PASS_FILE  - a file holding its password (read here, never on a command line)
#   ANDROID_KEYSTORE_KEY_ALIAS  - default "lodestar"
#   ABIS                        - default "arm64-v8a;armeabi-v7a;x86_64"
#   QT_ROOT                     - default /opt/Qt/6.10.1 (gcc_64 and the android_* kits inside)
#   ANDROID_SDK_ROOT, ANDROID_NDK_ROOT, JAVA_HOME
#   CLEAN=1                     - start from an empty deploy/build
#
# Run it from a copy of the tree on a Linux file system: building on /mnt/<drive> is
# several times slower. The APKs land in deploy/build/: one per ABI and a universal one.
set -euo pipefail

: "${LODESTAR_GATEWAY_URL:?set LODESTAR_GATEWAY_URL}"
: "${ANDROID_KEYSTORE_PATH:?set ANDROID_KEYSTORE_PATH to the release key}"
: "${ANDROID_KEYSTORE_PASS_FILE:?set ANDROID_KEYSTORE_PASS_FILE}"
[ -f "$ANDROID_KEYSTORE_PATH" ] || { echo "No key at $ANDROID_KEYSTORE_PATH" >&2; exit 1; }

export ANDROID_KEYSTORE_KEY_ALIAS="${ANDROID_KEYSTORE_KEY_ALIAS:-lodestar}"
ANDROID_KEYSTORE_KEY_PASS="$(tr -d '\r\n' < "$ANDROID_KEYSTORE_PASS_FILE")"
export ANDROID_KEYSTORE_KEY_PASS

QT_ROOT="${QT_ROOT:-/opt/Qt/6.10.1}"
export QT_HOST_PATH="$QT_ROOT/gcc_64"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-/opt/android-ndk/android-ndk-r26b}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$JAVA_HOME/bin:$PATH"
# values read from Windows files may end in CR: in a compile definition it breaks the build
strip_cr() { local v="${1:-}"; printf '%s' "${v//$'\r'/}"; }
LODESTAR_GATEWAY_URL="$(strip_cr "$LODESTAR_GATEWAY_URL")"
LODESTAR_GATEWAY_FALLBACK_URL="$(strip_cr "${LODESTAR_GATEWAY_FALLBACK_URL:-}")"
LODESTAR_GATEWAY_CA="$(strip_cr "${LODESTAR_GATEWAY_CA:-}")"
LODESTAR_GATEWAY_KEY="$(strip_cr "${LODESTAR_GATEWAY_KEY:-}")"
export LODESTAR_GATEWAY_URL LODESTAR_GATEWAY_FALLBACK_URL LODESTAR_GATEWAY_CA LODESTAR_GATEWAY_KEY

ABIS="${ABIS:-arm64-v8a;armeabi-v7a;x86_64}"

cd "$(dirname "$0")/.."
if [ "${CLEAN:-0}" = 1 ]; then
    rm -rf deploy/build
fi
# the gateway's authority is copied into client/ at configure time; a stale copy must not stay
# behind when none is given
if [ -z "$LODESTAR_GATEWAY_CA" ]; then
    echo "LODESTAR_GATEWAY_CA is not set: https gateways are checked against the system's authorities" >&2
fi

# only what this run builds may be left in deploy/build
rm -f deploy/build/LodestarVPN-*.apk
./deploy/build_android.sh --apk "$ABIS" --move

# what goes out is checked, not assumed: the manifest is filled in, the key is ours
BT="$(ls -d "$ANDROID_SDK_ROOT"/build-tools/* | sort -V | tail -1)"
want="$("$JAVA_HOME/bin/keytool" -list -keystore "$ANDROID_KEYSTORE_PATH" -alias "$ANDROID_KEYSTORE_KEY_ALIAS" \
        -storepass:env ANDROID_KEYSTORE_KEY_PASS -v | sed -n 's/^.*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f')"
status=0
for apk in deploy/build/LodestarVPN-*-release.apk; do
    if "$BT/aapt2" dump xmltree --file AndroidManifest.xml "$apk" | grep -q '%%INSERT'; then
        echo "FAIL $apk: the manifest still holds a placeholder" >&2
        status=1
    fi
    # every ABI the APK offers has the app's own library: a phone picks the ABI by the
    # libraries it finds, and without ours there the app dies at start
    libs="$(unzip -Z1 "$apk" 'lib/*' 2>/dev/null || true)"
    for abi in $(printf '%s\n' "$libs" | cut -d/ -f2 | sort -u); do
        if ! printf '%s\n' "$libs" | grep -qx "lib/$abi/libDopamine_$abi.so"; then
            echo "FAIL $apk: lib/$abi has no libDopamine_$abi.so" >&2
            status=1
        fi
    done
    got="$("$BT/apksigner" verify --print-certs "$apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
    if [ "$got" != "$want" ]; then
        echo "FAIL $apk: not signed with the release key" >&2
        status=1
    fi
    echo "$apk: $("$BT/aapt2" dump badging "$apk" | sed -n "s/^package: name='\([^']*\)' versionCode='\([^']*\)' versionName='\([^']*\)'.*/\1 \3 (\2)/p"), $("$BT/aapt2" dump badging "$apk" | sed -n 's/^native-code: //p')"
done
exit $status
