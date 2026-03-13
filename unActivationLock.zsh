#!/bin/zsh

# unActivationLock
# Activation Lock / iCloud Find My Mac Removal Prompt
#
# Checks whether a Mac is Activation Locked by a user. If so, determines
# whether the currently logged-in user is the one associated with the lock
# and prompts them to disable Find My Mac.
#
# Originally authored by Brian Van Peski - macOS Adventures
# Rewritten and maintained by Branch Digital — https://branch.digital
#
########################################################################################
# Version: 2.0 | See CHANGELOG for full version history.
# Updated: 2026-03-09
########################################################################################

##############################################################
# USER INPUT
##############################################################
# Messaging
dialogTitle="Turn off Find My Mac"
dialogMessage15="This company device is currently locked to your iCloud account. Please turn off Find My Mac:\n\n1. Open System Settings and click your name at the top of the sidebar.\n2. Click iCloud, then next to Saved to iCloud, click See All.\n3. Click Find My Mac, then click Turn Off."
dialogMessage14="This company device is currently locked to your iCloud account. Please turn off Find My Mac:\n\n1. Open System Settings and click your name at the top of the sidebar.\n2. Click iCloud, then click Find My Mac.\n3. Click Turn Off next to Find My Mac."
appIcon="/System/Library/PrivateFrameworks/AOSUI.framework/Versions/A/Resources/findmy.icns"

# SwiftDialog options
swiftDialogOptions=(
  --mini
  --ontop
  --moveable
)

attempts=6      # Maximum number of prompts before giving up
wait_time=40    # Seconds to wait between prompts

# Set to 'true' to always prompt when Find My Mac is enabled,
# regardless of Activation Lock status.
DisallowFindMy=false

##############################################################
# VARIABLES
##############################################################
currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
uid=$(id -u "$currentUser" 2>/dev/null)
plist="/Users/$currentUser/Library/Preferences/MobileMeAccounts.plist"
KandjiAgent="/Library/Kandji/Kandji Agent.app"
dialogPath="/usr/local/bin/dialog"
dialogApp="/Library/Application Support/Dialog/Dialog.app"

# macOS major version — used for System Settings URL compatibility
osMajor=$(sw_vers -productVersion | cut -d. -f1)

# Select dialog message based on macOS version
if (( osMajor >= 15 )); then
    dialogMessage="$dialogMessage15"
else
    dialogMessage="$dialogMessage14"
fi

# Populated by UserLookup
FindMyUser=""
FindMyEmail=""
FindMyEnabled=""

##############################################################
# FUNCTIONS
##############################################################

LOGGING() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] UnActivationLock: ${1}"
    /usr/bin/logger -t "UnActivationLock" "${1}"
}

runAsUser() {
    if [[ -n "$currentUser" && "$currentUser" != "loginwindow" ]]; then
        launchctl asuser "$uid" sudo -u "$currentUser" "$@"
    else
        LOGGING "No user logged in — skipping user-context command."
    fi
}

getActivationLockStatus() {
    /usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | awk '/Activation Lock Status/{print $NF}'
}

openSystemSettings() {
    # macOS 13 (Ventura) and later renamed System Preferences to System Settings
    # and updated the URL scheme for iCloud preferences.
    if (( osMajor >= 13 )); then
        runAsUser open "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane" 2>/dev/null
        runAsUser osascript -e 'tell application "System Settings" to activate' 2>/dev/null
    else
        runAsUser open "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud" 2>/dev/null
        runAsUser osascript -e 'tell application "System Preferences" to activate' 2>/dev/null
    fi
}

