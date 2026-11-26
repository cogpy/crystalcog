# OpenCog Central Monorepo Makefile
# This Makefile provides convenient targets for building and managing the monorepo

# Configuration
BUILD_TYPE ?= Release
RELEASE_FLAGS ?= $(if $(filter Release RelWithDebInfo,$(BUILD_TYPE)),--release,)
JOBS ?= $(shell nproc)
INSTALL_PREFIX ?= /usr/local
BUILD_DIR ?= build
SKIP_TESTS ?= false
SKIP_INSTALL ?= false
CLEAN_BUILD ?= false

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Default target
.PHONY: all
all: build

# Help target
.PHONY: help
help:
	@echo "OpenCog Central Monorepo Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  all              - Build all components (default)"
	@echo "  build            - Build all components"
	@echo "  test             - Run all tests"
	@echo "  install          - Install all components"
	@echo "  clean            - Clean build directory"
	@echo "  setup            - Setup dependencies only"
	@echo "  dev-env          - Setup development environment"
	@echo "  core             - Build core components only"
	@echo "  extended         - Build extended components"
	@echo "  doc              - Generate documentation"
	@echo "  package          - Create package"
	@echo ""
	@echo "Agent-Zero Genesis targets:"
	@echo "  agent-zero       - Build Agent-Zero Genesis system"
	@echo "  agent-zero-setup - Setup Agent-Zero environment only"
	@echo "  agent-zero-test  - Test Agent-Zero components"
	@echo "  agent-zero-demo  - Run Agent-Zero demonstration"
	@echo "  agent-zero-clean - Clean Agent-Zero build artifacts"
	@echo "  agent-zero-image - Generate Agent-Zero system disk image"
	@echo "  agent-zero-vm-image - Generate Agent-Zero VM image"
	@echo "  agent-zero-iso-image - Generate Agent-Zero ISO image"
	@echo "  agent-zero-minimal-image - Generate minimal system image (for testing)"
	@echo ""
	@echo "System image generation targets:"
	@echo "  system-image     - Generate Agent-Zero system disk image"
	@echo "  vm-image         - Generate Agent-Zero VM image"
	@echo "  iso-image        - Generate Agent-Zero ISO image"
	@echo "  validate-config  - Validate system configuration only"
	@echo ""
	@echo "Guix environment targets:"
	@echo "  guix-env         - Enter Guix development environment"
	@echo "  guix-shell       - Enter Guix containerized shell"
	@echo ""
	@echo "Production deployment targets:"
	@echo "  production-setup - Setup production environment"
	@echo "  production-build - Build production Docker image"
	@echo "  production-deploy - Deploy to production"
	@echo "  production-status - Check production deployment status"
	@echo "  production-health - Run production health check"
	@echo "  production-backup - Create production backup"
	@echo "  production-rollback - Rollback production deployment"
	@echo "  production-logs  - View production logs"
	@echo "  production-up    - Start production services (Docker Compose)"
	@echo "  production-down  - Stop production services (Docker Compose)"
	@echo ""
	@echo "  help             - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  BUILD_TYPE       - Build type (Debug, Release, RelWithDebInfo) [default: Release]"
	@echo "  JOBS             - Number of parallel jobs [default: \$(nproc)]"
	@echo "  INSTALL_PREFIX   - Installation prefix [default: /usr/local]"
	@echo "  BUILD_DIR        - Build directory [default: build]"
	@echo "  SKIP_TESTS       - Skip tests (true/false) [default: false]"
	@echo "  SKIP_INSTALL     - Skip installation (true/false) [default: false]"
	@echo "  CLEAN_BUILD      - Clean build directory (true/false) [default: false]"
	@echo ""
	@echo "Examples:"
	@echo "  make                    # Build with default settings"
	@echo "  make BUILD_TYPE=Debug   # Debug build"
	@echo "  make JOBS=4            # Build with 4 jobs"
	@echo "  make SKIP_TESTS=true   # Build without tests"
	@echo "  make clean build       # Clean build"
	@echo "  make agent-zero        # Build Agent-Zero Genesis"
	@echo "  make guix-env          # Enter Guix development environment"

# Setup dependencies
.PHONY: setup
setup:
	@echo "$(BLUE)[INFO]$(NC) Setting up dependencies..."
	@shards install --frozen
	@shards check

# Setup development environment
.PHONY: dev-env
dev-env:
	@echo "$(BLUE)[INFO]$(NC) Setting up development environment..."
	@./scripts/build-monorepo.sh --dev-env

# Configure CMake
.PHONY: configure
configure:
	@echo "$(BLUE)[INFO]$(NC) Crystal targets are configured by shard.yml"
	@shards check

# Build all components
.PHONY: build
build: configure
	@echo "$(BLUE)[INFO]$(NC) Building all components..."
	@shards build $(RELEASE_FLAGS) --verbose --error-trace
	@echo "$(GREEN)[SUCCESS]$(NC) Build complete"

