
# To do
- [ ] identify things to backup
    - /home, 
    - docker volumes, 
    - infra repo
    - other?
- [ ] Document the backup schedule and restoration process

# To set up
- [ ] System maintenance tasks
- [ ] Backup scripts
- [ ] Log management
- [ ] Performance monitoring

### System Maintenance
```bash
# Update package lists daily
0 2 * * * apt update && apt upgrade -y

# Clean temporary files weekly
0 3 * * 0 find /tmp -type f -atime +7 -delete

# Backup critical configurations
0 1 * * * tar -czf /backups/config_backup_$(date +"%Y%m%d").tar.gz /etc/

# Monitor disk space hourly
0 * * * * df -h >> /var/log/disk_usage.log
```

### Data Science Specific Tasks
```bash
# Update Python packages
0 3 * * 1 pip list --outdated
# Runs every Monday at 3 AM

# Cleanup Jupyter notebook temporary files
0 4 * * * find ~/.local/share/jupyter/runtime -type f -mtime +3 -delete

# Backup "research data"
0 2 * * * rsync -a /path/to/research/data/ /path/to/backup/location/
```

## Sample Backup Script

```bash
#!/bin/bash
# backup script

# Timestamp for backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/path/to/backups"

# Backup important directories
tar -czf "$BACKUP_DIR/system_backup_$TIMESTAMP.tar.gz" \
    /etc \
    /home \
    /var/log

# Clean up old backups (older than 30 days)
find "$BACKUP_DIR" -type f -name "system_backup_*.tar.gz" -mtime +30 -delete

# Log the backup
echo "Backup completed at $TIMESTAMP" >> /var/log/backup.log