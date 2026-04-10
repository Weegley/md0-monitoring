# Cockpit RAID Tools

A simple Cockpit plugin for the RAID helper scripts.

## Features

- shows `mdadm --detail /dev/md0`
- shows `/var/log/raid/.last_smart`
- shows latest lines from:
  - `md0_YYYY-MM-DD.log`
  - `smart_YYYY-MM-DD.log`
  - `scrub_YYYY-MM-DD.log`
- if today's log does not exist yet, falls back to the latest available log
- can run:
  - `/usr/local/sbin/check_raid.sh`
  - `/usr/local/sbin/raid_scrub_bg.sh`
  - `/usr/local/sbin/scrub_stop.sh`
  - `/usr/local/sbin/cleanup_raid_logs.sh`

## Language behavior

- Russian UI is used when the detected Cockpit/browser language starts with `ru`
- English UI is used for all other languages

## Installation

```bash
sudo rm -rf /usr/local/share/cockpit/raidtools
sudo mkdir -p /usr/local/share/cockpit/raidtools
sudo cp -r raidtools/* /usr/local/share/cockpit/raidtools/
```

Then reload the Cockpit page in your browser.
