#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/audit-docker.sh
# Create a comprehensive Docker Configuration Audit
# Focus: Images, networks, volumes, security, not real-time stats
# Run: Weekly or Monthly

DIR=/var/log/ds01-infra/audits/docker
mkdir -p "$DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
AUDIT_FILE="$DIR/docker_audit_${TIMESTAMP}.md"

{
    echo "# 🐳 Docker Configuration Audit"
    echo ""
    echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""

    echo "**To do :**"
    echo "- Review containers without resource limits"
    echo "- Check for dangling images and volumes"
    echo "- Run vulnerability scans on production images"
    echo "- Verify privileged containers are necessary"
    echo "- Set up \`docker image prune\` automation"
    
    echo "## 📋 Audit Metadata"
    echo ""
    echo "| Field | Value |"
    echo "|-------|-------|"
    echo "| Timestamp | $TIMESTAMP |"
    echo "| Hostname | $(hostname) |"
    echo "| Audit User | $USER |"
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 📦 Container Inventory"
    echo ""
    echo "### Running Containers"
    echo ""
    RUNNING_COUNT=$(docker ps -q 2>/dev/null | wc -l)
    echo "**Total Running:** $RUNNING_COUNT"
    echo ""
    
    if [ "$RUNNING_COUNT" -gt 0 ]; then
        echo "| Name | Image | Created | Status | Ports |"
        echo "|------|-------|---------|--------|-------|"
        docker ps --format "{{.Names}}|{{.Image}}|{{.CreatedAt}}|{{.Status}}|{{.Ports}}" 2>/dev/null | \
        while IFS='|' read -r name image created status ports; do
            created_short=$(echo "$created" | cut -d' ' -f1)
            ports_short=$(echo "$ports" | cut -c1-30)
            echo "| $name | $image | $created_short | $status | $ports_short |"
        done
    else
        echo "*No running containers*"
    fi
    echo ""
    
    echo "### All Containers (including stopped)"
    echo ""
    TOTAL_COUNT=$(docker ps -a -q 2>/dev/null | wc -l)
    STOPPED_COUNT=$((TOTAL_COUNT - RUNNING_COUNT))
    echo "**Total:** $TOTAL_COUNT (**Stopped:** $STOPPED_COUNT)"
    echo ""
    
    if [ "$TOTAL_COUNT" -gt 0 ]; then
        echo "<details>"
        echo "<summary>Click to expand full container list</summary>"
        echo ""
        echo '```'
        docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Size}}" 2>/dev/null
        echo '```'
        echo ""
        echo "</details>"
    fi
    echo ""
    
    echo "### Container Resource Limits"
    echo ""
    echo "Containers without resource limits pose a risk of resource exhaustion."
    echo ""
    
    # Check for containers without limits
    docker ps --format "{{.Names}}" 2>/dev/null | while read -r container; do
        mem_limit=$(docker inspect "$container" --format '{{.HostConfig.Memory}}' 2>/dev/null)
        cpu_limit=$(docker inspect "$container" --format '{{.HostConfig.NanoCpus}}' 2>/dev/null)
        
        if [ "$mem_limit" = "0" ] && [ "$cpu_limit" = "0" ]; then
            echo "- ⚠️ **$container**: No CPU or memory limits set"
        elif [ "$mem_limit" = "0" ]; then
            echo "- ⚠️ **$container**: No memory limit set"
        elif [ "$cpu_limit" = "0" ]; then
            echo "- ⚠️ **$container**: No CPU limit set"
        else
            mem_mb=$((mem_limit / 1024 / 1024))
            echo "- ✅ **$container**: Memory limit ${mem_mb}MB, CPU limited"
        fi
    done
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 🖼️ Image Inventory"
    echo ""
    IMAGE_COUNT=$(docker images -q 2>/dev/null | wc -l)
    echo "**Total Images:** $IMAGE_COUNT"
    echo ""
    
    if [ "$IMAGE_COUNT" -gt 0 ]; then
        echo "| Repository | Tag | Image ID | Created | Size |"
        echo "|------------|-----|----------|---------|------|"
        docker images --format "{{.Repository}}|{{.Tag}}|{{.ID}}|{{.CreatedAt}}|{{.Size}}" 2>/dev/null | \
        head -20 | \
        while IFS='|' read -r repo tag id created size; do
            created_short=$(echo "$created" | cut -d' ' -f1)
            echo "| $repo | $tag | $id | $created_short | $size |"
        done
        
        if [ "$IMAGE_COUNT" -gt 20 ]; then
            echo ""
            echo "*Showing first 20 images. Total: $IMAGE_COUNT*"
        fi
    fi
    echo ""
    
    echo "### Dangling Images (unused)"
    echo ""
    DANGLING_COUNT=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
    echo "**Total Dangling:** $DANGLING_COUNT"
    echo ""
    
    if [ "$DANGLING_COUNT" -gt 0 ]; then
        echo '```'
        docker images -f "dangling=true" 2>/dev/null
        echo '```'
        echo ""
        echo "*💡 Run \`docker image prune\` to clean up dangling images*"
    else
        echo "*No dangling images*"
    fi
    echo ""
    
    echo "### Image Vulnerability Scan"
    echo ""
    if command -v trivy &> /dev/null; then
        echo "Running Trivy scan on critical images..."
        echo ""
        docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | head -5 | while read -r image; do
            echo "**$image:**"
            echo '```'
            trivy image --severity HIGH,CRITICAL --quiet "$image" 2>/dev/null | head -20
            echo '```'
            echo ""
        done
    else
        echo "*Trivy not installed. Consider installing for vulnerability scanning:*"
        echo '```'
        echo "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -"
        echo "echo 'deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main' | sudo tee /etc/apt/sources.list.d/trivy.list"
        echo "sudo apt update && sudo apt install trivy"
        echo '```'
    fi
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 📚 Volume Configuration"
    echo ""
    VOLUME_COUNT=$(docker volume ls -q 2>/dev/null | wc -l)
    echo "**Total Volumes:** $VOLUME_COUNT"
    echo ""
    
    if [ "$VOLUME_COUNT" -gt 0 ]; then
        echo "| Name | Driver | Mountpoint |"
        echo "|------|--------|------------|"
        docker volume ls --format "{{.Name}}|{{.Driver}}" 2>/dev/null | while IFS='|' read -r name driver; do
            mountpoint=$(docker volume inspect "$name" --format '{{.Mountpoint}}' 2>/dev/null)
            echo "| $name | $driver | $mountpoint |"
        done
        echo ""
        
        echo "### Volume Usage"
        echo ""
        docker system df -v 2>/dev/null | grep -A 100 "^VOLUME NAME" | head -30
        echo ""
    else
        echo "*No volumes defined*"
        echo ""
    fi
    
    echo "### Dangling Volumes"
    echo ""
    DANGLING_VOL_COUNT=$(docker volume ls -f "dangling=true" -q 2>/dev/null | wc -l)
    echo "**Total Dangling:** $DANGLING_VOL_COUNT"
    echo ""
    
    if [ "$DANGLING_VOL_COUNT" -gt 0 ]; then
        echo '```'
        docker volume ls -f "dangling=true" 2>/dev/null
        echo '```'
        echo ""
        echo "*💡 Run \`docker volume prune\` to clean up dangling volumes (⚠️ be careful!)*"
    else
        echo "*No dangling volumes*"
    fi
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 🌐 Network Configuration"
    echo ""
    NETWORK_COUNT=$(docker network ls -q 2>/dev/null | wc -l)
    echo "**Total Networks:** $NETWORK_COUNT"
    echo ""
    
    if [ "$NETWORK_COUNT" -gt 0 ]; then
        echo "| Name | Driver | Scope | Subnet |"
        echo "|------|--------|-------|--------|"
        docker network ls --format "{{.Name}}|{{.Driver}}|{{.Scope}}" 2>/dev/null | while IFS='|' read -r name driver scope; do
            subnet=$(docker network inspect "$name" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
            echo "| $name | $driver | $scope | $subnet |"
        done
    fi
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 💾 Docker Disk Usage"
    echo ""
    echo '```'
    docker system df 2>/dev/null
    echo '```'
    echo ""
    
    echo "### Detailed Breakdown"
    echo ""
    echo '```'
    docker system df -v 2>/dev/null | head -50
    echo '```'
    echo ""
    
    echo "---"
    echo ""
    
    echo "## 🔐 Security Configuration"
    echo ""
    echo "### Docker Daemon Configuration"
    echo ""
    if [ -f /etc/docker/daemon.json ]; then
        echo '```json'
        cat /etc/docker/daemon.json
        echo '```'
    else
        echo "*No custom daemon configuration (/etc/docker/daemon.json not found)*"
    fi
    echo ""
    
    echo "### Running Containers with Privileged Mode"
    echo ""
    PRIV_COUNT=0
    docker ps --format "{{.Names}}" 2>/dev/null | while read -r container; do
        privileged=$(docker inspect "$container" --format '{{.HostConfig.Privileged}}' 2>/dev/null)
        if [ "$privileged" = "true" ]; then
            echo "- ⚠️ **$container**: Running in privileged mode"
            PRIV_COUNT=$((PRIV_COUNT + 1))
        fi
    done
    
    if [ "$PRIV_COUNT" -eq 0 ]; then
        echo "*No containers running in privileged mode*"
    fi
    echo ""
    
    echo "### Containers with Host Network Mode"
    echo ""
    docker ps --format "{{.Names}}" 2>/dev/null | while read -r container; do
        network_mode=$(docker inspect "$container" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
        if [ "$network_mode" = "host" ]; then
            echo "- ⚠️ **$container**: Using host network mode"
        fi
    done
    echo ""
    
    echo "---"
    echo ""
    
    echo '```'
    echo "## 📊 Historical Growth Trends"
    echo ""
    echo "| Metric | Current Value |"
    echo "|--------|---------------|"
    echo "| Total Containers | $TOTAL_COUNT |"
    echo "| Running Containers | $RUNNING_COUNT |"
    echo "| Total Images | $IMAGE_COUNT |"
    echo "| Total Volumes | $VOLUME_COUNT |"
    echo "| Total Networks | $NETWORK_COUNT |"
    echo ""
    
    # Get disk usage numbers
    IMAGES_SIZE=$(docker system df 2>/dev/null | grep "^Images" | awk '{print $3" "$4}')
    CONTAINERS_SIZE=$(docker system df 2>/dev/null | grep "^Containers" | awk '{print $3" "$4}')
    VOLUMES_SIZE=$(docker system df 2>/dev/null | grep "^Local Volumes" | awk '{print $3" "$4}')
    
    echo "| Images Size | $IMAGES_SIZE |"
    echo "| Containers Size | $CONTAINERS_SIZE |"
    echo "| Volumes Size | $VOLUMES_SIZE |"
    echo ""
    
    echo "---"
    echo ""
    echo "*Audit completed at $(date '+%Y-%m-%d %H:%M:%S')*"
    echo ""

    echo "## 🐳 Docker System Information"
    echo ""
    echo "### Version"
    echo ""
    echo '```'
    docker version 2>/dev/null || echo "Docker not available"
    echo '```'
    echo ""
    
    echo "### System Info"
    echo ""
    echo '```'
    docker system info 2>/dev/null | head -40
    echo '```'
    echo ""
    
    echo "---"
    echo ""
    
    
} > "$AUDIT_FILE"

# Create symlink to latest
ln -sf "$(basename "$AUDIT_FILE")" "$DIR/_latest_docker_audit.md"

echo "✅ Docker audit complete: $AUDIT_FILE"
echo "📄 Latest audit symlink: $DIR/_latest_docker_audit.md"