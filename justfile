truthy_regex := '(?i)^(?:yes|1|true)$'

# List all available commands by default
default:
    @just --choose --justfile {{justfile()}}

# Recursively format all Nim files in a specific directory
format directory="src":
    #!/usr/bin/env bash
    find "{{directory}}" -type f -name "*.nim" -print0 | while IFS= read -r -d '' file; do
        echo "Formatting $file..."
        nph "$file"
    done

# Generate test coverage
coverage:
    #!/usr/bin/env bash
    set -euo pipefail

    FILEINFO="lcov.info"
    LCOV_ARGS="--rc branch_coverage=1 --ignore-errors inconsistent --ignore-errors range --ignore-errors unused"
    GENERATED_FILE="generated_not_to_break_here"
    NIMCACHE_DIR="nimcache"
    CURRENT_DIR=$(pwd)

    # Create nimcache/tests directory if it doesn't exist
    mkdir -p "${NIMCACHE_DIR}/tests"

    # Find and process test files
    find ./tests -name 'test_*.nim' | head -n 2 | while read -r file; do
        echo "Processing file: $file"
        filename=$(basename "$file")
        filename_no_ext="${filename%.nim}"

        # Compile test with coverage
        nim c \
            --nimcache:"${NIMCACHE_DIR}" \
            --hints:off \
            --debugger:native \
            --passC:--coverage \
            --passL:--coverage \
            -o:"${NIMCACHE_DIR}/tests/${filename_no_ext}" \
            "$file"

        # Run the compiled test
        "${NIMCACHE_DIR}/tests/${filename_no_ext}"
    done

    # Generate coverage data
    touch "${GENERATED_FILE}"
    lcov ${LCOV_ARGS} --capture --directory "${NIMCACHE_DIR}" --output-file "${FILEINFO}"
    rm "${GENERATED_FILE}"

    # Clean up coverage data
    lcov ${LCOV_ARGS} --extract "${FILEINFO}" "${CURRENT_DIR}/src/*" -o "${FILEINFO}"
    lcov ${LCOV_ARGS} --remove "${FILEINFO}" "${CURRENT_DIR}/tests/*" -o "${FILEINFO}"

    # Generate HTML report
    genhtml --branch-coverage --ignore-errors missing,range,corrupt,inconsistent --legend --output-directory coverage/ "${FILEINFO}"

# Generate test coverage
test isParallel="false" cores="4":
    #!/usr/bin/env bash
    set -euo pipefail

    NIMCACHE_DIR="nimcache"

    # Create nimcache/tests directory if it doesn't exist
    mkdir -p "${NIMCACHE_DIR}/tests"

    # Function to compile and run a single test file
    run_test() {
        local file="$1"
        echo "Processing file: $file"
        filename=$(basename "$file")
        filename_no_ext="${filename%.nim}"

        # Step 1: Compile and run with debug flags
        nim c \
            -d:debug \
            -d:nimDebugDlOpen \
            --verbosity:0 \
            --hints:off \
            --cc:clang \
            --opt:none \
            --debugger:native \
            --passc:-fsanitize=address \
            --passl:-fsanitize=address \
            --stacktrace:on \
            -d:useMalloc \
            --mm:orc \
            --passC:-O0 \
            --passC:-g3 \
            --passC:-ggdb3 \
            --passC:-gdwarf-4 \
            --lineDir:on \
            --debuginfo:on \
            --excessiveStackTrace:on \
            -o:"${NIMCACHE_DIR}/tests/${filename_no_ext}" \
            "$file"

        # Run the compiled test
        "${NIMCACHE_DIR}/tests/${filename_no_ext}"
    }

    export -f run_test
    export NIMCACHE_DIR

    # Find test files
    TEST_FILES=$(find ./tests -name 'test_*.nim' | head)

    if {{isParallel}} =~ truthy_regex; then
        echo "Running tests in parallel..."
        # Run tests in parallel using xargs
        echo "$TEST_FILES" | xargs -n 1 -P {{cores}} -I {} bash -c 'run_test "$@"' _ {}
    else
        echo "Running tests sequentially..."
        # Run tests sequentially
        while read -r file; do
            run_test "$file"
        done <<< "$TEST_FILES"
    fi

# Debug with rr and connect lldb to the specific target
debug-run nim_file="src/duckdb" name="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Extract the base name without extension
    BASENAME=$(basename "{{nim_file}}" .nim)
    DIRNAME=$(dirname "{{nim_file}}")
    OUTPUT_PATH="${DIRNAME}/${BASENAME}"

    # Step 1: Compile and run with debug flags
    nim c \
        -r \
        -d:debug \
        -d:nimDebugDlOpen \
        --cc:clang \
        --opt:none \
        --debugger:native \
        --passc:-fsanitize=address \
        --passl:-fsanitize=address \
        --stacktrace:on \
        -d:useMalloc \
        --mm:orc \
        --passC:-O1 \
        --passC:-ggdb3 \
        --passC:-fno-omit-frame-pointer \
        --passC:-gdwarf-4 \
        --lineDir:on \
        --debuginfo:on \
        --threads:off \
        --excessiveStackTrace:on \
        "{{nim_file}}" \
        "{{name}}"

