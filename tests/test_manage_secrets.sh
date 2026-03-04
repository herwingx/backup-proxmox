#!/bin/bash

# Simple testing framework
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
FAILURES=0

assert_true() {
    if ! "$@"; then
        echo -e "${RED}✗ FAIL: ${*} did not return true${NC}"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "${GREEN}✓ PASS: ${*}${NC}"
    fi
}

assert_file_exists() {
    if [ ! -f "$1" ]; then
        echo -e "${RED}✗ FAIL: File $1 does not exist${NC}"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "${GREEN}✓ PASS: File $1 exists${NC}"
    fi
}

assert_file_not_exists() {
    if [ -f "$1" ]; then
        echo -e "${RED}✗ FAIL: File $1 exists but should not${NC}"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "${GREEN}✓ PASS: File $1 does not exist${NC}"
    fi
}

assert_output_contains() {
    local output="$1"
    local expected="$2"
    if [[ ! "$output" == *"$expected"* ]]; then
        echo -e "${RED}✗ FAIL: Output did not contain '$expected'${NC}"
        echo "Output was: $output"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "${GREEN}✓ PASS: Output contained '$expected'${NC}"
    fi
}

# Ensure tests are run from repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- TESTS ---

test_encrypt_secrets_keeps_original() {
    echo "--- test_encrypt_secrets_keeps_original ---"
    local test_dir=$(mktemp -d)

    cat << MOCK > "$test_dir/wrapper.sh"
#!/bin/bash
source "$REPO_ROOT/scripts/manage_secrets.sh"
SECRET_FILE="\$1"
ENCRYPTED_FILE="\$2"

# Mock age command
age() {
    touch "\$3"
}
export -f age

# override command -v for age mock
_command() {
    if [[ "\$1" == "-v" && "\$2" == "age" ]]; then
        echo "mocked-age"
        return 0
    fi
    command "\$@"
}
alias command=_command
shopt -s expand_aliases

encrypt_secrets
MOCK
    chmod +x "$test_dir/wrapper.sh"

    local sec_file="$test_dir/.env"
    local enc_file="$test_dir/.env.age"

    # Create the secret file
    echo "secret=123" > "$sec_file"

    # Run the function, answer 'n' to "Delete original file?"
    output=$(echo "n" | "$test_dir/wrapper.sh" "$sec_file" "$enc_file" 2>&1)

    assert_file_exists "$enc_file"
    assert_file_exists "$sec_file"
    assert_output_contains "$output" "Archivo encriptado:"

    rm -rf "$test_dir"
}

test_encrypt_secrets_deletes_original() {
    echo "--- test_encrypt_secrets_deletes_original ---"
    local test_dir=$(mktemp -d)

    cat << MOCK > "$test_dir/wrapper.sh"
#!/bin/bash
source "$REPO_ROOT/scripts/manage_secrets.sh"
SECRET_FILE="\$1"
ENCRYPTED_FILE="\$2"

# Mock age command
age() {
    # Extract output file correctly, considering args
    local outfile=""
    while [[ \$# -gt 0 ]]; do
        case "\$1" in
            -o) outfile="\$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    if [ -n "\$outfile" ]; then
        touch "\$outfile"
    fi
}
export -f age

# override command -v for age mock
_command() {
    if [[ "\$1" == "-v" && "\$2" == "age" ]]; then
        echo "mocked-age"
        return 0
    fi
    command "\$@"
}
alias command=_command
shopt -s expand_aliases

# Mock read to return 's'
read() {
    REPLY="s"
}
export -f read

encrypt_secrets
MOCK
    chmod +x "$test_dir/wrapper.sh"

    local sec_file="$test_dir/.env"
    local enc_file="$test_dir/.env.age"

    # Create the secret file
    echo "secret=123" > "$sec_file"

    # Run the function
    output=$("$test_dir/wrapper.sh" "$sec_file" "$enc_file" 2>&1)

    assert_file_exists "$enc_file"
    assert_file_not_exists "$sec_file"
    assert_output_contains "$output" "Archivo original eliminado"

    rm -rf "$test_dir"
}

test_encrypt_secrets_missing_file() {
    echo "--- test_encrypt_secrets_missing_file ---"
    local test_dir=$(mktemp -d)

    cat << MOCK > "$test_dir/wrapper.sh"
#!/bin/bash
source "$REPO_ROOT/scripts/manage_secrets.sh"
SECRET_FILE="\$1"
ENCRYPTED_FILE="\$2"

# Mock age command
age() {
    touch "\$3"
}
export -f age

# override command -v for age mock
_command() {
    if [[ "\$1" == "-v" && "\$2" == "age" ]]; then
        echo "mocked-age"
        return 0
    fi
    command "\$@"
}
alias command=_command
shopt -s expand_aliases

# Disable exit on error for the mock test to capture log_error
set +e
encrypt_secrets
MOCK
    chmod +x "$test_dir/wrapper.sh"

    local sec_file="$test_dir/.env"
    local enc_file="$test_dir/.env.age"

    # Run the function, it should fail
    output=$( "$test_dir/wrapper.sh" "$sec_file" "$enc_file" 2>&1 || true )

    assert_file_not_exists "$enc_file"
    assert_output_contains "$output" "No existe"

    rm -rf "$test_dir"
}

# Run tests
test_encrypt_secrets_keeps_original
test_encrypt_secrets_deletes_original
test_encrypt_secrets_missing_file

if [ "$FAILURES" -gt 0 ]; then
    echo -e "\n${RED}$FAILURES test(s) failed.${NC}"
else
    echo -e "\n${GREEN}All tests passed successfully.${NC}"
fi

# Exit with failure code if any tests failed
if [ "$FAILURES" -gt 0 ]; then
    false
fi
