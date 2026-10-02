#!/bin/bash
# ============================================================
# deploy.sh — post-pull deploy script. Runs ON THE SERVER,
# from the app checkout root.
#
# Usage:
#   ./deploy.sh           # run all checks + deploy
#   ./deploy.sh --check   # checks only, no deploy
#
# Overridable via env:
#   COMPOSER_CONTAINER    name of the Docker container that has composer
#                         (leave empty to use host PHP/composer)
#   HEALTH_URL            health-check URL to probe after deploy
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ERRORS=0
CHECK_ONLY=false
[ "$1" = "--check" ] && CHECK_ONLY=true

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

echo "============================================="
echo "  Deploy Script"
echo "  Host: $(hostname)"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="

# ----- 1. PHP lint -----
echo "--- 1. PHP Syntax Check ---"
LINT_OK=true
while IFS= read -r -d '' file; do
    if ! php -l "$file" 2>&1 | grep -q "No syntax errors"; then
        fail "Syntax error in: $file"
        LINT_OK=false
    fi
done < <(find . -name "*.php" -not -path "./vendor/*" -not -path "./runtime/*" -not -path "./tests/_output/*" 2>/dev/null)
$LINT_OK && ok "All PHP files valid"

# ----- 2. Composer install -----
echo "--- 2. Composer Install ---"
if [ "$CHECK_ONLY" = false ]; then
    if [ -n "${COMPOSER_CONTAINER:-}" ] && command -v docker >/dev/null; then
        info "docker exec $COMPOSER_CONTAINER composer install --no-dev --optimize-autoloader --no-interaction"
        docker exec "$COMPOSER_CONTAINER" composer install --no-dev --optimize-autoloader --no-interaction || fail "composer install failed"
    elif command -v composer >/dev/null; then
        info "composer install --no-dev --optimize-autoloader --no-interaction"
        composer install --no-dev --optimize-autoloader --no-interaction || fail "composer install failed"
    else
        warn "composer not found (set COMPOSER_CONTAINER or install composer)"
    fi
else
    echo "--- 2. Composer Install (SKIPPED - check mode) ---"
fi

# ----- 3. Migrations -----
echo "--- 3. Migrations ---"
if [ "$CHECK_ONLY" = false ]; then
    info "php yii migrate --interactive=0"
    php yii migrate --interactive=0 || fail "migrations failed"
else
    php yii migrate/history --interactive=0 || warn "could not check migrations"
fi

# ----- 4. Clear cache -----
echo "--- 4. Clear Cache ---"
if [ "$CHECK_ONLY" = false ]; then
    rm -rf runtime/cache/* 2>/dev/null || true
    rm -rf runtime/HTML/* 2>/dev/null || true
    rm -rf web/assets/* 2>/dev/null || true
    ok "cache cleared"
else
    echo "--- 4. Clear Cache (SKIPPED - check mode) ---"
fi

# ----- 5. Health check -----
echo "--- 5. Health Check ---"
if [ -n "${HEALTH_URL:-}" ] && command -v curl >/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        ok "Health check: $HEALTH_URL returned 200"
    else
        warn "Health check: $HEALTH_URL returned $HTTP_CODE"
    fi
else
    warn "HEALTH_URL not set (or curl missing); skipping health check"
fi

# ----- 6. PHPStan (optional) -----
echo "--- 6. PHPStan (Static Analysis) ---"
if [ -f "./vendor/bin/phpstan" ]; then
    if ./vendor/bin/phpstan analyse --no-interaction --memory-limit=512M; then
        ok "PHPStan: no errors"
    else
        warn "PHPStan found issues (review, deploy continues)"
    fi
else
    warn "PHPStan not installed"
fi

echo "============================================="
$CHECK_ONLY && echo -e "${CYAN}CHECK MODE - nothing was deployed.${NC}"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}Deploy successful!${NC}"
else
    echo -e "${RED}Deploy finished with $ERRORS error(s).${NC}"
fi
echo "============================================="
exit $ERRORS
