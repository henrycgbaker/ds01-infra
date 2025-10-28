#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/audit-system.sh
# Create a comprehensive System Configuration Audit
# Focus: Configuration, not performance
# Run: Weekly or Monthly

DIR=/var/log/ds01-infra/audits/system
mkdir -p "$DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
AUDIT_FILE="$DIR/system_audit_${TIMESTAMP}.md"

{
    echo "# System Configuration Audit"
    echo ""
    echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    
    echo "## 📋 Audit Metadata"
    echo ""
    echo "| Field | Value |"
    echo "|-------|-------|"
    echo "| Timestamp | $TIMESTAMP |"
    echo "| Hostname | $(hostname) |"
    echo "| FQDN | $(hostname -f 2>/dev/null || echo 'N/A') |"
    echo "| Kernel | $(uname -r) |"
    echo "| OS | $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2) |"
    echo "| Uptime | $(uptime -p) |"
    echo "| Audit User | $USER |"
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 🖥️ Hardware Configuration"
    echo ""
    echo "### CPU"
    echo ""
    echo '```'
    lscpu | grep -E "Architecture|Model name|CPU\(s\)|Thread|Core|Socket|Vendor ID|CPU MHz"
    echo '```'
    echo ""
    
    echo "### Memory"
    echo ""
    echo '```'
    free -h
    echo '```'
    echo ""
    
    echo "### GPU Hardware"
    echo ""
    if command -v nvidia-smi &> /dev/null; then
        echo '```'
        nvidia-smi --query-gpu=index,name,driver_version,memory.total,compute_cap --format=csv
        echo '```'
        echo ""
        
        echo "**NVIDIA Driver Version:** $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
        echo ""
        echo "**CUDA Version:** $(nvidia-smi | grep "CUDA Version" | awk '{print $9}')"
        echo ""
    else
        echo "*nvidia-smi not available*"
        echo ""
    fi
    
    echo "---"
    echo ""
    
    echo "## 💾 Storage Configuration"
    echo ""
    echo "### Disk Capacity"
    echo ""
    echo '```'
    df -h | awk 'BEGIN {printf "%-30s %10s %10s %10s %8s %s\n", "Filesystem", "Size", "Used", "Avail", "Use%", "Mounted on"; print "────────────────────────────────────────────────────────────────────────────"} NR>1 {printf "%-30s %10s %10s %10s %8s %s\n", $1, $2, $3, $4, $5, $6}'
    echo '```'
    echo ""
    
    echo "### Disk Health (SMART Status)"
    echo ""
    if command -v smartctl &> /dev/null; then
        for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
            if [ -b "$disk" ]; then
                echo "**$disk:**"
                smartctl -H "$disk" 2>/dev/null | grep -E "SMART overall-health|PASSED|FAILED" || echo "Unable to read SMART data"
                echo ""
            fi
        done
    else
        echo "*smartctl not installed (install smartmontools)*"
    fi
    echo ""
    
    echo "### Mounted Filesystems"
    echo ""
    echo '```'
    mount | column -t | head -30
    echo '```'
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 👥 User Configuration"
    echo ""
    echo "### Users with UID >= 1000 (non-system)"
    echo ""
    echo "| Username | UID | GID | Home | Shell |"
    echo "|----------|-----|-----|------|-------|"
    awk -F: '$3 >= 1000 {printf "| %s | %s | %s | %s | %s |\n", $1, $3, $4, $6, $7}' /etc/passwd
    echo ""
    
    echo "### Currently Logged In Users"
    echo ""
    echo '```'
    who
    echo '```'
    echo ""
    
    echo "### Recent Login Activity (last 20)"
    echo ""
    echo '```'
    last -n 20 | head -21
    echo '```'
    echo ""
    
    echo "### Failed Login Attempts (last 20)"
    echo ""
    if [ -f /var/log/auth.log ]; then
        echo '```'
        grep "Failed password" /var/log/auth.log 2>/dev/null | tail -20 || echo "No failed attempts or insufficient permissions"
        echo '```'
    elif [ -f /var/log/secure ]; then
        echo '```'
        grep "Failed password" /var/log/secure 2>/dev/null | tail -20 || echo "No failed attempts or insufficient permissions"
        echo '```'
    else
        echo "*Auth log not accessible*"
    fi
    echo ""
    
    echo "### Sudo Usage (last 20 events)"
    echo ""
    if [ -f /var/log/auth.log ]; then
        echo '```'
        grep "sudo:" /var/log/auth.log 2>/dev/null | tail -20 || echo "No sudo events or insufficient permissions"
        echo '```'
    elif [ -f /var/log/secure ]; then
        echo '```'
        grep "sudo:" /var/log/secure 2>/dev/null | tail -20 || echo "No sudo events or insufficient permissions"
        echo '```'
    else
        echo "*Auth log not accessible*"
    fi
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 📦 Software Versions"
    echo ""
    echo "### Critical System Packages"
    echo ""
    echo "| Package | Version |"
    echo "|---------|---------|"
    
    # Check for common packages
    for pkg in docker.io docker-ce python3 python3-pip gcc git openssh-server; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            version=$(dpkg -l "$pkg" | grep "^ii" | awk '{print $3}')
            echo "| $pkg | $version |"
        fi
    done
    echo ""
    
    echo "### Python Environments"
    echo ""
    echo '```'
    python3 --version 2>/dev/null || echo "Python3 not found"
    pip3 --version 2>/dev/null || echo "pip3 not found"
    echo '```'
    echo ""
    
    if command -v conda &> /dev/null; then
        echo "**Conda environments:**"
        echo '```'
        conda env list
        echo '```'
        echo ""
    fi
    
    echo "---"
    echo ""
    
    echo "## 🌐 Network Configuration"
    echo ""
    echo "### Network Interfaces"
    echo ""
    echo '```'
    ip -br addr show
    echo '```'
    echo ""
    
    echo "### Listening Services"
    echo ""
    echo '```'
    ss -tlnp 2>/dev/null | head -20 || netstat -tlnp 2>/dev/null | head -20 || echo "Unable to query listening ports"
    echo '```'
    echo ""
    
    echo "### Firewall Status"
    echo ""
    if command -v ufw &> /dev/null; then
        echo "**UFW Status:**"
        echo '```'
        sudo ufw status verbose 2>/dev/null || echo "Unable to check UFW status"
        echo '```'
    elif command -v firewall-cmd &> /dev/null; then
        echo "**firewalld Status:**"
        echo '```'
        sudo firewall-cmd --list-all 2>/dev/null || echo "Unable to check firewalld status"
        echo '```'
    else
        echo "*No standard firewall detected*"
    fi
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 🔄 System Services"
    echo ""
    echo "### Critical Service Status"
    echo ""
    echo "| Service | Status | Enabled |"
    echo "|---------|--------|---------|"
    
    for service in ssh docker containerd cron; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
            enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "unknown")
            echo "| $service | $status | $enabled |"
        fi
    done
    echo ""
    
    echo "### Recent Service Failures"
    echo ""
    echo '```'
    systemctl --failed --no-pager
    echo '```'
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 🔐 Security Configuration"
    echo ""
    echo "### SSH Configuration Highlights"
    echo ""
    if [ -f /etc/ssh/sshd_config ]; then
        echo '```'
        grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config
        echo '```'
    else
        echo "*SSH config not accessible*"
    fi
    echo ""
    
    echo "### Open Ports (External Connections)"
    echo ""
    echo '```'
    ss -tuln | grep LISTEN | head -20
    echo '```'
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 📊 System Resource Capacity Trends"
    echo ""
    echo "### Disk Usage Growth (compare with previous audits)"
    echo ""
    echo '```'
    df -h / /home 2>/dev/null | awk 'NR==1 || NR>1 {printf "%-20s %10s %10s %10s %8s\n", $1, $2, $3, $4, $5}'
    echo '```'
    echo ""
    
    echo "### Log File Sizes"
    echo ""
    echo "| Directory | Size |"
    echo "|-----------|------|"
    du -sh /var/log 2>/dev/null | awk '{print "| /var/log | " $1 " |"}'
    du -sh ~/server_infra/logs 2>/dev/null | awk '{print "| ~/server_infra/logs | " $1 " |"}' || echo "| ~/server_infra/logs | N/A |"
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 🔄 Backup & Maintenance Status"
    echo ""
    echo "### Last System Reboot"
    echo ""
    echo '```'
    last reboot | head -3
    echo '```'
    echo ""
    
    echo "### Pending System Updates"
    echo ""
    if command -v apt &> /dev/null; then
        echo '```'
        apt list --upgradable 2>/dev/null | head -20
        echo '```'
    elif command -v yum &> /dev/null; then
        echo '```'
        yum check-update 2>/dev/null | head -20
        echo '```'
    fi
    echo ""
    
    echo "---"
    echo ""
    echo "*Audit completed at $(date '+%Y-%m-%d %H:%M:%S')*"
    echo ""
    echo "**Next Steps:**"
    echo "- Review disk usage trends"
    echo "- Check for pending security updates"
    echo "- Verify backup procedures"
    echo "- Review failed login attempts"
    
} > "$AUDIT_FILE"

# Create symlink to latest
ln -sf "$(basename "$AUDIT_FILE")" "$DIR/_latest_system_audit.md"

echo "✅ System audit complete: $AUDIT_FILE"
echo "📄 Latest audit symlink: $DIR/_latest_system_audit.md"