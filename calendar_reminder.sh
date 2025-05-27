#!/bin/bash

# Configuration
ICS_FILE="$HOME/calendar.ics"  # Path to .ics file
CHECK_INTERVAL=60              # Check every 60 seconds
REMINDER_TIME=900              # Reminder 15 minutes before (in seconds)
NOTIFICATION_ICON="calendar"   # Notification icon
TEMP_DIR="/tmp/calendar_reminder"

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Function to parse ICS file
parse_ics() {
    local ics_file="$1"
    local current_time=$(date +%s)
    local upcoming_events=()

    if [[ ! -f "$ics_file" ]]; then
        echo "File $ics_file does not exist!"
        return 1
    fi

    # Parse events from ICS file
    awk '
    BEGIN {
        RS = "BEGIN:VEVENT"
        FS = "\n"
    }
    NR > 1 {
        summary = ""
        description = ""
        dtstart = ""
        location = ""

        for (i = 1; i <= NF; i++) {
            if ($i ~ /^SUMMARY:/) {
                summary = substr($i, 9)
                gsub(/\\,/, ",", summary)
                gsub(/\\;/, ";", summary)
                gsub(/\\n/, "\n", summary)
            }
            if ($i ~ /^DESCRIPTION:/) {
                description = substr($i, 13)
                gsub(/\\,/, ",", description)
                gsub(/\\;/, ";", description)
                gsub(/\\n/, "\n", description)
            }
            if ($i ~ /^DTSTART/) {
                dtstart = $i
                gsub(/^DTSTART[^:]*:/, "", dtstart)
                # Handle both DATE and DATETIME formats
                if (dtstart ~ /T/) {
                    # DATETIME format: 20250527T003500 or 20250527T003500Z
                    gsub(/Z$/, "", dtstart)  # Remove Z if present
                } else {
                    # DATE format: 20250526 - add default time 00:00
                    dtstart = dtstart "T0000"
                }
            }
            if ($i ~ /^LOCATION:/) {
                location = substr($i, 10)
                gsub(/\\,/, ",", location)
                gsub(/\\;/, ";", location)
            }
        }

        if (summary != "" && dtstart != "") {
            # Convert date from YYYYMMDDTHHMMSS format to timestamp
            year = substr(dtstart, 1, 4)
            month = substr(dtstart, 5, 2)
            day = substr(dtstart, 7, 2)

            # Extract time part after T
            if (dtstart ~ /T/) {
                timepart = substr(dtstart, index(dtstart, "T") + 1)
                hour = substr(timepart, 1, 2)
                minute = substr(timepart, 3, 2)
            } else {
                hour = "00"
                minute = "00"
            }

            if (hour == "") hour = "00"
            if (minute == "") minute = "00"

            printf "%s|%s|%s|%s-%s-%s %s:%s\n", summary, description, location, year, month, day, hour, minute
        }
    }' "$ics_file"
}

# Function to convert date to timestamp
date_to_timestamp() {
    local date_str="$1"
    date -d "$date_str" +%s 2>/dev/null || echo 0
}

# Function to display notification
show_notification() {
    local title="$1"
    local message="$2"
    local event_id="$3"

    # fyi notification
    fyi -i "$NOTIFICATION_ICON" -t 10000 "$title" "$message"

    # Create icon in panel with YAD
    local notification_file="$TEMP_DIR/notification_$event_id"
    echo "$title|$message" > "$notification_file"

    # Create wrapper scripts for YAD menu actions
    local details_script="$TEMP_DIR/show_details_$event_id.sh"
    local close_script="$TEMP_DIR/close_$event_id.sh"

    cat > "$details_script" << EOF
#!/bin/bash
TEMP_DIR="$TEMP_DIR"
event_id="$event_id"
$(declare -f show_event_details)
$(declare -f close_notification)
show_event_details "\$event_id"
EOF
    chmod +x "$details_script"

    cat > "$close_script" << EOF
#!/bin/bash
TEMP_DIR="$TEMP_DIR"
event_id="$event_id"
$(declare -f close_notification)
close_notification "\$event_id"
EOF
    chmod +x "$close_script"

    # YAD notification icon
    yad --notification \
        --image="$NOTIFICATION_ICON" \
        --text="Reminder: $title" \
        --menu="Show details!$details_script!gtk-info|Close!$close_script!gtk-close" \
        --command="$details_script" &

    echo $! > "$TEMP_DIR/yad_pid_$event_id"
}

# Function to display event details
show_event_details() {
    local event_id="$1"
    local notification_file="$TEMP_DIR/notification_$event_id"

    if [[ -f "$notification_file" ]]; then
        local content=$(cat "$notification_file")
        local title=$(echo "$content" | cut -d'|' -f1)
        local message=$(echo "$content" | cut -d'|' -f2)

        yad --info \
            --title="Event Details" \
            --text="<b>$title</b>\n\n$message" \
            --width=400 \
            --height=200 \
            --button="Close notification:0" \
            --button="OK:1"

        if [[ $? -eq 0 ]]; then
            close_notification "$event_id"
        fi
    fi
}

# Function to close notification
close_notification() {
    local event_id="$1"
    local pid_file="$TEMP_DIR/yad_pid_$event_id"
    local notification_file="$TEMP_DIR/notification_$event_id"
    local details_script="$TEMP_DIR/show_details_$event_id.sh"
    local close_script="$TEMP_DIR/close_$event_id.sh"

    # Kill YAD process
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        kill "$pid" 2>/dev/null
        rm -f "$pid_file"
    fi

    # Remove notification file and scripts
    rm -f "$notification_file" "$details_script" "$close_script"
}

# Export functions for YAD
export -f show_event_details
export -f close_notification

# Main program loop
main_loop() {
    local processed_events=()

    echo "Starting calendar reminder monitor..."
    echo "ICS file: $ICS_FILE"
    echo "Check interval: ${CHECK_INTERVAL}s"
    echo "Reminder time: $((REMINDER_TIME/60)) minutes before event"
    echo ""

    while true; do
        local current_time=$(date +%s)
        local events_found=false

        # Parse events
        while IFS='|' read -r summary description location datetime; do
            if [[ -n "$summary" && -n "$datetime" ]]; then
                events_found=true
                local event_timestamp=$(date_to_timestamp "$datetime")
                local event_id=$(echo "${summary}_${event_timestamp}" | md5sum | cut -d' ' -f1)
                local time_diff=$((event_timestamp - current_time))

                # Check if it's time for reminder (or if event is soon and we haven't notified yet)
                if [[ $time_diff -le $REMINDER_TIME && $time_diff -gt -300 ]]; then  # Notify up to 5 minutes after event starts
                    # Check if already processed
                    local already_processed=false
                    for processed in "${processed_events[@]}"; do
                        if [[ "$processed" == "$event_id" ]]; then
                            already_processed=true
                            break
                        fi
                    done

                    if [[ "$already_processed" == false ]]; then
                        local time_left=$((time_diff / 60))
                        local notification_text="$summary"

                        if [[ -n "$location" ]]; then
                            notification_text="$notification_text\nLocation: $location"
                        fi

                        if [[ -n "$description" ]]; then
                            notification_text="$notification_text\n\n$description"
                        fi

                        notification_text="$notification_text\n\nTime: $datetime"

                        if [[ $time_diff -gt 60 ]]; then
                            notification_text="$notification_text\nTime remaining: ${time_left} minutes"
                        elif [[ $time_diff -gt 0 ]]; then
                            notification_text="$notification_text\nEvent starts in less than 1 minute!"
                        elif [[ $time_diff -ge -300 ]]; then
                            local minutes_passed=$(( (-time_diff) / 60 ))
                            if [[ $minutes_passed -eq 0 ]]; then
                                notification_text="$notification_text\nEVENT IS NOW!"
                            else
                                notification_text="$notification_text\nEvent started ${minutes_passed} minutes ago"
                            fi
                        fi

                        echo "$(date): Sending reminder: $summary"
                        show_notification "📅 Calendar Reminder" "$notification_text" "$event_id"
                        processed_events+=("$event_id")
                    fi
                fi
            fi
        done < <(parse_ics "$ICS_FILE")

        if [[ "$events_found" == false && -f "$ICS_FILE" ]]; then
            echo "$(date): No events found in $ICS_FILE"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Cleanup function
cleanup() {
    echo "Cleaning up resources..."
    # Kill all YAD processes
    for pid_file in "$TEMP_DIR"/yad_pid_*; do
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            kill "$pid" 2>/dev/null
        fi
    done

    # Remove temporary files
    rm -rf "$TEMP_DIR"
    exit 0
}

# Handle signals
trap cleanup SIGINT SIGTERM

# Check required tools
check_dependencies() {
    local missing=()

    command -v yad >/dev/null 2>&1 || missing+=("yad")
    command -v fyi >/dev/null 2>&1 || missing+=("fyi")
    command -v awk >/dev/null 2>&1 || missing+=("awk")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}"
        echo "Install them using your distribution's package manager"
        exit 1
    fi
}

# Display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Calendar reminder monitor - monitors .ics file and displays notifications
for upcoming events.

OPTIONS:
    -f, --file FILE         Path to .ics file (default: ~/calendar.ics)
    -i, --interval SECONDS  Check interval in seconds (default: 60)
    -r, --reminder MINUTES  Reminder time in minutes before event (default: 15)
    -h, --help              Display this help

EXAMPLES:
    $0                                 # Use default settings
    $0 -f ~/Documents/calendar.ics     # Use specific file
    $0 -i 30 -r 30                     # Check every 30s, remind 30min earlier

NOTES:
    - Program requires: yad, fyi, awk
    - Notification icons are displayed in panel (e.g., tint2)
    - Clicking icon shows event details
    - Program runs in background until stopped (Ctrl+C)

DEPENDENCIES:
    - yad: For panel icons and dialog boxes
    - fyi: For desktop notifications (replaces notify-send)
    - awk: For parsing .ics files

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            ICS_FILE="$2"
            shift 2
            ;;
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -r|--reminder)
            REMINDER_TIME=$((${2} * 60))
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
check_dependencies
main_loop
