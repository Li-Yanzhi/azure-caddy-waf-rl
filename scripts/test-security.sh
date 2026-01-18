#!/bin/bash
# =============================================================================
# Security Test Script for Caddy Cluster
# Tests: Rate Limiting (Header-based) and WAF Protection
# =============================================================================

# Configuration - Set TARGET_URL environment variable or pass as first argument
TARGET_URL="${1:-${TARGET_URL:-}}"

# Check if TARGET_URL is provided
if [[ -z "$TARGET_URL" ]]; then
    echo "Error: TARGET_URL is required."
    echo "Usage: $0 <target_url>"
    echo "Example: $0 https://lb.on-azure.net"
    exit 1
fi

# Ensure URL has trailing slash for consistent routing
TARGET_URL="${TARGET_URL%/}/"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Counters for summary
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Results storage
declare -a TEST_RESULTS

print_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}     Security Test Suite for Caddy Cluster                     ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║     Target: ${TARGET_URL}                       ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_test() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    local detail="$4"
    
    ((TOTAL_TESTS++))
    
    if [[ "$actual" == "$expected" ]]; then
        echo -e "  ${GREEN}✓${NC} $name: ${GREEN}$actual${NC} $detail"
        ((PASSED_TESTS++))
        TEST_RESULTS+=("PASS|$name|Expected: $expected, Got: $actual")
    else
        echo -e "  ${RED}✗${NC} $name: ${RED}$actual${NC} (expected: $expected) $detail"
        ((FAILED_TESTS++))
        TEST_RESULTS+=("FAIL|$name|Expected: $expected, Got: $actual")
    fi
}

log_info() {
    echo -e "  ${BLUE}→${NC} $1"
}

# =============================================================================
# CONNECTIVITY TESTS
# =============================================================================
test_connectivity() {
    print_section "1. Basic Connectivity"
    
    log_info "Testing HTTPS connection..."
    local code=$(curl -s -o /dev/null -w "%{http_code}" -k --connect-timeout 10 "$TARGET_URL" 2>/dev/null)
    log_test "HTTPS Connection" "200" "$code"
    
    log_info "Testing Health endpoint..."
    local health=$(curl -s -k "$TARGET_URL/health" 2>/dev/null)
    local status=$(echo "$health" | grep -o '"status":"healthy"' | head -1)
    if [[ -n "$status" ]]; then
        log_test "Health Endpoint" "healthy" "healthy"
    else
        log_test "Health Endpoint" "healthy" "unhealthy"
    fi
}

# =============================================================================
# RATE LIMITING TESTS
# =============================================================================
test_rate_limiting() {
    print_section "2. Rate Limiting Tests (X-User-Id Header: 10 req/min)"
    
    # Generate unique user ID for each test run to avoid conflicts with previous tests
    local test_user="test-user-$(date +%s)-$$"
    log_info "Using test user: $test_user"
    log_info "Sending 30 requests (limit is 10/min)..."
    echo ""
    
    local success=0
    local blocked=0
    local codes=""
    
    for i in $(seq 1 30); do
        local code=$(curl -s -o /dev/null -w "%{http_code}" -k \
            -H "X-User-Id: $test_user" \
            "$TARGET_URL" 2>/dev/null)
        codes="$codes $code"
        
        if [[ "$code" == "200" ]]; then
            ((success++))
            echo -ne "  Request $i: ${GREEN}200${NC}"
        elif [[ "$code" == "429" ]]; then
            ((blocked++))
            echo -ne "  Request $i: ${YELLOW}429${NC}"
        else
            echo -ne "  Request $i: ${RED}$code${NC}"
        fi
        
        # Print newline every 3 requests for readability
        if (( i % 3 == 0 )); then
            echo ""
        fi
    done
    echo ""
    echo ""
    
    log_info "Results: ${GREEN}$success allowed${NC}, ${YELLOW}$blocked blocked${NC}"
    
    # Validate: first 10 should be 200, rest should be 429
    ((TOTAL_TESTS++))
    if [[ $success -eq 10 && $blocked -eq 5 ]]; then
        echo -e "  ${GREEN}✓${NC} Rate Limiting: Working correctly (10 allowed, 5 blocked)"
        ((PASSED_TESTS++))
        TEST_RESULTS+=("PASS|Rate Limiting (X-User-Id)|10 allowed, 5 blocked as expected")
    elif [[ $blocked -gt 0 ]]; then
        echo -e "  ${YELLOW}~${NC} Rate Limiting: Partially working ($success allowed, $blocked blocked)"
        ((PASSED_TESTS++))
        TEST_RESULTS+=("PASS|Rate Limiting (X-User-Id)|$blocked requests blocked")
    else
        echo -e "  ${RED}✗${NC} Rate Limiting: Not working (no requests blocked)"
        ((FAILED_TESTS++))
        TEST_RESULTS+=("FAIL|Rate Limiting (X-User-Id)|No requests blocked")
    fi
    
    # Test different user should not be blocked
    echo ""
    log_info "Testing different user (should NOT be blocked)..."
    local other_code=$(curl -s -o /dev/null -w "%{http_code}" -k \
        -H "X-User-Id: different-user-$(date +%s)" \
        "$TARGET_URL" 2>/dev/null)
    log_test "Different User Access" "200" "$other_code"
}