# Debug with rr and connect lldb to the specific target
debug nim_file="tests/results/test_result_type.nim":
    #!/usr/bin/env bash
    set -euo pipefail

    # Extract the base name without extension
    BASENAME=$(basename "{{nim_file}}" .nim)
    DIRNAME=$(dirname "{{nim_file}}")
    OUTPUT_PATH="${DIRNAME}/${BASENAME}"

    # Step 1: Compile and run with debug flags
    nim c \
        -d:debug \
        -d:nimDebugDlOpen \
        --opt:none \
        --debugger:native \
        --stacktrace:on \
        -d:useMalloc \
        --mm:orc \
        --passC:-O0 \
        --passC:-g3 \
        --passC:-gdwarf-4 \
        --linedir:on \
        --debuginfo:on \
        --threads:off \
        --excessiveStackTrace:on \
        "{{nim_file}}"

    # Step 2: Record using rr
    rr record -M "${OUTPUT_PATH}"

    # Step 3: Start rr replay and connect lldb
    # Start rr in the background
    # rr replay -s 9999 &
    # rr replay -s 9999 --debugger=nim-gdb
    # RR_PID=$!
    ./gf2 --rr-replay

    # Wait a moment for rr to start
    # sleep 2

    # ddd --debugger "nim-gdb -ex 'target remote localhost:9999'" "${OUTPUT_PATH}" &

    # # Create a source map file for lldb
    # PROJECT_ROOT=$(pwd)
    # LLDB_SETTINGS=$(mktemp)
    # echo "settings set target.source-map /proc/self/cwd ${PROJECT_ROOT}" > "$LLDB_SETTINGS"
    # echo "command script import nimlldb.py" >> "$LLDB_SETTINGS"

    # # Launch lldb with enhanced debug settings
    # lldb \
    #     -s "$LLDB_SETTINGS" \
    #     -o "platform select remote-gdb-server" \
    #     -o "target create /home/vlad/.local/share/rr/test_result_type-23/mmap_hardlink_4_test_result_type" \
    #     -o "gdb-remote 127.0.0.1:9999" \
    #     -o "settings set target.inline-breakpoint-strategy always" \
    #     -o "settings set target.skip-prologue false"

    # # Cleanup
    # rm "$LLDB_SETTINGS"
    # kill $RR_PID 2>/dev/null || true

# Run Valgrind on a Nim file to analyze memory usage
valgrind nim_file="tests/results/test_result_type.nim" name="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Extract the base name without extension
    BASENAME=$(basename "{{nim_file}}" .nim)
    DIRNAME=$(dirname "{{nim_file}}")
    OUTPUT_PATH="${DIRNAME}/${BASENAME}"

    # Step 1: Compile with debug flags (without optimization)
    nim c \
        -d:debug \
        -d:nimDebugDlOpen \
        --opt:none \
        --debugger:native \
        --stacktrace:on \
        -d:useMalloc \
        --mm:orc \
        --passC:-O0 \
        --passC:-g3 \
        --passC:-gdwarf-4 \
        --linedir:on \
        --lineDir:on \
        --debuginfo:on \
        --threads:off \
        --excessiveStackTrace:on \
        "{{nim_file}}"

    # Step 2: Run Valgrind with memory analysis options
    valgrind \
        --leak-check=full \
        --show-leak-kinds=definite,possible \
        --track-origins=yes \
        --verbose \
        "${OUTPUT_PATH}"

# Run with maximum performance compiler flags for benchmarking
benchmark name="":
    #!/usr/bin/env bash
    set -euo pipefail

    NIMCACHE_DIR="nimcache"

    # Create nimcache/tests directory if it doesn't exist
    mkdir -p "${NIMCACHE_DIR}/benchmarks"

    # Find and process test files
    find ./benchmarks -name "benchmark_*{{name}}*.nim" | while read -r file; do
        echo "Processing file: $file"
        filename=$(basename "$file")
        filename_no_ext="${filename%.nim}"

        nim c \
            -r \
            -d:release \
            -d:danger \
            --verbosity:0 \
            --hints:off \
            --opt:speed \
            --panics:on \
            --passC:"-flto -march=native -ffast-math -funroll-loops -fopt-info-vec" \
            --passL:"-flto" \
            -o:"${NIMCACHE_DIR}/benchmarks/${filename_no_ext}" \
            "$file"

        # --profiler:on --stacktrace:on --linetrace:on
            # --debugger:native \

        # Run the compiled test
        "${NIMCACHE_DIR}/benchmarks/${filename_no_ext}"
        echo "Running file: $file"
    done

# Generate new duckdb.h wrappers
generate:
    #!/usr/bin/env bash
    set -euo pipefail
    nim c \
        -r \
        -d:useFuthark:true \
        -d:nodeclguards:true \
        -d:exportall:true \
        src/nimdrake.nim

# Build a statically linked version
build-static:
    #!/usr/bin/env bash
    set -euo pipefail
    nim cpp \
        -d:release \
        --passL:"-static" \
        --passL:"-L$(pwd)" \
        --passL:"-l:src/include/libduckdb_bundle.a" \
        --passL:"-lstdc++" \
        src/nimdrake

# --gcc.exe:"musl-gcc" --gcc.linkerexe:"musl-gcc"
