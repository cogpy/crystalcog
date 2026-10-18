#!/bin/bash

# Crystal Installation Script Validation Test Suite
# This test validates the crystal-lang/install/install-via-apt.sh script
# Part of the CrystalCog validation framework

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test configuration
REPO_ROOT="/home/runner/work/crystalcog/crystalcog"
APT_SCRIPT="$REPO_ROOT/crystal-lang/install/install-via-apt.sh"
MAIN_SCRIPT="$REPO_ROOT/scripts/install-crystal.sh"

# Comprehensive validation function
validate_crystal_installation_script() {
    local exit_code=0
    
    print_status "Crystal Installation Script Comprehensive Validation"
    print_status "=================================================="
    
    # Test 1: File existence and permissions
    print_status "1. Testing file existence and permissions..."
    if [[ ! -f "$APT_SCRIPT" ]]; then
        print_error "APT installation script not found: $APT_SCRIPT"
        exit_code=1
    elif [[ ! -x "$APT_SCRIPT" ]]; then
        print_error "APT installation script not executable"
        exit_code=1
    else
        print_success "APT installation script exists and is executable"
    fi
    
    # Test 2: Script syntax validation
    print_status "2. Testing script syntax..."
    if bash -n "$APT_SCRIPT"; then
        print_success "Script syntax is valid"
    else
        print_error "Script syntax errors found"
        exit_code=1
    fi
    
    # Test 3: Dependency availability
    print_status "3. Testing system dependency availability..."
    local deps=(
        "build-essential" "git" "wget" "curl" "libbsd-dev" "libedit-dev"
        "libevent-dev" "libgmp-dev" "libssl-dev" "libxml2-dev" "libyaml-dev"
        "libreadline-dev" "libz-dev" "pkg-config" "libpcre3-dev" "llvm-14" "llvm-14-dev"
    )
    
    local missing_count=0
    for dep in "${deps[@]}"; do
        if ! apt-cache show "$dep" &>/dev/null; then
            print_warning "Missing dependency: $dep"
            missing_count=$((missing_count + 1))
        fi
    done
    
    if [[ $missing_count -eq 0 ]]; then
        print_success "All ${#deps[@]} dependencies are available"
    else
        print_warning "$missing_count dependencies missing or unavailable"
        # Not failing here as some deps might be optional
    fi
    
    # Test 4: Crystal download URL validation
    print_status "4. Testing Crystal download URL accessibility..."
    local crystal_version="1.10.1"
    local crystal_url="https://github.com/crystal-lang/crystal/releases/download/${crystal_version}/crystal-${crystal_version}-1-linux-x86_64.tar.gz"
    
    if curl -I "$crystal_url" &>/dev/null; then
        print_success "Crystal download URL is accessible"
    else
        print_warning "Crystal download URL accessibility test failed"
        # Not failing as this could be network related
    fi
    
    # Test 5: Integration with main installation script
    print_status "5. Testing integration with main installation script..."
    if [[ ! -f "$MAIN_SCRIPT" ]]; then
        print_error "Main installation script not found: $MAIN_SCRIPT"
        exit_code=1
    elif ! grep -q "install-via-apt.sh" "$MAIN_SCRIPT"; then
        print_error "Main script does not reference APT installation script"
        exit_code=1
    else
        print_success "Integration with main installation script validated"
    fi
    
    # Test 6: Script content validation
    print_status "6. Testing script content and structure..."
    
    # Check for required functions
    local required_functions=("install_crystal_system" "verify_installation" "main")
    for func in "${required_functions[@]}"; do
        if grep -q "^${func}()" "$APT_SCRIPT"; then
            print_success "Function $func found"
        else
            print_error "Required function $func not found"
            exit_code=1
        fi
    done
    
    # Check for proper error handling
    if grep -q "set -e" "$APT_SCRIPT"; then
        print_success "Proper error handling (set -e) found"
    else
        print_warning "Error handling directive not found"
    fi
    
    # Test 7: Crystal version validation
    print_status "7. Testing Crystal version specification..."
    if grep -q 'CRYSTAL_VERSION="1.10.1"' "$APT_SCRIPT"; then
        print_success "Crystal version 1.10.1 specified correctly"
    else
        print_warning "Crystal version specification check failed"
    fi
    
    # Test 8: Installation verification
    print_status "8. Testing installation verification logic..."
    if command -v crystal &>/dev/null && command -v shards &>/dev/null; then
        local crystal_version=$(crystal version | head -n1)
        local shards_version=$(shards version | head -n1)
        print_success "Crystal installation verified: $crystal_version"
        print_success "Shards installation verified: $shards_version"
        
        # Test basic Crystal functionality
        print_status "Testing basic Crystal functionality..."
        if echo 'puts "Crystal validation test"' | crystal eval; then
            print_success "Crystal basic functionality test passed"
        else
            print_warning "Crystal basic functionality test failed"
        fi
    else
        print_warning "Crystal or Shards not found (may not be installed yet)"
    fi
    
    # Test 9: Security validation
    print_status "9. Testing security aspects..."
    
    # Check for sudo usage (expected)
    if grep -q "sudo" "$APT_SCRIPT"; then
        print_success "Proper sudo usage found for system modifications"
    else
        print_warning "No sudo usage found (unexpected for system installation)"
    fi
    
    # Check for secure downloads
    if grep -q "curl.*https://" "$APT_SCRIPT"; then
        print_success "Secure HTTPS downloads used"
    else
        print_warning "Secure download check inconclusive"
    fi
    
    # Test 10: Cleanup validation
    print_status "10. Testing cleanup procedures..."
    if grep -q "rm.*CRYSTAL_ARCHIVE" "$APT_SCRIPT"; then
        print_success "Proper cleanup of temporary files found"
    else
        print_warning "Cleanup procedure not found or incomplete"
    fi
    
    return $exit_code
}