UserLookup() {
    ## Fetch all local user accounts and find any with a Find My Mac service entry.
    ## NOTE: The plist Enabled field is NOT reliable — macOS does not always keep it
    ## in sync with the actual Find My Mac state. We use system_profiler's Activation
    ## Lock status as the source of truth and only use the plist to identify WHICH
    ## user has iCloud + Find My Mac configured.
    local USER_LIST
    USER_LIST=($(/usr/bin/dscl /Local/Default -list /Users UniqueID | /usr/bin/awk '$2 >= 500 {print $1}'))
    LOGGING "Checking Find My Mac status for users: ${USER_LIST[*]}"

    for user in "${USER_LIST[@]}"; do
        local userPlist="/Users/${user}/Library/Preferences/MobileMeAccounts.plist"
        [[ -f "$userPlist" ]] || continue

        # Check if this user has a FIND_MY_MAC service entry at all
        # Match on Name field (= "FIND_MY_MAC"), not ServiceID (= "com.apple.Dataclass.DeviceLocator")
        local servicesOutput serviceCount i serviceName hasFindMy
        servicesOutput=$(/usr/libexec/PlistBuddy -c 'print :Accounts:0:Services' "$userPlist" 2>/dev/null)
        [[ -n "$servicesOutput" ]] || continue

        serviceCount=$(echo "$servicesOutput" | grep -c "Dict {")
        serviceCount=${serviceCount:-0}

        hasFindMy="false"
        for (( i=0; i<serviceCount; i++ )); do
            serviceName=$(/usr/libexec/PlistBuddy -c "print :Accounts:0:Services:${i}:Name" "$userPlist" 2>/dev/null)
            if [[ "$serviceName" == "FIND_MY_MAC" ]]; then
                hasFindMy="true"
                break
            fi
        done

        if [[ "$hasFindMy" == "true" ]]; then
            LOGGING "User $user has Find My Mac service in iCloud account."
            FindMyUser="$user"
            FindMyEnabled="true"
            FindMyEmail=$(/usr/libexec/PlistBuddy -c 'print :Accounts:0:AccountID' "$userPlist" 2>/dev/null || echo "Unknown")
            break  # Stop at first user with Find My Mac service entry
        fi
    done
}

UserDialog() {
    local iconCMD=()
    if [[ -f "$appIcon" ]]; then
        iconCMD=(--icon "$appIcon")
    fi

    if [[ -d "$KandjiAgent" ]]; then
        /usr/local/bin/kandji display-alert --title "$dialogTitle" --message "$dialogMessage" "${iconCMD[@]}"
    elif [[ -x "$dialogPath" && -d "$dialogApp" ]]; then
        "$dialogPath" --title "$dialogTitle" --message "$dialogMessage" "${swiftDialogOptions[@]}" "${iconCMD[@]}"
    elif [[ -f "$appIcon" ]]; then
        runAsUser /usr/bin/osascript -e "display dialog \"$dialogMessage\" with title \"$dialogTitle\" with icon POSIX file \"$appIcon\" buttons {\"OK\"} default button 1 giving up after 15"
    else
        runAsUser /usr/bin/osascript -e "display dialog \"$dialogMessage\" with title \"$dialogTitle\" buttons {\"OK\"} default button 1 giving up after 15"
    fi
}

promptActivationLockLoop() {
    local dialogAttempts=0
    activationLock=$(getActivationLockStatus)

    until [[ "$activationLock" == "Disabled" ]]; do
        if (( dialogAttempts >= attempts )); then
            LOGGING "User ignored $attempts prompts. Giving up."
            exit 1
        fi
        LOGGING "Prompting '$currentUser' to disable Find My Mac (attempt $((dialogAttempts + 1)) of $attempts)..."
        openSystemSettings
        UserDialog
        sleep "$wait_time"
        (( dialogAttempts++ ))
        activationLock=$(getActivationLockStatus)
    done
}

