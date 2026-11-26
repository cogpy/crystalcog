#!/bin/bash
# CrystalCog Production Environment Setup Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_DIR="/opt/crystalcog"
SERVICE_USER="crystalcog"
BACKUP_DIR="/backup/crystalcog"

print_status() {
    echo -e "${BLUE}[Setup]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[Setup]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[Setup]${NC} $1"
}

print_error() {
    echo -e "${RED}[Setup]${NC} $1"
}

usage() {
    echo "CrystalCog Production Environment Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --install-dir DIR     Installation directory (default: /opt/crystalcog)"
    echo "  --service-user USER   Service user (default: crystalcog)"
    echo "  --backup-dir DIR      Backup directory (default: /backup/crystalcog)"
    echo "  --skip-docker        Skip Docker installation"
    echo "  --skip-ssl           Skip SSL certificate setup"
    echo "  -h, --help           Show this help message"
}

# Parse command line arguments
SKIP_DOCKER=false
SKIP_SSL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --service-user)
            SERVICE_USER="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --skip-ssl)
            SKIP_SSL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Update system packages
update_system() {
    print_status "Updating system packages..."
    
    apt-get update
    apt-get upgrade -y
    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        htop \
        vim \
        ufw \
        fail2ban \
        logrotate \
        cron \
        openssl
    
    print_success "System packages updated"
}

# Install Docker and Docker Compose
install_docker() {
    if [ "$SKIP_DOCKER" = true ]; then
        print_status "Skipping Docker installation"
        return
    fi
    
    print_status "Installing Docker and Docker Compose..."
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Install Docker Compose (standalone)
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker and Docker Compose installed"
}

# Create service user
create_service_user() {
    print_status "Creating service user: $SERVICE_USER"
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -m -s /bin/bash "$SERVICE_USER"
        usermod -aG docker "$SERVICE_USER"
        print_success "Service user created: $SERVICE_USER"
    else
        print_warning "Service user already exists: $SERVICE_USER"
    fi
}

# Setup directory structure
setup_directories() {
    print_status "Setting up directory structure..."
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"/{config,scripts,data,logs,backups}
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR"
    
    print_success "Directory structure created"
}

# Copy application files
copy_application_files() {
    print_status "Copying application files..."
    
    # Copy Docker Compose and configuration files
    cp "$PROJECT_ROOT/docker-compose.production.yml" "$INSTALL_DIR/"
    cp "$PROJECT_ROOT/Dockerfile.production" "$INSTALL_DIR/"
    cp -r "$PROJECT_ROOT/config" "$INSTALL_DIR/"
    cp -r "$PROJECT_ROOT/scripts" "$INSTALL_DIR/"
    cp -r "$PROJECT_ROOT/deployments" "$INSTALL_DIR/"
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/scripts/production/"*.sh
    
    print_success "Application files copied"
}

# Setup SSL certificates
setup_ssl() {
    if [ "$SKIP_SSL" = true ]; then
        print_status "Skipping SSL certificate setup"
        return
    fi
    
    print_status "Setting up SSL certificates..."
    
    # Install Certbot
    apt-get install -y certbot python3-certbot-nginx
    
    # Create SSL directory
    mkdir -p "$INSTALL_DIR/config/production/ssl"
    
    print_warning "SSL certificates need to be obtained manually:"
    print_warning "Run: certbot certonly --standalone -d crystalcog.example.com"
    print_warning "Then copy certificates to: $INSTALL_DIR/config/production/ssl/"
    
    # Create self-signed certificates for testing
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$INSTALL_DIR/config/production/ssl/crystalcog.key" \
        -out "$INSTALL_DIR/config/production/ssl/crystalcog.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=crystalcog.example.com"
    
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/config/production/ssl"
    chmod 600 "$INSTALL_DIR/config/production/ssl/crystalcog.key"
    
    print_success "SSL certificates setup completed"
}

# Configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Reset UFW to default
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow application ports (if needed for external access)
    ufw allow 5000/tcp comment "CrystalCog API"
    ufw allow 17001/tcp comment "CogServer"
    
    # Allow monitoring ports (restrict to internal network)
    ufw allow from 10.0.0.0/8 to any port 3000 comment "Grafana"
    ufw allow from 10.0.0.0/8 to any port 9090 comment "Prometheus"
    
    # Enable firewall
    ufw --force enable
    
    print_success "Firewall configured"
}

