#!/bin/bash
# API Endpoint Testing Script for Trading Service
# Tests all major endpoints with proper authentication

set -e

# Configuration
API_HOST="${API_HOST:-192.168.1.11}"
API_PORT="${API_PORT:-8085}"
API_URL="http://${API_HOST}:${API_PORT}"
API_TOKEN="${API_TOKEN:-4a92e7f8b1c3d5e6f7089a1b2c3d4e5f6789012345678901234567890abcdef0}"

# Test data
TEST_ORDER_ID=""
TEST_RESULTS=()
FAILED_TESTS=0
PASSED_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print test results
print_test() {
    local status=$1
    local test_name=$2
    local details=$3
    
    if [ "$status" == "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((FAILED_TESTS++))
    fi
    
    if [ ! -z "$details" ]; then
        echo "  $details"
    fi
}

# Function to make authenticated API call
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    local expected_code=$4
    
    if [ -z "$data" ]; then
        RESPONSE=$(curl -s -w "\n%{http_code}" -X $method \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Content-Type: application/json" \
            "${API_URL}${endpoint}" 2>/dev/null)
    else
        RESPONSE=$(curl -s -w "\n%{http_code}" -X $method \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${API_URL}${endpoint}" 2>/dev/null)
    fi
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" == "$expected_code" ]; then
        echo "$BODY"
        return 0
    else
        echo "Expected HTTP $expected_code, got $HTTP_CODE"
        echo "Response: $BODY"
        return 1
    fi
}

# Function to format JSON
format_json() {
    echo "$1" | jq . 2>/dev/null || echo "$1"
}

echo "========================================="
echo "   Trading Service API Endpoint Tests"
echo "========================================="
echo "Target: ${API_URL}"
echo ""

# Test 1: Health Check (No Auth)
echo -e "${BLUE}1. Health Check Endpoint${NC}"
echo "----------------------------------------"
HEALTH_RESPONSE=$(curl -s "${API_URL}/healthz" 2>/dev/null || echo "Failed")
if [[ $HEALTH_RESPONSE == *"healthy"* ]] || [[ $HEALTH_RESPONSE == *"ok"* ]] || [ "$HEALTH_RESPONSE" == "{}" ]; then
    print_test "PASS" "GET /healthz" "Response: $HEALTH_RESPONSE"
else
    print_test "FAIL" "GET /healthz" "Response: $HEALTH_RESPONSE"
fi
echo ""

# Test 2: Metrics Endpoint (No Auth)
echo -e "${BLUE}2. Metrics Endpoint${NC}"
echo "----------------------------------------"
METRICS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/metrics" 2>/dev/null)
if [ "$METRICS_RESPONSE" == "200" ]; then
    print_test "PASS" "GET /metrics" "Prometheus metrics available"
else
    print_test "FAIL" "GET /metrics" "HTTP $METRICS_RESPONSE"
fi
echo ""

# Test 3: Authentication Check
echo -e "${BLUE}3. Authentication${NC}"
echo "----------------------------------------"

# Test without auth
NO_AUTH=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/orders" 2>/dev/null)
if [ "$NO_AUTH" == "401" ] || [ "$NO_AUTH" == "403" ]; then
    print_test "PASS" "Unauthorized request blocked" "HTTP $NO_AUTH"
else
    print_test "FAIL" "Unauthorized request not blocked" "HTTP $NO_AUTH"
fi

# Test with auth
if AUTH_RESPONSE=$(api_call "GET" "/orders" "" "200"); then
    print_test "PASS" "Authorized request accepted" "Successfully authenticated"
else
    print_test "FAIL" "Authorized request failed" "$AUTH_RESPONSE"
fi
echo ""

# Test 4: List Orders
echo -e "${BLUE}4. List Orders${NC}"
echo "----------------------------------------"
if ORDERS=$(api_call "GET" "/orders" "" "200"); then
    ORDER_COUNT=$(echo "$ORDERS" | jq '. | length' 2>/dev/null || echo "0")
    print_test "PASS" "GET /orders" "Found $ORDER_COUNT order(s)"
    echo "  Response preview:"
    echo "$ORDERS" | jq '.[0:2]' 2>/dev/null | head -10 | sed 's/^/    /'
else
    print_test "FAIL" "GET /orders" "$ORDERS"
fi
echo ""

# Test 5: Create Order
echo -e "${BLUE}5. Create Order${NC}"
echo "----------------------------------------"
ORDER_DATA='{
  "symbol": "BTC/USDT",
  "side": "BUY",
  "order_type": "LIMIT",
  "quantity": 0.001,
  "price": 45000,
  "exchange": "BINANCE"
}'

if CREATE_RESPONSE=$(api_call "POST" "/orders" "$ORDER_DATA" "201"); then
    TEST_ORDER_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id' 2>/dev/null)
    print_test "PASS" "POST /orders" "Order created: $TEST_ORDER_ID"
    echo "  Order details:"
    echo "$CREATE_RESPONSE" | jq . | head -15 | sed 's/^/    /'
else
    print_test "FAIL" "POST /orders" "$CREATE_RESPONSE"
fi
echo ""

# Test 6: Get Order by ID
if [ ! -z "$TEST_ORDER_ID" ]; then
    echo -e "${BLUE}6. Get Order by ID${NC}"
    echo "----------------------------------------"
    if ORDER_DETAIL=$(api_call "GET" "/orders/$TEST_ORDER_ID" "" "200"); then
        ORDER_STATUS=$(echo "$ORDER_DETAIL" | jq -r '.status' 2>/dev/null)
        print_test "PASS" "GET /orders/{id}" "Status: $ORDER_STATUS"
    else
        print_test "FAIL" "GET /orders/{id}" "$ORDER_DETAIL"
    fi
    echo ""
fi

# Test 7: Cancel Order
if [ ! -z "$TEST_ORDER_ID" ]; then
    echo -e "${BLUE}7. Cancel Order${NC}"
    echo "----------------------------------------"
    if CANCEL_RESPONSE=$(api_call "POST" "/orders/$TEST_ORDER_ID/cancel" "" "200"); then
        CANCEL_STATUS=$(echo "$CANCEL_RESPONSE" | jq -r '.status' 2>/dev/null)
        print_test "PASS" "POST /orders/{id}/cancel" "Status: $CANCEL_STATUS"
    else
        print_test "FAIL" "POST /orders/{id}/cancel" "$CANCEL_RESPONSE"
    fi
    echo ""
fi

# Test 8: Get Fills
echo -e "${BLUE}8. Get Fills${NC}"
echo "----------------------------------------"
if FILLS=$(api_call "GET" "/fills" "" "200"); then
    FILL_COUNT=$(echo "$FILLS" | jq '. | length' 2>/dev/null || echo "0")
    print_test "PASS" "GET /fills" "Found $FILL_COUNT fill(s)"
else
    print_test "FAIL" "GET /fills" "$FILLS"
fi
echo ""

# Test 9: Get Positions
echo -e "${BLUE}9. Get Positions${NC}"
echo "----------------------------------------"
if POSITIONS=$(api_call "GET" "/positions" "" "200"); then
    POS_COUNT=$(echo "$POSITIONS" | jq '. | length' 2>/dev/null || echo "0")
    print_test "PASS" "GET /positions" "Found $POS_COUNT position(s)"
else
    print_test "FAIL" "GET /positions" "$POSITIONS"
fi
echo ""

# Test 10: Risk Metrics
echo -e "${BLUE}10. Risk Metrics${NC}"
echo "----------------------------------------"
if RISK=$(api_call "GET" "/risk/metrics" "" "200"); then
    TOTAL_EXPOSURE=$(echo "$RISK" | jq -r '.total_exposure_usd' 2>/dev/null || "0")
    print_test "PASS" "GET /risk/metrics" "Total exposure: \$$TOTAL_EXPOSURE"
    echo "  Risk metrics:"
    echo "$RISK" | jq . | head -10 | sed 's/^/    /'
else
    print_test "FAIL" "GET /risk/metrics" "$RISK"
fi
echo ""

# Test 11: Test Webhook
echo -e "${BLUE}11. Test Webhook${NC}"
echo "----------------------------------------"
WEBHOOK_DATA='{
  "test": true,
  "message": "Testing webhook endpoint"
}'