# Build core components only
.PHONY: core
core: configure
	@echo "$(BLUE)[INFO]$(NC) Building core components..."
	@shards build $(RELEASE_FLAGS) crystalcog cogserver cogshell atomspace_bin opencog_bin pln_bin ure_bin attention_bin
	@echo "$(GREEN)[SUCCESS]$(NC) Core build complete"

# Build extended components
.PHONY: extended
extended: core
	@echo "$(BLUE)[INFO]$(NC) Building extended components..."
	@shards build $(RELEASE_FLAGS) --verbose --error-trace
	@echo "$(GREEN)[SUCCESS]$(NC) Extended build complete"

# Run tests
.PHONY: test
test: build
ifeq ($(SKIP_TESTS),true)
	@echo "$(YELLOW)[WARNING]$(NC) Skipping tests as requested"
else
	@echo "$(BLUE)[INFO]$(NC) Running tests..."
	@crystal spec --stats -v --error-trace --no-color
	@echo "$(GREEN)[SUCCESS]$(NC) Tests complete"
endif

.PHONY: verify
verify:
	@./scripts/verify.sh all

# Install components
.PHONY: install
install: build
ifeq ($(SKIP_INSTALL),true)
	@echo "$(YELLOW)[WARNING]$(NC) Skipping installation as requested"
else
	@echo "$(BLUE)[INFO]$(NC) Installing components..."
	@install -d $(DESTDIR)$(INSTALL_PREFIX)/bin
	@install -m 0755 bin/* $(DESTDIR)$(INSTALL_PREFIX)/bin/
	@echo "$(GREEN)[SUCCESS]$(NC) Installation complete"
	@echo "$(BLUE)[INFO]$(NC) You may need to run: sudo ldconfig"
endif

# Generate documentation
.PHONY: doc
doc: build
	@echo "$(BLUE)[INFO]$(NC) Generating documentation..."
	@crystal docs
	@echo "$(GREEN)[SUCCESS]$(NC) Documentation generated"

# Create package
.PHONY: package
package: build
	@echo "$(BLUE)[INFO]$(NC) Creating package..."
	@tar -czf crystalcog-0.1.0-bin.tar.gz -C bin .
	@echo "$(GREEN)[SUCCESS]$(NC) Package created"

# Clean build directory
.PHONY: clean
clean:
	@echo "$(BLUE)[INFO]$(NC) Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "$(GREEN)[SUCCESS]$(NC) Build directory cleaned"

# Clean and rebuild
.PHONY: rebuild
rebuild: clean build

# Full build with tests and installation
.PHONY: full
full: setup build test install

# Quick build (skip tests and installation)
.PHONY: quick
quick: build

# Development build
.PHONY: dev
dev: BUILD_TYPE=Debug
dev: build test

# Release build
.PHONY: release
release: BUILD_TYPE=Release
release: clean build test install

# Profile build
.PHONY: profile
profile: BUILD_TYPE=RelWithDebInfo
profile: build

# Coverage build
.PHONY: coverage
coverage: BUILD_TYPE=Coverage
coverage: build test

# Install system dependencies
.PHONY: deps
deps:
	@echo "$(BLUE)[INFO]$(NC) Installing system dependencies..."
	@./scripts/build-monorepo.sh --setup-only

# Setup Python environment
.PHONY: python-env
python-env:
	@echo "$(BLUE)[INFO]$(NC) Setting up Python environment..."
	@python3 -m venv venv
	@source venv/bin/activate && pip install --upgrade pip
	@source venv/bin/activate && pip install -r requirements.txt
	@echo "$(GREEN)[SUCCESS]$(NC) Python environment setup complete"

# Setup Node.js environment
.PHONY: node-env
node-env:
	@echo "$(BLUE)[INFO]$(NC) Setting up Node.js environment..."
	@if [ -f "package.json" ]; then npm install; fi
	@echo "$(GREEN)[SUCCESS]$(NC) Node.js environment setup complete"

# Setup Rust environment
.PHONY: rust-env
rust-env:
	@echo "$(BLUE)[INFO]$(NC) Setting up Rust environment..."
	@if [ -f "Cargo.toml" ]; then cargo build --release; fi
	@echo "$(GREEN)[SUCCESS]$(NC) Rust environment setup complete"

# Run specific component tests
.PHONY: test-%
test-%: build
	@echo "$(BLUE)[INFO]$(NC) Running tests for $*..."
	@crystal spec --error-trace "spec/$*/"

# Build specific component
.PHONY: build-%
build-%: configure
	@echo "$(BLUE)[INFO]$(NC) Building $*..."
	@shards build $(RELEASE_FLAGS) "$*"

