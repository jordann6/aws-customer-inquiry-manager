#!/usr/bin/env bash
set -euo pipefail

API_URL="${1:?Usage: seed_inquiries.sh <api-url>}"

echo "==> Submitting inquiries..."

INQUIRY_ID=$(
  curl -sf -X POST "$API_URL/inquiries" \
    -H "Content-Type: application/json" \
    -d '{"name":"Alice Johnson","email":"alice@example.com","subject":"Billing question","message":"I was charged twice for my last invoice. Can you look into this?"}' \
  | jq -r '.inquiry_id'
)
echo "Created: $INQUIRY_ID"

curl -sf -X POST "$API_URL/inquiries" \
  -H "Content-Type: application/json" \
  -d '{"name":"Bob Smith","email":"bob@example.com","subject":"Feature request","message":"It would be great to have CSV export support in the reporting module."}' \
  | jq -r '.inquiry_id'

echo ""
echo "==> Listing open inquiries..."
curl -sf "$API_URL/inquiries?status=open" | jq 'length'

echo ""
echo "==> Updating first inquiry to in-progress..."
curl -sf -X PATCH "$API_URL/inquiries/$INQUIRY_ID/status" \
  -H "Content-Type: application/json" \
  -d '{"status":"in-progress"}' | jq '{inquiry_id, status, updated_at}'
