#!/bin/bash

API_URL="https://m11do12rth.execute-api.us-east-1.amazonaws.com/prod"

echo "Testing API Gateway endpoint..."

# Test upload endpoint
curl -X POST "$API_URL/upload" \
    -H "Content-Type: application/json" \
    -d '{"test": "data"}' \
    -v

echo -e "\n\nAPI test complete"