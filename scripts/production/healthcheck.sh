#!/bin/bash
# CrystalCog Production Health Check Script

set -e

# Configuration
API_HOST="${API_HOST:-localhost}"
API_PORT="${GALATEA_PORT:-8080}"
TIMEOUT=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}[$(date +'%Y-%m-%d %H:%M:%S')] $2${NC}"
}

# Check if a port is responding
check_port() {
    local host=$1
    local port=$2
    local service=$3
    
    if timeout $TIMEOUT bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        log "$GREEN" "✓ $service ($host:$port) is responding"
        return 0
    else
        log "$RED" "✗ $service ($host:$port) is not responding"
        return 1
    fi
}

# Check HTTP endpoint
check_http() {
    local url=$1
    local service=$2
    
    if curl -s -f --max-time $TIMEOUT "$url" >/dev/null 2>&1; then
        log "$GREEN" "✓ $service ($url) is healthy"
        return 0
    else
        log "$RED" "✗ $service ($url) is not healthy"
        return 1
    fi
}

# Check process is running
check_process() {
    local process_name=$1
    
    if pgrep -f "$process_name" >/dev/null 2>&1; then
        log "$GREEN" "✓ Process '$process_name' is running"
        return 0
    else
        log "$RED" "✗ Process '$process_name' is not running"
        return 1
    fi
}

# Check disk space
check_disk_space() {
    local threshold=90
    local mount_point="/app"
    
    # Fall back to root filesystem if /app doesn't exist
    if [ ! -d "$mount_point" ]; then
        mount_point="/"
        log "$YELLOW" "⚠ /app directory not found, checking root filesystem instead"
    fi
    
    local usage=$(df "$mount_point" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    
    # Check if usage is a valid number
    if ! [[ "$usage" =~ ^[0-9]+$ ]]; then
        log "$RED" "✗ Could not determine disk space usage for $mount_point"
        return 1
    fi
    
    if [ "$usage" -lt "$threshold" ]; then
        log "$GREEN" "✓ Disk space usage: ${usage}% (< ${threshold}%) on $mount_point"
        return 0
    else
        log "$RED" "✗ Disk space usage: ${usage}% (>= ${threshold}%) on $mount_point"
        return 1
    fi
}

# Check memory usage
check_memory() {
    local threshold=90
    local usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    
    if [ "$usage" -lt "$threshold" ]; then
        log "$GREEN" "✓ Memory usage: ${usage}% (< ${threshold}%)"
        return 0
    else
        log "$YELLOW" "⚠ Memory usage: ${usage}% (>= ${threshold}%)"
        return 0  # Warning but not failure
    fi
}

# Main health check
main() {
    log "$YELLOW" "Starting CrystalCog health check..."
    
    local exit_code=0
    
    # Check core services
    check_port "$API_HOST" "$API_PORT" "API Service" || exit_code=1
    
    # Check HTTP endpoints
    check_http "http://$API_HOST:$API_PORT/api/health" "Galatea Health Endpoint" || exit_code=1
    
    # Check critical processes
    check_process "crystalcog" || exit_code=1
    
    # Check system resources
    check_disk_space || exit_code=1
    check_memory || exit_code=1
    
    if [ $exit_code -eq 0 ]; then
        log "$GREEN" "All health checks passed!"
    else
        log "$RED" "Some health checks failed!"
    fi
    
    exit $exit_code
}

# Run health check (only if not being sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi