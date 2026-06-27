#!/usr/bin/env bash
set -euo pipefail

MODEL="${DEEPSEEK_MODEL:-deepseek-v4-flash}"
BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
KEY="${DEEPSEEK_API_KEY:-}"

if [[ -z "$KEY" ]] && command -v security >/dev/null 2>&1; then
  KEY="$(security find-generic-password \
    -s com.focusflow.education-agent \
    -a deepseek_api_key \
    -w 2>/dev/null || true)"
fi

if [[ -z "$KEY" ]]; then
  echo "Missing DeepSeek API key. Set DEEPSEEK_API_KEY or save one in FocusFlow Settings." >&2
  exit 2
fi

PAYLOAD="$(mktemp "${TMPDIR:-/tmp}/focusflow_deepseek_payload.XXXXXX.json")"
CONFIG="$(mktemp "${TMPDIR:-/tmp}/focusflow_deepseek_curl.XXXXXX.conf")"
RESPONSE="$(mktemp "${TMPDIR:-/tmp}/focusflow_deepseek_response.XXXXXX.json")"
cleanup() {
  rm -f "$PAYLOAD" "$CONFIG" "$RESPONSE"
}
trap cleanup EXIT

chmod 600 "$PAYLOAD" "$CONFIG" "$RESPONSE"

python3 - "$PAYLOAD" "$MODEL" <<'PY'
import json
import sys

payload_path, model = sys.argv[1], sys.argv[2]
payload = {
    "model": model,
    "messages": [
        {
            "role": "system",
            "content": "You are a connectivity probe. Return only compact JSON."
        },
        {
            "role": "user",
            "content": "{\"ping\":\"focusflow\",\"expect\":\"pong\"}"
        }
    ],
    "temperature": 0,
    "response_format": {"type": "json_object"},
    "thinking": {"type": "disabled"}
}
with open(payload_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))
PY

cat >"$CONFIG" <<EOF
url = "${BASE_URL%/}/chat/completions"
request = "POST"
header = "Authorization: Bearer $KEY"
header = "Content-Type: application/json"
data = "@$PAYLOAD"
max-time = 45
silent
show-error
output = "$RESPONSE"
write-out = "%{http_code}"
EOF

HTTP_STATUS="$(curl --config "$CONFIG")"

if [[ ! "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]; then
  echo "DeepSeek request failed with HTTP $HTTP_STATUS." >&2
  python3 - "$RESPONSE" <<'PY' >&2
import json
import sys

path = sys.argv[1]
try:
    data = json.load(open(path, encoding="utf-8"))
    message = data.get("error", {}).get("message") or data.get("message") or str(data)
except Exception:
    message = open(path, encoding="utf-8", errors="replace").read()
print(message[:800])
PY
  exit 1
fi

python3 - "$RESPONSE" "$MODEL" <<'PY'
import json
import sys

response_path, model = sys.argv[1], sys.argv[2]
data = json.load(open(response_path, encoding="utf-8"))
content = data["choices"][0]["message"].get("content", "").strip()
if not content:
    raise SystemExit("DeepSeek returned an empty message.")
try:
    parsed = json.loads(content)
except json.JSONDecodeError as exc:
    raise SystemExit(f"DeepSeek did not return JSON content: {exc}")
print(f"DeepSeek connectivity OK: model={model}, content={json.dumps(parsed, ensure_ascii=False, separators=(',', ':'))}")
PY

