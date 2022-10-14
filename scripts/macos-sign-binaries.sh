#!/usr/bin/env bash

# intended to run on MacOS only
# signs all executable files in a given folder (as $1) with developer certificate

# required variables:
# APPLE_DEVELOPER_IDENTITY: "Developer ID Application: <company name> (<hex id>)"
# APPLE_DEVELOPER_ID_BUNDLE: base64-encoded content of apple developer id certificate bundle in pksc12 format
# APPLE_DEVELOPER_ID_BUNDLE_PASSWORD: password used when exporting the bundle

# note: 'bundle' in apple terminology is 'identity'

set -euo pipefail

if [[ "${APPLE_DEVELOPER_ID_BUNDLE:-0}" == 0 || "${APPLE_DEVELOPER_ID_BUNDLE_PASSWORD:-0}" == 0 ]]; then
    echo "Apple developer certificate is not configured, skip signing"
    exit 0
fi

REL_DIR="${1}"
PKSC12_FILE="$HOME/developer-id-application.p12"
base64 --decode > "${PKSC12_FILE}" <<<"${APPLE_DEVELOPER_ID_BUNDLE}"

KEYCHAIN='emqx.keychain-db'
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings -lut 21600 "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${PKSC12_FILE}" -P "${APPLE_DEVELOPER_ID_BUNDLE_PASSWORD}" -t cert -f pkcs12 -k "${KEYCHAIN}" -T /usr/bin/codesign
security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security verify-cert -k "${KEYCHAIN}" -c "${PKSC12_FILE}"
security find-identity -p codesigning "${KEYCHAIN}"

# add new keychain into the search path for codesign, otherwise the stuff does not work
keychains=$(security list-keychains -d user)
keychain_names=();
for keychain in ${keychains}; do
    basename=$(basename "${keychain}")
    keychain_name=${basename::${#basename}-4}
    keychain_names+=("${keychain_name}")
done
security -v list-keychains -s "${keychain_names[@]}" "${KEYCHAIN}"

# sign
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/erts-*/bin/{beam.smp,dyn_erl,epmd,erl,erl_call,erl_child_setup,erlexec,escript,heart,inet_gethost,run_erl,to_erl}
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/asn1-*/priv/lib/asn1rt_nif.so
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/bcrypt-*/priv/bcrypt_nif.so
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/crypto-*/priv/lib/{crypto.so,otp_test_engine.so}
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/jiffy-*/priv/jiffy.so
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/jq-*/priv/{jq_nif1.so,libjq.1.dylib,libonig.4.dylib,erlang_jq_port}
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/os_mon-*/priv/bin/{cpu_sup,memsup}
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/rocksdb-*/priv/liberocksdb.so
codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime "${REL_DIR}"/lib/runtime_tools-*/priv/lib/{dyntrace.so,trace_ip_drv.so,trace_file_drv.so}
find "${REL_DIR}/lib/" -name libquicer_nif.so -exec codesign -s "${APPLE_DEVELOPER_IDENTITY}" -f --verbose=4 --timestamp --options=runtime {} \;
