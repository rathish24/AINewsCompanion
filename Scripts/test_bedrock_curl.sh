#!/usr/bin/env bash
# Test AWS Bedrock (Llama 3.2 3B) with curl via awscurl (SigV4). Exit 0 only on HTTP 200.
# Prereqs: pip install awscurl; AWS credentials configured (aws configure or env).
# Usage: ./test_bedrock_curl.sh [REGION]
set -e
REGION="${1:-us-east-1}"
MODEL_ID="meta.llama3-2-3b-instruct-v1:0"
URL="https://bedrock-runtime.${REGION}.amazonaws.com/model/${MODEL_ID}/invoke"

# Same body shape as AWSBedrockClient (Llama): prompt (chat template), max_gen_len, temperature, top_p
BODY='{"prompt":"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\nYou are a precise news companion. Always respond with valid JSON only.<|eot_id|><|start_header_id|>user<|end_header_id|>\n\nHello<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n","max_gen_len":64,"temperature":0.2,"top_p":0.9}'

echo "Testing Bedrock: $URL"
OUT=$(awscurl --service bedrock --region "$REGION" -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$BODY" \
  -i 2>&1) || true

STATUS=$(echo "$OUT" | sed -n 's/^HTTP\/[0-9.]* \([0-9]*\) .*/\1/p' | head -1)
if [ -z "$STATUS" ] && echo "$OUT" | grep -q "AttributeError\|credentials\|NoneType"; then
  echo "FAIL: AWS credentials not configured. Run: aws configure (or set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
  exit 1
fi
if [ "$STATUS" = "200" ]; then
  if echo "$OUT" | grep -q '"generation"'; then
    echo "OK: statusCode 200, response has generation."
    echo "$OUT" | tail -1 | head -c 200
    echo "..."
    exit 0
  fi
fi
echo "FAIL: status=$STATUS (expected 200). Install awscurl: pip install awscurl; configure AWS: aws configure"
echo "$OUT" | head -25
exit 1
