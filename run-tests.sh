#!/bin/bash
set -e

echo "🧪 MoleUI Test Runner"
echo "===================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
RUN_UNIT=true
RUN_UI=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ui)
            RUN_UI=true
            shift
            ;;
        --unit-only)
            RUN_UI=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: ./run-tests.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --ui          Run UI tests (requires GUI)"
            echo "  --unit-only   Run only unit tests (default)"
            echo "  --verbose     Show detailed output"
            echo "  --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ xcodebuild not found. Please install Xcode.${NC}"
    exit 1
fi

echo "📋 Test Configuration:"
echo "  - Unit Tests: $RUN_UNIT"
echo "  - UI Tests: $RUN_UI"
echo "  - Verbose: $VERBOSE"
echo ""

# Clean previous test results
rm -rf TestResults.xcresult Coverage.xcresult DerivedData

# Run unit tests
if [ "$RUN_UNIT" = true ]; then
    echo "🔬 Running Unit Tests..."
    echo "------------------------"
    
    if [ "$VERBOSE" = true ]; then
        xcodebuild test \
            -scheme MoleUI \
            -configuration Debug \
            -destination 'platform=macOS' \
            -only-testing:MoleUITests/MoleCoreTests \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            -resultBundlePath TestResults.xcresult
    else
        xcodebuild test \
            -scheme MoleUI \
            -configuration Debug \
            -destination 'platform=macOS' \
            -only-testing:MoleUITests/MoleCoreTests \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            -resultBundlePath TestResults.xcresult 2>&1 | grep -E "Test Suite|Test Case|passed|failed|error"
    fi
    
    UNIT_EXIT_CODE=$?
    
    if [ $UNIT_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Unit tests passed${NC}"
    else
        echo -e "${RED}❌ Unit tests failed${NC}"
    fi
    echo ""
fi

# Run UI tests
if [ "$RUN_UI" = true ]; then
    echo "🖥️  Running UI Tests..."
    echo "----------------------"
    echo -e "${YELLOW}⚠️  UI tests require GUI access and may take longer${NC}"
    echo ""
    
    if [ "$VERBOSE" = true ]; then
        xcodebuild test \
            -scheme MoleUI \
            -configuration Debug \
            -destination 'platform=macOS' \
            -only-testing:MoleUITests/UIFlowTests \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO
    else
        xcodebuild test \
            -scheme MoleUI \
            -configuration Debug \
            -destination 'platform=macOS' \
            -only-testing:MoleUITests/UIFlowTests \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Test Suite|Test Case|passed|failed|error"
    fi
    
    UI_EXIT_CODE=$?
    
    if [ $UI_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ UI tests passed${NC}"
    else
        echo -e "${YELLOW}⚠️  UI tests failed (this is expected in headless environments)${NC}"
    fi
    echo ""
fi

# Generate test report
if [ -d "TestResults.xcresult" ]; then
    echo "📊 Generating Test Report..."
    echo "----------------------------"
    
    # Extract test summary
    xcrun xcresulttool get object --legacy --format json --path TestResults.xcresult > test-results.json
    
    # Count tests
    TOTAL_TESTS=$(xcrun xcresulttool get --path TestResults.xcresult | grep -c "Test Case" || echo "0")
    
    echo "Total tests run: $TOTAL_TESTS"
    echo "Results saved to: TestResults.xcresult"
    echo ""
fi

# Summary
echo "📝 Test Summary"
echo "==============="

if [ "$RUN_UNIT" = true ]; then
    if [ $UNIT_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Unit Tests: PASSED${NC}"
    else
        echo -e "${RED}❌ Unit Tests: FAILED${NC}"
    fi
fi

if [ "$RUN_UI" = true ]; then
    if [ $UI_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ UI Tests: PASSED${NC}"
    else
        echo -e "${YELLOW}⚠️  UI Tests: FAILED${NC}"
    fi
fi

echo ""
echo "💡 Tips:"
echo "  - View detailed results: open TestResults.xcresult"
echo "  - Run with --verbose for full output"
echo "  - Run with --ui to include UI tests"
echo ""

# Exit with appropriate code
if [ "$RUN_UNIT" = true ] && [ $UNIT_EXIT_CODE -ne 0 ]; then
    exit 1
fi

exit 0