# Setup fail2ban
setup_fail2ban() {
    print_status "Setting up fail2ban..."
    
    # Create custom jail configuration
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF
    
    # Restart fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    print_success "fail2ban configured"
}

# Setup logrotate
setup_logrotate() {
    print_status "Setting up log rotation..."
    
    cat > /etc/logrotate.d/crystalcog << EOF
$INSTALL_DIR/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 $SERVICE_USER $SERVICE_USER
    postrotate
        docker-compose -f $INSTALL_DIR/docker-compose.production.yml restart crystalcog-app
    endscript
}

/var/log/nginx/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 www-data www-data
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 \$(cat /var/run/nginx.pid)
        fi
    endscript
}
EOF
    
    print_success "Log rotation configured"
}

# Setup backup cron job
setup_backup_cron() {
    print_status "Setting up backup cron job..."
    
    # Create backup script
    cat > "$INSTALL_DIR/scripts/production/backup.sh" << 'EOF'
#!/bin/bash
# CrystalCog Automated Backup Script

set -e

BACKUP_DIR="/backup/crystalcog/$(date +%Y%m%d_%H%M%S)"
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

# Backup the Paphos data file and event journal
docker run --rm -v crystalcog_app-data:/data -v "$BACKUP_DIR":/backup alpine \
    tar czf /backup/app-data.tar.gz -C /data .

# Backup configuration
cp -r /opt/crystalcog/config "$BACKUP_DIR/"

# Cleanup old backups
find /backup/crystalcog -type d -mtime +$RETENTION_DAYS -exec rm -rf {} +

echo "Backup completed: $BACKUP_DIR"
EOF
    
    chmod +x "$INSTALL_DIR/scripts/production/backup.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/scripts/production/backup.sh"
    
    # Add cron job
    crontab -u "$SERVICE_USER" -l 2>/dev/null | { cat; echo "0 2 * * * $INSTALL_DIR/scripts/production/backup.sh >> $INSTALL_DIR/logs/backup.log 2>&1"; } | crontab -u "$SERVICE_USER" -
    
    print_success "Backup cron job configured"
}

# Create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."
    
    cat > /etc/systemd/system/crystalcog.service << EOF
[Unit]
Description=CrystalCog Production Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/docker-compose -f docker-compose.production.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.production.yml down
ExecReload=/usr/local/bin/docker-compose -f docker-compose.production.yml restart
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable crystalcog.service
    
    print_success "Systemd service created"
}

# Generate environment file template
generate_env_file() {
    print_status "Generating environment file template..."
    
    cat > "$INSTALL_DIR/.env.production.template" << EOF
# CrystalCog Production Environment Configuration
# Copy this file to .env.production and update with your values

# Database Configuration
POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD

# Monitoring Configuration  
GRAFANA_ADMIN_PASSWORD=CHANGE_ME_STRONG_PASSWORD

# Email Configuration
SMTP_HOST=smtp.example.com
SMTP_USER=noreply@example.com
SMTP_PASSWORD=CHANGE_ME_SMTP_PASSWORD

# SSL Configuration
SSL_CERT_PATH=$INSTALL_DIR/config/production/ssl/crystalcog.crt
SSL_KEY_PATH=$INSTALL_DIR/config/production/ssl/crystalcog.key

# Backup Configuration
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_RETENTION_DAYS=30

# Domain Configuration
DOMAIN=crystalcog.example.com
STAGING_DOMAIN=staging.crystalcog.example.com
EOF
    
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/.env.production.template"
    
    print_success "Environment file template generated"
}

# Main setup function
main() {
    print_status "Starting CrystalCog production environment setup..."
    
    check_root
    update_system
    install_docker
    create_service_user
    setup_directories
    copy_application_files
    setup_ssl
    configure_firewall
    setup_fail2ban
    setup_logrotate
    setup_backup_cron
    create_systemd_service
    generate_env_file
    
    print_success "Production environment setup completed!"
    print_warning ""
    print_warning "Next steps:"
    print_warning "1. Copy .env.production.template to .env.production and update values"
    print_warning "2. Obtain SSL certificates and place them in config/production/ssl/"
    print_warning "3. Update domain names in configuration files"
    print_warning "4. Run: systemctl start crystalcog"
    print_warning "5. Check status: systemctl status crystalcog"
    print_warning ""
    print_warning "Installation directory: $INSTALL_DIR"
    print_warning "Service user: $SERVICE_USER"
    print_warning "Backup directory: $BACKUP_DIR"
}

# Run main function
main "$@"