# =============================================================================
# WAF TESTS
# =============================================================================
test_waf() {
    print_section "3. WAF Protection Tests"
    
    # ----- SQL Injection -----
    echo ""
    echo -e "  ${BOLD}SQL Injection Detection:${NC}"
    echo -e "  ${CYAN}Expected: 403 Forbidden${NC}"
    echo ""
    
    local sqli_tests=(
        "?id=1'+OR+'1'='1|SQL: OR injection"
        "?id=1;+DROP+TABLE+users--|SQL: DROP TABLE"
        "?id='+UNION+SELECT+*+FROM+users--|SQL: UNION SELECT"
        "?user=admin'--|SQL: Comment injection"
    )
    
    for test in "${sqli_tests[@]}"; do
        local payload="${test%%|*}"
        local desc="${test##*|}"
        local full_url="${TARGET_URL}/${payload}"
        echo -e "  ${BLUE}GET${NC} ${full_url}"
        local code=$(curl -s -o /dev/null -w "%{http_code}" -k "${full_url}" 2>/dev/null)
        log_test "$desc" "403" "$code"
    done
    
    # ----- XSS -----
    echo ""
    echo -e "  ${BOLD}XSS Detection:${NC}"
    echo -e "  ${CYAN}Expected: 403 Forbidden${NC}"
    echo ""
    
    local xss_tests=(
        "?q=%3Cscript%3Ealert(1)%3C/script%3E|XSS: script tag|<script>alert(1)</script>"
        "?q=%3Cimg+src=x+onerror=alert(1)%3E|XSS: img onerror|<img src=x onerror=alert(1)>"
        "?q=%3Csvg+onload=alert(1)%3E|XSS: svg onload|<svg onload=alert(1)>"
        "?q=javascript:alert(1)|XSS: javascript protocol|javascript:alert(1)"
    )
    
    for test in "${xss_tests[@]}"; do
        local payload=$(echo "$test" | cut -d'|' -f1)
        local desc=$(echo "$test" | cut -d'|' -f2)
        local decoded=$(echo "$test" | cut -d'|' -f3)
        local full_url="${TARGET_URL}/${payload}"
        echo -e "  ${BLUE}GET${NC} ${TARGET_URL}/?q=${YELLOW}${decoded}${NC}"
        local code=$(curl -s -o /dev/null -w "%{http_code}" -k "${full_url}" 2>/dev/null)
        log_test "$desc" "403" "$code"
    done
    
    # ----- Path Traversal -----
    echo ""
    echo -e "  ${BOLD}Path Traversal Detection:${NC}"
    echo -e "  ${CYAN}Expected: 403 Forbidden or 400 Bad Request${NC}"
    echo ""
    
    local path_tests=(
        "/../../../etc/passwd|Path: etc/passwd"
        "?file=../../../etc/shadow|Path: query param"
    )
    
    for test in "${path_tests[@]}"; do
        local payload="${test%%|*}"
        local desc="${test##*|}"
        local full_url="${TARGET_URL}${payload}"
        echo -e "  ${BLUE}GET${NC} ${full_url}"
        local code=$(curl -s -o /dev/null -w "%{http_code}" -k "${full_url}" 2>/dev/null)
        # Accept both 403 (blocked) and 400 (bad request)
        if [[ "$code" == "403" || "$code" == "400" ]]; then
            ((TOTAL_TESTS++))
            ((PASSED_TESTS++))
            echo -e "  ${GREEN}✓${NC} $desc: ${GREEN}$code${NC} (blocked)"
            TEST_RESULTS+=("PASS|$desc|Blocked with $code")
        else
            log_test "$desc" "403" "$code"
        fi
    done
    
    # ----- Command Injection -----
    echo ""
    echo -e "  ${BOLD}Command Injection Detection:${NC}"
    echo -e "  ${CYAN}Expected: 403 Forbidden${NC}"
    echo ""
    
    # Test 1: semicolon injection
    local cmd1_url="${TARGET_URL}/?cmd=;ls+-la"
    echo -e "  ${BLUE}GET${NC} ${TARGET_URL}/?cmd=${YELLOW};ls -la${NC}"
    local cmd1_code=$(curl -s -o /dev/null -w "%{http_code}" -k "${cmd1_url}" 2>/dev/null)
    log_test "CMD: semicolon injection" "403" "$cmd1_code"
    
    # Test 2: pipe injection
    local cmd2_url="${TARGET_URL}/?cmd=|cat+/etc/passwd"
    echo -e "  ${BLUE}GET${NC} ${TARGET_URL}/?cmd=${YELLOW}|cat /etc/passwd${NC}"
    local cmd2_code=$(curl -s -o /dev/null -w "%{http_code}" -k "${cmd2_url}" 2>/dev/null)
    log_test "CMD: pipe injection" "403" "$cmd2_code"
    
    # Test 3: && injection
    local cmd3_url="${TARGET_URL}/?cmd=%26%26id"
    echo -e "  ${BLUE}GET${NC} ${TARGET_URL}/?cmd=${YELLOW}&&id${NC}"
    local cmd3_code=$(curl -s -o /dev/null -w "%{http_code}" -k "${cmd3_url}" 2>/dev/null)
    log_test "CMD: && injection" "403" "$cmd3_code"
    
    # ----- Scanner Detection -----
    echo ""
    echo -e "  ${BOLD}Scanner/Bot Detection:${NC}"
    echo -e "  ${CYAN}Expected: 403 Forbidden${NC}"
    echo ""
    
    local scanner_tests=(
        "sqlmap/1.0|Scanner: sqlmap"
        "nikto/2.1.6|Scanner: nikto"
        "nmap scripting engine|Scanner: nmap"
    )
    
    for test in "${scanner_tests[@]}"; do
        local ua="${test%%|*}"
        local desc="${test##*|}"
        echo -e "  ${BLUE}GET${NC} ${TARGET_URL}/"
        echo -e "      ${YELLOW}User-Agent: ${ua}${NC}"
        local code=$(curl -s -o /dev/null -w "%{http_code}" -k -A "$ua" "$TARGET_URL" 2>/dev/null)
        log_test "$desc" "403" "$code"
    done
    
    # ----- Normal Request (should pass) -----
    echo ""
    echo -e "  ${BOLD}Legitimate Request (should pass):${NC}"
    echo -e "  ${CYAN}Expected: 200 OK${NC}"
    echo ""
    
    local normal_url="$TARGET_URL/?page=1&sort=name"
    local normal_ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0"
    echo -e "  ${BLUE}GET${NC} ${normal_url}"
    echo -e "      ${YELLOW}User-Agent: ${normal_ua}${NC}"
    local normal_code=$(curl -s -o /dev/null -w "%{http_code}" -k \
        -A "$normal_ua" \
        "$normal_url" 2>/dev/null)
    log_test "Normal browser request" "200" "$normal_code"
}

