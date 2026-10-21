#!/usr/bin/env bash
# Smoke test — posts one valid order and asserts a 202 response.
# Run after every deploy to confirm the API Gateway → Lambda path is live.
#
# Usage: ./scripts/health_check.sh https://<api-id>.execute-api.eu-west-1.amazonaws.com/dev

set -euo pipefail

ENDPOINT="${1:?Usage: health_check.sh <api-endpoint-base-url>}"
ORDER_ID="smoke-$(date +%s)"

PAYLOAD=$(printf '{"orderId":"%s","customerId":"smoke-test","items":[{"sku":"SMOKE","qty":1,"price":1.00}],"totalAmount":1.00}' "$ORDER_ID")

HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" \
  --max-time 10 \
  --request POST \
  --header "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "${ENDPOINT%/}/orders")

if [ "$HTTP_CODE" = "202" ]; then
  echo "OK  ($HTTP_CODE) — orderId=$ORDER_ID accepted"
  exit 0
else
  echo "FAIL ($HTTP_CODE) — expected 202" >&2
  exit 1
fi