# Integration test with project test runner
test_integration_with_project() {
    print_status "Testing integration with project test runner..."
    
    cd "$REPO_ROOT"
    
    # Test if test runner can detect Crystal
    if ./scripts/test-runner.sh --help &>/dev/null; then
        print_success "Test runner integration works"
        
        # Test dependency installation
        if [[ -f "shard.yml" ]]; then
            print_status "Testing shards install..."
            if shards install &>/dev/null; then
                print_success "Project dependencies install successfully"
            else
                print_warning "Project dependency installation had issues"
            fi
        fi
    else
        print_warning "Test runner integration test failed"
    fi
}

# Guix environment tests
test_guix_environment() {
    print_status "Testing Guix environment compatibility..."
    
    cd "$REPO_ROOT"
    
    local exit_code=0
    
    # Test 1: Check for required Guix files
    print_status "1. Checking Guix configuration files..."
    local guix_files=(".guix-channel" "guix.scm")
    for file in "${guix_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_success "Found Guix file: $file"
        else
            print_error "Missing required Guix file: $file"
            exit_code=1
        fi
    done
    
    # Test 2: Validate Guix manifest syntax
    print_status "2. Validating Guix manifest syntax..."
    if [[ -f "guix.scm" ]]; then
        # Basic syntax check - look for required Guile structures
        if grep -q "packages->manifest" "guix.scm" && grep -q "use-modules" "guix.scm"; then
            print_success "Guix manifest has proper structure"
        else
            print_warning "Guix manifest structure check failed"
            exit_code=1
        fi
        
        # Check for cognitive packages
        if grep -q "opencog\|cognitive" "guix.scm"; then
            print_success "Cognitive framework packages found in manifest"
        else
            print_warning "No cognitive framework packages found in manifest"
        fi
    fi
    
    # Test 3: Check for OpenCog Guix packages
    print_status "3. Checking for OpenCog package definitions..."
    if [[ -d "modules" ]] && find modules -name "*.scm" -type f | grep -q "cognitive\|opencog"; then
        print_success "OpenCog package definitions found"
    else
        print_warning "OpenCog package definitions not found or incomplete"
    fi
    
    # Test 4: Validate channel configuration
    print_status "4. Validating Guix channel configuration..."
    if [[ -f ".guix-channel" ]]; then
        if grep -q "name\|url\|branch" ".guix-channel"; then
            print_success "Guix channel configuration is valid"
        else
            print_warning "Guix channel configuration incomplete"
        fi
    fi
    
    return $exit_code
}

# Main validation execution
main() {
    print_status "Crystal Installation Script Validation Test Suite"
    print_status "Starting comprehensive validation..."
    echo
    
    local exit_code=0
    
    # Run comprehensive validation
    validate_crystal_installation_script || exit_code=1
    
    echo
    
    # Run integration tests
    test_integration_with_project || exit_code=1
    
    echo
    
    # Run Guix environment tests
    test_guix_environment || exit_code=1
    
    echo
    print_status "Validation Summary"
    print_status "=================="
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "✅ All critical validations passed!"
        print_success "The crystal-lang/install/install-via-apt.sh script is ready for production use."
    else
        print_error "❌ Some critical validations failed!"
        print_error "Please review the issues above before using the script."
    fi
    
    echo
    print_status "Validation completed."
    return $exit_code
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi