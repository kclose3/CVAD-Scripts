#!/bin/zsh

#################################################################################################
#
# Nudge Deferral Check and Count
# Created by: KClose (with assistance from ChatGPT)
#
# This script performs two functions. It checks for the number and date of Nudge Deferrals,
# but also clears the nudge.log whenever an OS update is detected.
#
# Changelog
# 2025-10-20    -   Updated to zsh and standardized variable formats.
#
#################################################################################################

### VARIABLES ###

userHome=$(dscl . -read /Users/$(stat -f%Su /dev/console) NFSHomeDirectory | awk '{print $2}')
nudgeApp="/Applications/Utilities/Nudge.app"
nudgePlist="$userHome/Library/Preferences/com.github.macadmins.Nudge.plist"
currentOS=$(sw_vers -productVersion 2>/dev/null)

### FUNCTIONS ###

# Function to compare two macOS version numbers
compareOS() {
    local curOS="$1"
    local minOS="$2"
    local -a a1=() a2=()
    local i n1 n2
    
    [[ -z "$curOS" ]] && return 1
    [[ "$minOS" == "none" || -z "$minOS" ]] && return 1
    
    # Split version strings into arrays
    IFS='.' a1=(${(s:.:)curOS})
    IFS='.' a2=(${(s:.:)minOS})
    
    # Compare each numeric segment
    for ((i = 1; i <= ${#a1[@]} || i <= ${#a2[@]}; i++)); do
        n1=${a1[i]:-0}
        n2=${a2[i]:-0}
        ((10#$n1 > 10#$n2)) && return 0   # current > minimum
        ((10#$n1 < 10#$n2)) && return 1   # current < minimum
    done
    
    return 0  # equal
}

### MAIN SCRIPT ###

# Check for Nudge installation.
if [[ ! -d "$nudgeApp" ]]; then
    echo "<result>N/A</result>"
    exit 0
fi

# Read Nudge Plist to get MinimumOSVersion.
if [[ -f "$nudgePlist" ]]; then
    minimumOS=$(defaults read "$nudgePlist" requiredMinimumOSVersion 2>/dev/null || echo "none")
else
    minimumOS="none"
fi

# Check if Current OS Version is the same or newer than MinimumOSVersion.
if compareOS "$currentOS" "$minimumOS"; then
    # OS version is up to date, clear nudge.log.
    if [[ -f "/var/log/nudge.log" ]]; then
        > /var/log/nudge.log
    fi
    echo "<result>Deferrals: 0 | Last Deferral: none</result>"
    exit 0
else
    if [[ -f "$nudgePlist" ]]; then
        # Read plist values.
        user_deferrals=$(defaults read "$nudgePlist" userDeferrals 2>/dev/null || echo 0)

        # Get last modified date and format nicely.
        plist_mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S %z" "$nudgePlist" 2>/dev/null)
        if [[ -n "$plist_mtime" ]]; then
            formatted_date=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$plist_mtime" "+%b %d %Y, %I:%M %p" 2>/dev/null)
            [[ -z "$formatted_date" ]] && formatted_date="$plist_mtime"
        else
            formatted_date="none"
        fi

        echo "<result>Deferrals: $user_deferrals | Last Deferral: $formatted_date</result>"
    else
        echo "<result>Deferrals: 0 | Last Deferral: none</result>"
    fi
fi