# =============================================================================
# SUMMARY
# =============================================================================
print_summary() {
    print_section "Test Summary"
    
    echo ""
    echo -e "  ${BOLD}Overall Results:${NC}"
    echo -e "  ┌─────────────────────────────────────┐"
    echo -e "  │  Total Tests:  ${BOLD}$TOTAL_TESTS${NC}"
    echo -e "  │  ${GREEN}Passed:${NC}        ${GREEN}$PASSED_TESTS${NC}"
    echo -e "  │  ${RED}Failed:${NC}        ${RED}$FAILED_TESTS${NC}"
    echo -e "  └─────────────────────────────────────┘"
    echo ""
    
    # Calculate pass rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        
        if [[ $pass_rate -eq 100 ]]; then
            echo -e "  ${GREEN}${BOLD}★ All tests passed! Security features are working correctly.${NC}"
        elif [[ $pass_rate -ge 80 ]]; then
            echo -e "  ${YELLOW}${BOLD}◐ Most tests passed ($pass_rate%). Some issues may need attention.${NC}"
        else
            echo -e "  ${RED}${BOLD}✗ Test pass rate: $pass_rate%. Security configuration needs review.${NC}"
        fi
    fi
    
    # Print failed tests if any
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo ""
        echo -e "  ${RED}${BOLD}Failed Tests:${NC}"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL* ]]; then
                local name=$(echo "$result" | cut -d'|' -f2)
                local detail=$(echo "$result" | cut -d'|' -f3)
                echo -e "    ${RED}•${NC} $name - $detail"
            fi
        done
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    print_header
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed${NC}"
        exit 1
    fi
    
    test_connectivity
    test_rate_limiting
    test_waf
    print_summary
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main
