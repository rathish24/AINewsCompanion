#!/bin/sh
# Check Azure OpenAI endpoint HTTP status. Reads key from ApiKeys.xcconfig in same directory.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/ApiKeys.xcconfig"
if [ ! -f "$CONFIG" ]; then
  echo "ERROR: ApiKeys.xcconfig not found at $CONFIG"
  exit 1
fi
KEY=$(grep '^AZURE_OPENAI_API_KEY' "$CONFIG" | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"')
ENDPOINT=$(grep '^AZURE_OPENAI_ENDPOINT' "$CONFIG" | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"')
DEPLOYMENT=$(grep '^AZURE_OPENAI_DEPLOYMENT' "$CONFIG" | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"')

# Azure URL: base can be with or without /openai/v1; we need .../openai/deployments/<name>/chat/completions
BASE="${ENDPOINT%/openai/v1}"
BASE="${BASE%/}"
URL="${BASE}/openai/deployments/${DEPLOYMENT}/chat/completions?api-version=2024-02-15"

echo "URL: $URL"
echo "Deployment: $DEPLOYMENT"
echo "---"

if [ -z "$KEY" ]; then
  echo "ERROR: AZURE_OPENAI_API_KEY not found in config"
  exit 1
fi

HTTP_CODE=$(curl -s -o /tmp/azure_check_body.txt -w "%{http_code}" -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "api-key: $KEY" \
  -d '{"messages":[{"role":"user","content":"Say hello in one word"}],"max_tokens":20}')
echo "HTTP status: $HTTP_CODE"
echo "Response (first 600 chars):"
head -c 600 /tmp/azure_check_body.txt
echo ""
rm -f /tmp/azure_check_body.txt
