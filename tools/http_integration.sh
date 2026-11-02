#!/usr/bin/env bash
set -euo pipefail

port=18765
received="$(mktemp)"
server_log="$(mktemp)"
probe="$(mktemp)"
cleanup() {
    kill "${server_pid:-}" 2>/dev/null || true
    rm -f "$received" "$server_log" "$probe"
}
trap cleanup EXIT

python3 tools/http_test_server.py "$received" "$port" >"$server_log" 2>&1 &
server_pid=$!
sleep 0.2

dmd -I=source -I=../containers-d/source \
    source/transport/source.d source/transport/buffer.d \
    source/transport/http.d ../containers-d/source/containers/package.d \
    ../containers-d/source/containers/segmented_buffer.d \
    ../containers-d/source/containers/internal/*.d tools/http_probe.d \
    -L-lcurl -of="$probe"
"$probe" "http://127.0.0.1:$port/resource"

test "$(od -An -t u1 "$received" | tr -d ' \n')" = "9 8 7 6"
