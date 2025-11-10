# Installing System-Wide Libraries

## Interactive Selection Library

**Source:** `/opt/ds01-infra/config/usr-mirrors/local/lib/interactive-select.sh`
**Target:** `/usr/local/lib/interactive-select.sh`

### Installation

```bash
sudo cp /opt/ds01-infra/config/usr-mirrors/local/lib/interactive-select.sh /usr/local/lib/interactive-select.sh
sudo chmod 644 /usr/local/lib/interactive-select.sh
```

### Verification

```bash
ls -la /usr/local/lib/interactive-select.sh
# Should show: -rw-r--r-- 1 root root [size] [date] /usr/local/lib/interactive-select.sh

# Test sourcing
bash -c "source /usr/local/lib/interactive-select.sh && echo 'Library loaded successfully'"
```

### Used By

The following commands depend on this library:
- `image-update`
- `image-delete`
- `container-run`
- `container-stop`
- `container-cleanup`

Without this library, these commands will show:
```
/usr/local/bin/[command]: line X: /usr/local/lib/interactive-select.sh: No such file or directory
```

### Updating

When the library is updated in the infra repo:

1. Update the mirror:
   ```bash
   cp /opt/ds01-infra/scripts/lib/interactive-select.sh /opt/ds01-infra/config/usr-mirrors/local/lib/interactive-select.sh
   ```

2. Deploy to system:
   ```bash
   sudo cp /opt/ds01-infra/config/usr-mirrors/local/lib/interactive-select.sh /usr/local/lib/interactive-select.sh
   ```
