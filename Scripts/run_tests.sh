#!/bin/bash

# CentralDSM Test Runner
# This script helps run various tests including TSan and Valgrind

set -e

BUILDDIR="build"
TESTDIR="$BUILDDIR/tests"

print_usage() {
    echo "Usage: $0 [test-type] [test-name]"
    echo ""
    echo "Test types:"
    echo "  normal         - Run normal build test"
    echo "  tsan           - Run ThreadSanitizer test"
    echo "  valgrind       - Run Valgrind memory check"
    echo "  all-tsan       - Run all tests with TSan"
    echo "  all-valgrind   - Run all tests with Valgrind"
    echo ""
    echo "Test names:"
    echo "  test1          - test_dsm_init_master"
    echo "  test2          - test_dsm_init_slave"
    echo "  test3          - test_dsm_lock_write"
    echo "  test4          - test_dsm_lock_read"
    echo "  test5          - test_dsm_lock_read2"
    echo "  demo1          - demo_master_writer"
    echo "  demo2          - demo_slave_writer_reader"
    echo "  demo3          - demo_slave_reader"
    echo ""
    echo "Examples:"
    echo "  $0 tsan test1              - Run test1 with TSan"
    echo "  $0 valgrind demo1          - Run demo1 with Valgrind"
    echo "  $0 all-tsan                - Run all tests with TSan"
    echo "  $0 normal test3            - Run test3 normally"
}

# Map test names to actual executable names
get_test_executable() {
    case $1 in
        test1) echo "test_dsm_init_master" ;;
        test2) echo "test_dsm_init_slave" ;;
        test3) echo "test_dsm_lock_write" ;;
        test4) echo "test_dsm_lock_read" ;;
        test5) echo "test_dsm_lock_read2" ;;
        demo1) echo "demo_master_writer" ;;
        demo2) echo "demo_slave_writer_reader" ;;
        demo3) echo "demo_slave_reader" ;;
        *) echo "" ;;
    esac
}

run_normal_test() {
    local test_name=$1
    local exe=$(get_test_executable "$test_name")

    if [ -z "$exe" ]; then
        echo "Error: Unknown test name: $test_name"
        exit 1
    fi

    echo "Running $exe (normal build)..."
    "$TESTDIR/$exe"
}

run_tsan_test() {
    local test_name=$1
    local exe=$(get_test_executable "$test_name")

    if [ -z "$exe" ]; then
        echo "Error: Unknown test name: $test_name"
        exit 1
    fi

    echo "Running $exe with ThreadSanitizer..."
    TSAN_OPTIONS="log_path=$BUILDDIR/tsan-${exe}.log" "$TESTDIR/${exe}_tsan"

    echo ""
    echo "TSan output saved to: $BUILDDIR/tsan-${exe}.log.*"
}

run_valgrind_test() {
    local test_name=$1
    local exe=$(get_test_executable "$test_name")

    if [ -z "$exe" ]; then
        echo "Error: Unknown test name: $test_name"
        exit 1
    fi

    echo "Running $exe with Valgrind..."
    valgrind --leak-check=full \
             --show-leak-kinds=all \
             --track-origins=yes \
             --verbose \
             --log-file="$BUILDDIR/valgrind-${exe}.log" \
             "$TESTDIR/$exe"

    echo ""
    echo "Valgrind output saved to: $BUILDDIR/valgrind-${exe}.log"
    echo ""
    echo "Summary from Valgrind:"
    grep -A 5 "LEAK SUMMARY" "$BUILDDIR/valgrind-${exe}.log" || true
    grep "ERROR SUMMARY" "$BUILDDIR/valgrind-${exe}.log" || true
}

run_all_tsan() {
    echo "Running all tests with ThreadSanitizer..."
    echo "========================================="

    for test in test1 test2 test3 test4 test5 demo1 demo2 demo3; do
        echo ""
        echo "--- Running $test with TSan ---"
        run_tsan_test "$test" || echo "Test $test failed or needs setup"
        echo ""
    done

    echo "========================================="
    echo "All TSan tests completed. Check $BUILDDIR/tsan-*.log.* for details"
}

run_all_valgrind() {
    echo "Running all tests with Valgrind..."
    echo "===================================="

    for test in test1 test2 test3 test4 test5 demo1 demo2 demo3; do
        echo ""
        echo "--- Running $test with Valgrind ---"
        run_valgrind_test "$test" || echo "Test $test failed or needs setup"
        echo ""
    done

    echo "===================================="
    echo "All Valgrind tests completed. Check $BUILDDIR/valgrind-*.log for details"
}

# Main script logic
if [ $# -eq 0 ]; then
    print_usage
    exit 1
fi

case $1 in
    normal)
        if [ -z "$2" ]; then
            echo "Error: Please specify a test name"
            print_usage
            exit 1
        fi
        run_normal_test "$2"
        ;;
    tsan)
        if [ -z "$2" ]; then
            echo "Error: Please specify a test name"
            print_usage
            exit 1
        fi
        run_tsan_test "$2"
        ;;
    valgrind)
        if [ -z "$2" ]; then
            echo "Error: Please specify a test name"
            print_usage
            exit 1
        fi
        run_valgrind_test "$2"
        ;;
    all-tsan)
        run_all_tsan
        ;;
    all-valgrind)
        run_all_valgrind
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        echo "Error: Unknown test type: $1"
        print_usage
        exit 1
        ;;
esac
