#!/bin/bash
# Architecture Validation Script
# Validates DDD boundaries and cross-context dependencies

echo "🔍 Validating DDD Architecture Boundaries..."
echo "==============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check for forbidden imports
check_forbidden_imports() {
    local context=$1
    local forbidden_pattern=$2
    local description=$3

    echo -e "\n📋 Checking $context context for $description..."

    # Find files in context that import from forbidden contexts
    local violations=$(find lib -name "*.dart" -path "*/$context/*" -exec grep -l "$forbidden_pattern" {} \; 2>/dev/null)

    if [ -n "$violations" ]; then
        echo -e "${RED}❌ VIOLATIONS FOUND in $context:${NC}"
        echo "$violations" | while read -r file; do
            echo -e "  ${YELLOW}⚠️  $file${NC}"
            grep "$forbidden_pattern" "$file" | sed 's/^/    /'
        done
        return 1
    else
        echo -e "${GREEN}✅ No violations found${NC}"
        return 0
    fi
}

# Check each bounded context
ERRORS=0

# Chat context should not import call implementations (only interfaces)
if ! check_forbidden_imports "chat" "from.*call.*infrastructure" "direct call infrastructure imports"; then
    ((ERRORS++))
fi

# Call context should not import chat implementations (only interfaces)
if ! check_forbidden_imports "call" "from.*chat.*infrastructure" "direct chat infrastructure imports"; then
    ((ERRORS++))
fi

# Onboarding should only import from shared and core
if ! check_forbidden_imports "onboarding" "from.*chat.*infrastructure\|from.*call.*infrastructure" "direct infrastructure imports"; then
    ((ERRORS++))
fi

# Check for circular dependencies
echo -e "\n🔄 Checking for circular dependencies..."
if grep -r "import.*\.\./\.\./" lib/ --include="*.dart" > /dev/null; then
    echo -e "${YELLOW}⚠️  Potential circular dependencies detected${NC}"
    grep -r "import.*\.\./\.\./" lib/ --include="*.dart" | head -5
else
    echo -e "${GREEN}✅ No circular dependencies detected${NC}"
fi

# Summary
echo -e "\n==============================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}🎉 Architecture validation PASSED!${NC}"
    echo "All bounded contexts respect DDD boundaries."
else
    echo -e "${RED}💥 Architecture validation FAILED!${NC}"
    echo "Found $ERRORS boundary violations that need to be fixed."
    exit 1
fi

echo -e "\n📊 Dependency Analysis:"
echo "Total Dart files: $(find lib -name "*.dart" | wc -l)"
echo "Barrel files: $(find lib -name "*.dart" -exec grep -l "^export " {} \; | wc -l)"
echo "Bounded contexts: $(ls lib/ | grep -E "^(chat|call|onboarding|core|shared)$" | wc -l)"
