# Calendar Reminder

A bash script that monitors calendar events from `.ics` files and displays desktop notifications with interactive panel icons.

## Features

- **Desktop Notifications**: Shows reminders 15 minutes before events (configurable)
- **Interactive Panel Icons**: Click to view event details or dismiss notifications
- **All-day Event Support**: Proper handling of whole-day events
- **Real-time Monitoring**: Continuously checks for upcoming events
- **Configurable Timing**: Customizable check intervals and reminder times

## Dependencies

Before using this script, install the required tools:

```bash
# On Arch Linux
sudo pacman -S yad fyi
```

Required tools:
- `yad` - For panel icons and dialog boxes (fork of zenity)
- `fyi` - For desktop notifications (alternative to notify-send)
- `awk` - For parsing .ics files (usually pre-installed)

## Usage

### Basic Usage

```bash
# Use default settings (~/calendar.ics, check every 60s, remind 15min before)
./calendar_reminder.sh

# Specify custom .ics file
./calendar_reminder.sh -f ~/Documents/mycalendar.ics

# Custom check interval and reminder time
./calendar_reminder.sh -i 30 -r 30  # Check every 30s, remind 30min before
```

### Command Line Options

```
-f, --file FILE         Path to .ics file (default: ~/calendar.ics)
-i, --interval SECONDS  Check interval in seconds (default: 60)
-r, --reminder MINUTES  Reminder time in minutes before event (default: 15)
-h, --help              Display help message
```

## Configuration

Edit the configuration variables at the top of the script:

```bash
ICS_FILE="$HOME/calendar.ics"  # Path to .ics file
CHECK_INTERVAL=60              # Check every 60 seconds
REMINDER_TIME=900              # Reminder 15 minutes before (in seconds)
NOTIFICATION_ICON="calendar"   # Notification icon
```

## How It Works

1. **Monitors**: Continuously monitors your `.ics` calendar file
2. **Parses**: Extracts event details (title, time, location, description)
3. **Notifies**: Shows desktop notifications before events start
4. **Interactive**: Creates clickable panel icons for each notification
5. **Details**: Click icons to view full event details or dismiss notifications

## Event Types

- **Timed Events**: Shows exact time and countdown
- **All-day Events**: Displays as morning reminders for the event day
- **Past Events**: Brief notifications for recently started events

## Notification Features

- Desktop notifications via `fyi`
- Persistent panel icons via `yad`
- Event details popup window
- Manual dismissal options
- Automatic cleanup

## File Structure

The script creates temporary files in `/tmp/calendar_reminder/` for:
- Notification data storage
- YAD process management
- Event detail scripts

## Stopping the Script

Press `Ctrl+C` to stop the monitoring and clean up all notifications.

## Troubleshooting

1. **No notifications appearing**: Check if your `.ics` file exists and contains valid events
2. **Missing dependencies**: Install `yad` and `fyi` using your package manager
3. **Panel icons not showing**: Ensure you're using a panel that supports system tray (e.g., tint2)

## License

This script is provided as-is for personal use.
