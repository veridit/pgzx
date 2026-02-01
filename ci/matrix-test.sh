#!/usr/bin/env bash
# Matrix test script for testing pgzx against multiple PostgreSQL versions
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PRJ_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PG_VERSIONS="${1:-16 17 18}"

echo "=========================================="
echo "PGZX Matrix Test"
echo "Testing PostgreSQL versions: $PG_VERSIONS"
echo "=========================================="

FAILED_VERSIONS=""
PASSED_VERSIONS=""

for version in $PG_VERSIONS; do
	echo ""
	echo -e "${YELLOW}=========================================="
	echo "Testing PostgreSQL $version"
	echo -e "==========================================${NC}"

	# Clean up previous test artifacts
	rm -rf .zig-cache
	rm -rf out/default

	# Kill any existing postgres on port 5432
	pkill -f "postgres.*-D.*var/postgres" 2>/dev/null || true
	# Also try killing by port binding
	lsof -ti:5432 | xargs kill -9 2>/dev/null || true
	sleep 2

	# Run tests in the version-specific nix shell
	# shellcheck disable=SC2016
	if nix develop ".#pg$version" --command bash -c '
		set -e
		echo "PostgreSQL version: $(pg_config --version)"
		echo "Zig version: $(zig version)"

		# Ensure no postgres is running
		pgstop 2>/dev/null || true

		# Setup local postgres
		pglocal

		# Initialize database
		rm -rf $PG_HOME/var/postgres/data 2>/dev/null || true
		pginit

		# Start postgres
		pgstart

		# Build and run unit tests
		zig build -p $PG_HOME unit

		# Stop postgres
		pgstop

		echo "Tests passed for PostgreSQL $(pg_config --version)"
	' 2>&1; then
		echo -e "${GREEN}✓ PostgreSQL $version tests PASSED${NC}"
		PASSED_VERSIONS="$PASSED_VERSIONS $version"
	else
		echo -e "${RED}✗ PostgreSQL $version tests FAILED${NC}"
		FAILED_VERSIONS="$FAILED_VERSIONS $version"
	fi
done

echo ""
echo "=========================================="
echo "Matrix Test Summary"
echo "=========================================="
if [ -n "$PASSED_VERSIONS" ]; then
	echo -e "${GREEN}Passed:$PASSED_VERSIONS${NC}"
fi
if [ -n "$FAILED_VERSIONS" ]; then
	echo -e "${RED}Failed:$FAILED_VERSIONS${NC}"
	exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"