# Install specific component
.PHONY: install-%
install-%: build-%
	@echo "$(BLUE)[INFO]$(NC) Installing $*..."
	@install -d $(DESTDIR)$(INSTALL_PREFIX)/bin
	@install -m 0755 "bin/$*" $(DESTDIR)$(INSTALL_PREFIX)/bin/

# Show build status
.PHONY: status
status:
	@echo "$(BLUE)[INFO]$(NC) Build Status:"
	@echo "  Build Type: $(BUILD_TYPE)"
	@echo "  Jobs: $(JOBS)"
	@echo "  Install Prefix: $(INSTALL_PREFIX)"
	@echo "  Build Directory: $(BUILD_DIR)"
	@echo "  Skip Tests: $(SKIP_TESTS)"
	@echo "  Skip Install: $(SKIP_INSTALL)"
	@echo "  Clean Build: $(CLEAN_BUILD)"
	@if [ -d "bin" ]; then \
		echo "  Build Output: $(GREEN)Exists$(NC)"; \
	else \
		echo "  Build Output: $(RED)Missing$(NC)"; \
	fi

# Show component list
.PHONY: components
components:
	@echo "$(BLUE)[INFO]$(NC) Available components:"
	@echo "Core Components:"
	@echo "  cogutil atomspace attention ure pln link-grammar cogserver"
	@echo ""
	@echo "Extended Components:"
	@echo "  asmoses agents agi-bio atomspace-agents atomspace-bridge"
	@echo "  atomspace-cog atomspace-dht atomspace-explorer atomspace-ipfs"
	@echo "  atomspace-js atomspace-metta atomspace-restful atomspace-rocks"
	@echo "  atomspace-rpc atomspace-typescript atomspace-websockets"
	@echo "  benchmark blender_api blender_api_msgs cheminformatics"
	@echo "  cogprotolab destin dimensional-embedding distributional-value"
	@echo "  external-tools generate ghost_bridge guile-dbi"
	@echo "  language-learning learn lg-atomese logicmoo_cogserver"
	@echo "  loving-ai loving-ai-ghost miner moses ocpkg opencog"
	@echo "  opencog-cycl opencog-debian opencog-neo4j opencog-nix"
	@echo "  opencog.org opencog_rpi opencog-to-minecraft pattern-index"
	@echo "  pau2motors perception pi_vision pln-brca-xp python-attic"
	@echo "  python-client python-destin relex rest-api-documentation"
	@echo "  robots_config rocca ros-behavior-scripting"
	@echo "  ros_opencog_robot_embodiment semantic-vision sensory"
	@echo "  spacetime stochastic-language-generation test-datasets"
	@echo "  TinyCog tv-toolbox unify unity3d-opencog-game"
	@echo "  vision visualization"

# Show help for specific component
.PHONY: help-%
help-%:
	@echo "$(BLUE)[INFO]$(NC) Help for component: $*"
	@echo "Available targets:"
	@echo "  build-$*     - Build $*"
	@echo "  test-$*      - Test $*"
	@echo "  install-$*   - Install $*"
	@echo ""
	@echo "Example: make build-$*"

# Agent-Zero Genesis targets
.PHONY: agent-zero agent-zero-setup agent-zero-test agent-zero-clean agent-zero-demo
.PHONY: system-image vm-image iso-image validate-config

# Build Agent-Zero Genesis (standalone)
agent-zero:
	@echo "$(BLUE)[INFO]$(NC) Building Agent-Zero Genesis..."
	@./scripts/agent-zero/build-agent-zero.sh
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero Genesis build complete"

# Setup Agent-Zero environment only
agent-zero-setup:
	@echo "$(BLUE)[INFO]$(NC) Setting up Agent-Zero environment..."
	@./scripts/agent-zero/build-agent-zero.sh --setup-only
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero environment setup complete"

# Test Agent-Zero components
agent-zero-test: agent-zero
	@echo "$(BLUE)[INFO]$(NC) Testing Agent-Zero Genesis..."
	@./tests/agent-zero/integration-test.sh
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero tests complete"

# Run Agent-Zero demonstration
agent-zero-demo: agent-zero
	@echo "$(BLUE)[INFO]$(NC) Running Agent-Zero Genesis demonstration..."
	@./scripts/agent-zero/demo-agent-zero.sh
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero demonstration complete"

# Clean Agent-Zero build artifacts
agent-zero-clean:
	@echo "$(BLUE)[INFO]$(NC) Cleaning Agent-Zero build artifacts..."
	@rm -rf build/agent-zero build/system-images
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero artifacts cleaned"

#<<<<<<< copilot/fix-62b924d7-f615-47d2-bdef-f907a093d2a7
# System image generation targets