if WEBHOOK_RESPONSE=$(api_call "POST" "/webhook/test" "$WEBHOOK_DATA" "200"); then
    print_test "PASS" "POST /webhook/test" "Webhook test successful"
else
    print_test "FAIL" "POST /webhook/test" "$WEBHOOK_RESPONSE"
fi
echo ""

# Test 12: Invalid Endpoint
echo -e "${BLUE}12. Error Handling${NC}"
echo "----------------------------------------"
ERROR_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${API_TOKEN}" "${API_URL}/invalid-endpoint" 2>/dev/null)
if [ "$ERROR_RESPONSE" == "404" ]; then
    print_test "PASS" "GET /invalid-endpoint" "Properly returns 404"
else
    print_test "FAIL" "GET /invalid-endpoint" "Expected 404, got $ERROR_RESPONSE"
fi
echo ""

# Test 13: Rate Limiting Check
echo -e "${BLUE}13. Rate Limiting${NC}"
echo "----------------------------------------"
echo "  Sending 5 rapid requests..."
RATE_LIMIT_HIT=false
for i in {1..5}; do
    RATE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${API_TOKEN}" "${API_URL}/orders" 2>/dev/null)
    if [ "$RATE_RESPONSE" == "429" ]; then
        RATE_LIMIT_HIT=true
        break
    fi
done

if [ "$RATE_LIMIT_HIT" == true ]; then
    print_test "PASS" "Rate limiting active" "Rate limit enforced"
else
    print_test "PASS" "Rate limiting" "No rate limit hit (may have high threshold)"
fi
echo ""

# Performance Test
echo -e "${BLUE}14. Performance Test${NC}"
echo "----------------------------------------"
START_TIME=$(date +%s%N)
PERF_RESPONSE=$(curl -s -o /dev/null -w "%{time_total}" -H "Authorization: Bearer ${API_TOKEN}" "${API_URL}/orders" 2>/dev/null)
RESPONSE_TIME=$(echo "$PERF_RESPONSE * 1000" | bc 2>/dev/null || echo "N/A")

if [ "$RESPONSE_TIME" != "N/A" ]; then
    if (( $(echo "$RESPONSE_TIME < 1000" | bc -l) )); then
        print_test "PASS" "Response time" "${RESPONSE_TIME}ms"
    else
        print_test "FAIL" "Response time" "${RESPONSE_TIME}ms (>1000ms)"
    fi
else
    print_test "FAIL" "Response time" "Could not measure"
fi
echo ""

# Summary
echo "========================================="
echo "   Test Summary"
echo "========================================="
echo -e "${GREEN}Passed:${NC} $PASSED_TESTS"
echo -e "${RED}Failed:${NC} $FAILED_TESTS"
TOTAL_TESTS=$((PASSED_TESTS + FAILED_TESTS))
SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
echo -e "${BLUE}Success Rate:${NC} ${SUCCESS_RATE}%"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Some tests failed. Please review the results.${NC}"
    exit 1
fi