getFindMyStatus() {
    local targetPlist="$1"
    local servicesOutput serviceCount i serviceName result
    servicesOutput=$(/usr/libexec/PlistBuddy -c 'print :Accounts:0:Services' "$targetPlist" 2>/dev/null)
    serviceCount=$(echo "$servicesOutput" | grep -c "Dict {")
    serviceCount=${serviceCount:-0}
    result="false"
    for (( i=0; i<serviceCount; i++ )); do
        serviceName=$(/usr/libexec/PlistBuddy -c "print :Accounts:0:Services:${i}:Name" "$targetPlist" 2>/dev/null)
        if [[ "$serviceName" == "FIND_MY_MAC" ]]; then
            result=$(/usr/libexec/PlistBuddy -c "print :Accounts:0:Services:${i}:Enabled" "$targetPlist" 2>/dev/null)
            break
        fi
    done
    echo "$result"
}

promptFindMyLoop() {
    local dialogAttempts=0
    FindMyEnabled=$(getFindMyStatus "$plist")

    until [[ "$FindMyEnabled" == "false" ]]; do
        if (( dialogAttempts >= attempts )); then
            LOGGING "User ignored $attempts prompts. Giving up."
            exit 1
        fi
        LOGGING "Prompting '$currentUser' to disable Find My Mac (attempt $((dialogAttempts + 1)) of $attempts)..."
        openSystemSettings
        UserDialog
        sleep "$wait_time"
        (( dialogAttempts++ ))
        FindMyEnabled=$(getFindMyStatus "$plist")
    done
}

##############################################################
# PREFLIGHT CHECKS
##############################################################

# Ensure a user is logged in before proceeding
if [[ -z "$currentUser" || "$currentUser" == "loginwindow" ]]; then
    LOGGING "No user is currently logged in. Exiting."
    exit 0
fi

# Check if Kandji Liftoff is running (device setup in progress — wait for it to finish)
if pgrep -x "Liftoff" >/dev/null 2>&1; then
    LOGGING "Liftoff is running — waiting for app installs to complete. Exiting."
    exit 0
fi

##############################################################
# MAIN
##############################################################

activationLock=$(getActivationLockStatus)
DEPStatus=$(profiles status -type enrollment 2>/dev/null | awk '/Enrolled via DEP/{print $NF}')
LOGGING "Activation Lock: $activationLock | DEP Enrolled: $DEPStatus | User: $currentUser | macOS: $(sw_vers -productVersion)"

# Perform user lookup once — results stored in FindMyUser, FindMyEmail, FindMyEnabled
UserLookup

if [[ "$activationLock" == "Enabled" ]]; then
    LOGGING "User-Based Activation Lock is enabled. Checking for a matching local user..."

    if [[ -n "$FindMyUser" ]]; then
        # A local user has the Find My Mac service — prompt the current logged-in user.
        # We don't require an exact username match because Kandji Passport can rename
        # accounts (e.g. "jsmith" → "JSmith@company.com"), leaving
        # the plist under the old username while the console user has the new one.
        if [[ "$FindMyUser" != "$currentUser" ]]; then
            LOGGING "Note: Find My account found under '$FindMyUser' ($FindMyEmail) but current user is '$currentUser' — likely a renamed/Passport account. Prompting current user."
        fi
        promptActivationLockLoop
        LOGGING "Activation Lock is now: $(getActivationLockStatus). Exiting."
        exit 0

    else
        # Activation Lock is on but no local user has a Find My token — check NVRAM
        nvramToken="absent"
        if /usr/sbin/nvram -xp 2>/dev/null | grep -q "fmm-mobileme-token-FMM"; then
            nvramToken="present"
        fi
        LOGGING "Activation Lock is enabled but no local Find My user found. NVRAM token: $nvramToken. Manual investigation required."
        exit 1
    fi

else
    # Activation Lock is not enabled
    if [[ "$DisallowFindMy" == "true" && "$FindMyUser" == "$currentUser" ]]; then
        LOGGING "DisallowFindMy is enabled. Prompting '$currentUser' ($FindMyEmail) to disable Find My Mac."
        promptFindMyLoop
    fi

    LOGGING "Activation Lock not enabled. Find My Mac status for '$currentUser': ${FindMyEnabled:-false}. Exiting."
    exit 0
fi