# Generate Agent-Zero system disk image
system-image:
	@echo "$(BLUE)[INFO]$(NC) Generating Agent-Zero system disk image..."
	@./scripts/generate-system-image.sh --type disk-image
	@echo "$(GREEN)[SUCCESS]$(NC) System disk image generation complete"

# Generate Agent-Zero VM image  
vm-image:
	@echo "$(BLUE)[INFO]$(NC) Generating Agent-Zero VM image..."
	@./scripts/generate-system-image.sh --type vm-image
	@echo "$(GREEN)[SUCCESS]$(NC) VM image generation complete"

# Generate Agent-Zero ISO image
iso-image:
	@echo "$(BLUE)[INFO]$(NC) Generating Agent-Zero ISO image..."
	@./scripts/generate-system-image.sh --type iso
	@echo "$(GREEN)[SUCCESS]$(NC) ISO image generation complete"

# Validate system configuration
validate-config:
	@echo "$(BLUE)[INFO]$(NC) Validating Agent-Zero system configuration..."
	@./scripts/generate-system-image.sh --validate-only
	@echo "$(GREEN)[SUCCESS]$(NC) System configuration validation complete"
#=======
# Generate Agent-Zero system image
.PHONY: agent-zero-image agent-zero-vm-image agent-zero-iso-image
agent-zero-image: agent-zero
	@echo "$(BLUE)[INFO]$(NC) Generating Agent-Zero system disk image..."
	@./scripts/generate-system-image.sh disk-image
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero system image generated"

# Generate Agent-Zero VM image
agent-zero-vm-image: agent-zero
	@echo "$(BLUE)[INFO]$(NC) Generating Agent-Zero VM image..."
	@./scripts/generate-system-image.sh vm-image
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero VM image generated"

# Generate Agent-Zero ISO image
agent-zero-iso-image: agent-zero
	@echo "$(BLUE)[INFO]$(NC) Generating Agent-Zero ISO image..."
	@./scripts/generate-system-image.sh iso-image
	@echo "$(GREEN)[SUCCESS]$(NC) Agent-Zero ISO image generated"

# Generate minimal system image (faster for testing)
agent-zero-minimal-image: agent-zero
	@echo "$(BLUE)[INFO]$(NC) Generating minimal Agent-Zero system image..."
	@./scripts/generate-system-image.sh --minimal disk-image agent-zero-minimal
	@echo "$(GREEN)[SUCCESS]$(NC) Minimal Agent-Zero system image generated"
#>>>>>>> main

# Guix environment setup
.PHONY: guix-env guix-shell

# Enter Guix development environment
guix-env:
	@echo "$(BLUE)[INFO]$(NC) Entering Guix development environment..."
	@echo "$(YELLOW)[NOTE]$(NC) This will start a new shell with Agent-Zero dependencies"
	@guix environment -m guix.scm

# Enter Guix shell (containerized)
guix-shell:
	@echo "$(BLUE)[INFO]$(NC) Entering Guix containerized shell..."
	@echo "$(YELLOW)[NOTE]$(NC) This will start a containerized environment"
	@guix shell -m guix.scm --container --pure

# Production deployment targets
.PHONY: production-setup production-deploy production-status production-backup production-rollback production-logs

# Setup production environment
production-setup:
	@echo "$(BLUE)[INFO]$(NC) Setting up production environment..."
	@sudo ./scripts/production/setup-production.sh

# Deploy to production
production-deploy:
	@echo "$(BLUE)[INFO]$(NC) Deploying to production..."
	@./scripts/production/deploy.sh

# Check production deployment status
production-status:
	@echo "$(BLUE)[INFO]$(NC) Checking production deployment status..."
	@./scripts/production/deploy.sh --action status

# Backup production data
production-backup:
	@echo "$(BLUE)[INFO]$(NC) Creating production backup..."
	@./scripts/production/deploy.sh --action backup

# Rollback production deployment
production-rollback:
	@echo "$(BLUE)[INFO]$(NC) Rolling back production deployment..."
	@./scripts/production/deploy.sh --action rollback

# View production logs
production-logs:
	@echo "$(BLUE)[INFO]$(NC) Viewing production logs..."
	@./scripts/production/deploy.sh --action logs

# Build production Docker image
production-build:
	@echo "$(BLUE)[INFO]$(NC) Building production Docker image..."
	@docker build -f Dockerfile.production -t crystalcog/app:production .

# Run production health check
production-health:
	@echo "$(BLUE)[INFO]$(NC) Running production health check..."
	@./scripts/production/healthcheck.sh

# Production deployment with Docker Compose
production-up:
	@echo "$(BLUE)[INFO]$(NC) Starting production services with Docker Compose..."
	@docker compose -f docker-compose.production.yml up -d

# Stop production services
production-down:
	@echo "$(BLUE)[INFO]$(NC) Stopping production services..."
	@docker compose -f docker-compose.production.yml down
