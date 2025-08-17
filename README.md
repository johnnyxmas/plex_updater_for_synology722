# Synology Plex Auto-Update Script

An intelligent bash script for automatically checking and updating Plex Media Server on Synology DSM 7.2.2+ systems.

## Supported Architectures

- x86_64 (Intel/AMD 64-bit)
- x86 (Intel/AMD 32-bit)
- armv7hf (ARM 32-bit)
- aarch64 (ARM 64-bit)

## Requirements

- Synology DSM 7.2.2 or compatible
- Root access (sudo)
- Internet connection
- `curl` installed (standard on DSM)

## Installation

1. **Download the script**:
   ```bash
   wget -O update_plex.sh https://raw.githubusercontent.com/your-username/synology-plex-updater/main/update_plex.sh
   ```

2. **Make it executable**:
   ```bash
   chmod +x update_plex.sh
   ```

3. **Test run**:
   ```bash
   sudo ./update_plex.sh
   ```

## Usage

### Basic Usage
```bash
# Check for updates and install if available
sudo ./update_plex.sh
```

### Force Build Updates
```bash
# Update even when only build hash differs
sudo ./update_plex.sh --force-build-update
```

### Help
```bash
./update_plex.sh --help
```

## Automated Scheduling

### Synology Task Scheduler
1. Open **Control Panel** → **Task Scheduler**
2. Click **Create** → **Scheduled Task** → **User-defined script**
3. Configure the task:
   - **General Tab**:
     - Task name: `Plex Auto Update`
     - User: `root`
     - Enabled: ✓
   - **Schedule Tab**:
     - Date: Daily
     - Time: 04:00 (or your preferred time)
   - **Task Settings Tab**:
     - Run command: `/path/to/your/update_plex.sh`
     - Send run details by email: ✓ (optional, if you want notifications)
4. Click **OK** to save

## Logging

The script maintains detailed logs:

- **Main Log**: `/var/log/plex_updater.log` - All script activity
- **Task Scheduler Log**: Available in DSM Task Scheduler interface

## Configuration

Edit the script header to customize:

```bash
# Configuration
DOWNLOAD_DIR="/tmp/plex_update"           # Temporary download location
LOG_FILE="/var/log/plex_updater.log"     # Main log file location
USER_AGENT="Mozilla/5.0 (...)"           # User agent for web requests
```

## Troubleshooting

### Common Issues

**Script fails with "permission denied"**:
```bash
chmod +x update_plex.sh
sudo ./update_plex.sh
```

**"Could not determine latest Plex version"**:
- Check internet connectivity
- Verify firewall isn't blocking outbound requests
- Try running with `--force-build-update` flag

**Installation fails**:
- Check available disk space in `/tmp`
- Verify Synology package management isn't locked
- Review logs for specific error messages

**Task Scheduler not running**:
- Verify the task is enabled in Control Panel → Task Scheduler
- Check the task history for error messages
- Ensure the script path is correct and accessible
- Review the "View Result" output for the scheduled task

## License

MIT License - see LICENSE file for details.

## Disclaimer

This script is not officially supported by Plex Inc. or Synology. Use at your own risk. Always ensure you have proper backups of your Plex configuration before running automated updates.

---

**⭐ If this script helps you, please star the repository!**
