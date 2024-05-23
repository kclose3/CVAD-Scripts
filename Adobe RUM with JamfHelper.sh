#!/bin/zsh

#############################################################################################################################
#
# Written by KClose
# Based on an original script by John Mahlman
#
# Purpose:  This script uses jamfhelper to show which updates are available for Adobe CC and asks
#           if they would like to install those updates.  If they choose to install updates it will begin installing updates.
#
# Setup:  It is advised that the primary policy be created to run this script at a regular interval.
#         - Suggested interval: Once per day.
#         It is also recommended that a duplicate policy be created that runs via custom trigger with an ongoing frequency.
#         - This will be the policy that is called if the user choses to defer the updates.
#
# Changelog:
# 5/6/24  - Initial Upload
#         - Added/Updated Application List
# 5/12/24 - Over the past week, I have effectively rewritten most of the UI.
#         - Additionally, both Acrobat Pro and Acrobat reader will be ignored due to failures in the install/update process.
# 5/14/24 - Added deferral option. This option simply calls a Jamf policy to run the script again.
#         - Further testing and finalization of the UI.
# 5/20/24 -	Added timestamp to deferral LaunchDaemon and added cleanup for old Daemons.
# 5/23/24 -	Remove Cancel from the initial pop-up, but added 1-Day as a deferral option.
#			Also added "FriendlyTime" for logging.
#
#############################################################################################################################

#################
### VARIABLES ###
#################

icons="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources" # MacOS system icons directory
logPath="/Library/Application Support/CustomAdobeUpdater/"
rumLog="$logPath/AdobeRUM_Updates.log"
rumPrompt="$logPath/AdobeRUM_Prompt.txt"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
rum="/usr/local/bin/RemoteUpdateManager"
jamf_bin="/usr/local/bin/jamf"
plistPal="/usr/libexec/PlistBuddy"
installRUM="${4}" # set RUM install trigger in parameter 4.
selfTrigger="${5}" # set the trigger to re-run this policy.

# if parameter 4 is not specified, use the UNT default install trigger.
if [[ -z $installRUM ]]; then
	installRUM="install.adoberum"
fi

# if parameter 5 is not specified, use the following default trigger.
if [[ -z $selfTrigger ]]; then
	selfTrigger="rum.userdeferred"
fi

#################
### FUNCTIONS ###
#################

# Function to install updates.
installUpdates ()
{
	# Retrieve Sap Title and generate a friendly name for the application to be installed.
	sapTitle="$1"
	friendlyName $sapTitle
	# Let's caffinate the mac because this can take long.
	caffeinate -d -i -m -u &
	caffeinatepid=$!
	# Displaying jamfHelper update "progress".
	progressDesc="Downloading and Installing\n  • $appTitle Update\n\nThis may take some time..."
	"$jamfHelper" -windowType hud -windowPosition ur -title "Adobe Updater" -description "$(echo "$progressDesc")" -icon "$installIcon" -button1 "Ok" -lockHUD -defaultButton 1 > /dev/null 2>&1 &
	# Force quit application in preparation for update
	echo "Attempting to quit $appTitle"  
	# Run update for the current application in the loop.
	$rum --action=install --productVersions=$sapTitle
	# Kill jamfhelper
	killall jamfHelper > /dev/null 2>&1
	# No more caffeine please. I've a headache.
	kill "$caffeinatepid"
	# exit 0
}

# Function to set up the log files.
configureLog ()
{
	# if the log directory doesn't exist, create the dir.
	if [[ ! -d "$logPath" ]]; then
		mkdir -p "$logPath"
	else
		for configLog in "$rumLog" "$rumPrompt"
		do
			# if the log file exists, clear the old log.
			if [[ -f "$configLog" ]] ; then
				rm "$configLog"
			fi
			# create a fresh log file.
			touch "$configLog"
		done
	fi
}

# Function to clean up old LaunchDaemons.
daemonCleanup ()
{
	# 	Check for old LauchDaemons and remove them.
	listPlist=($(ls -tr /Library/LaunchDaemons | grep "com.adobeupdate.deferred"))
	
	# For each Daemon found, if it's not the current (assumed running) Daemon, unload and delete it.
	#	This is to prevent premature bootout of the current Launch Daemon,
	#	which prevents the policy from properly reporting back to Jamf.
	for checkPlist in $listPlist; do
		if [[ "$checkPlist" != "${listPlist[-1]}" ]]; then
			launchctl bootout system /Library/LaunchDaemons/$checkPlist
			rm -f /Library/LaunchDaemons/$checkPlist
		fi
	done
}

# Function to generate friendly names from Adobe Sap names.
# 	$sapTitle in returns $appTitle out.
friendlyName () {
	sapTitle=$1
	case $sapTitle in
		ACR) appTitle="Camera Raw" ;;
		AEFT) appTitle="After Effects" ;;
		AICY) appTitle="InCopy" ;;
		AUDT) appTitle="Audition" ;;
		AME) appTitle="Media Encoder" ;;
		CCXP) appTitle="Creative Cloud Experience" ;;
		CHAR) appTitle="Character Animator" ;;
		DRWV) appTitle="Dreamweaver" ;;
		ESHT) appTitle="Dimension" ;;
		FLPR) appTitle="Animate" ;;
		IDSN) appTitle="InDesign" ;;
		ILST) appTitle="Illustrator" ;;
		INDS) appTitle="InDesign" ;;
		KRBG) appTitle="Bridge" ;;
		LRCC) appTitle="Lightroom" ;;
		LTRM) appTitle="Lightroom Classic" ;;
		MUSE) appTitle="Muse" ;;
		PHSP) appTitle="Photoshop" ;;
		PPRO) appTitle="Premiere Pro" ;;
		PRLD) appTitle="Prelude" ;;
		RUSH) appTitle="Premiere Rush" ;;
		SBSTA) appTitle="Substance 3D Sampler" ;;
		SBSTD) appTitle="Substance 3D Designer" ;;
		SBSTP) appTitle="Substance 3D Painter" ;;
		STGR) appTitle="Substance 3D Stager" ;;
		SPRK) appTitle="XD" ;;
	esac
}

# Function to write out a launch agent to re-run the policy at a later time.
agentSchedule () {
	delay=$1
	
	# Set the scheduled time by adding the deferral to *now*.
	now=$(date +%s)
	soon=$(($now+$delay))
	thenMinute=$(date -jf %s $soon +%M)
	thenHour=$(date -jf %s $soon +%H)
	thenDay=$(date -jf %s $soon +%d)
	thenMonth=$(date -jf %s $soon +%m)
	timeStamp=$(date -jf %s $soon +%m%d%H%M)
	
	# Define path to where the plist will write
	plistPath="/Library/LaunchDaemons/com.adobeupdate.deferred.$timeStamp.plist"
	
	# Using PlistBuddy, create the Launch Daemon.
	$plistPal -c "Add :Label string $(basename "$plistPath" | sed 's/.plist//')" "$plistPath"
	$plistPal -c "Add :ProgramArguments array" "$plistPath"
	$plistPal -c "Add :ProgramArguments: string /usr/local/bin/jamf" "$plistPath"
	$plistPal -c "Add :ProgramArguments: string policy" "$plistPath"
	$plistPal -c "Add :ProgramArguments: string -event" "$plistPath"
	$plistPal -c "Add :ProgramArguments: string $selfTrigger" "$plistPath"
	$plistPal -c "Add :StartCalendarInterval:Hour integer $thenHour" "$plistPath"
	$plistPal -c "Add :StartCalendarInterval:Minute integer $thenMinute" "$plistPath"
	$plistPal -c "Add :StartCalendarInterval:Day integer $thenDay" "$plistPath"
	$plistPal -c "Add :StartCalendarInterval:Month integer $thenMonth" "$plistPath"
	
	# Change the ownership and permissions
	chown root:wheel "$plistPath"
	chmod 644 "$plistPath"
	
	# Bootstrap it
	launchctl bootstrap system "$plistPath"
}

###################
### MAIN SCRIPT ###
###################

# RUM installed? Lets install if not.
if [[ ! -f $rum ]] ; then
	echo "Installing RUM from JSS"
	$jamf_bin policy -event "$installRUM"
	if [[ ! -f $rum ]] ; then
		echo "Couldn't install RUM! Exiting."
		exit 1
	fi
fi

# Cleanup old LaunchDaemons
daemonCleanup

# Generate RUM list
configureLog
$rum --action=list > "$rumLog"

# Check for updates, ignoring Acrobat (due to issues trying to update Acrobat via RUM), and extract the Sap Code.
rumUpdates=$(cat "$rumLog" | grep "(" | grep -v -e "Acrobat" -e "Return Code" | awk -F '[(/]' '{print $2}')

# Add all applications to be updated to an array.
rumArray=()
while IFS='\n' read -r line; do
	if [[ -z "$line" ]]; then # We were getting a false positive when the value was zero. This will check for actual data before building the array.
		break
	else
		rumArray+=( "$line" )
	fi
done < <( echo $rumUpdates )

# Check for updates and continue based on number of available updates.
if [[ ${#rumArray[@]} -lt 1 ]]; then # If there are no updates then end here.
	echo "No updates found. Exiting without proceeding."
	exit 0
else # If there are updates, prompt the user to update.
	echo "${#rumArray[@]} updates found. Proceeding to user prompt."
	
	# Build the jhc description for the user prompt.
	#   Set plurality of the description text.
	if [[ ${#rumArray[@]} == "1" ]]; then
		updNumText="is ${#rumArray[@]} Adobe Update"
		appNumText="application needs"
		instNumText="this update"
	else
		updNumText="are ${#rumArray[@]} Adobe Updates"
		appNumText="applications need"
		instNumText="these updates"
	fi
	#   Set the header text of the jhc Description.
	echo "There $updNumText available.\n\nThe following $appNumText to be updated:" > $rumPrompt
	#   Set the body text of the jhc Description including a list of all the applications that need to be updated.
	for appUpdate in "${rumArray[@]}"; do
		friendlyName $appUpdate
		echo "\t• $appTitle" >> $rumPrompt
	done
	#   Set the footer text of the jhc Description.
	echo "\nThe above $appNumText to be quit before $instNumText can be installed.\n\nWhen would you like to install $instNumText?" >> $rumPrompt
	
	# Define icons for jhc prompts - use Adobe icons if available, otherwise use Apple icons.
	if [[ -d "/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Installer.app" ]]; then
		installIcon="/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Installer.app/Contents/Resources/CreativeCloudInstaller.icns"
	else
		installIcon="$icons/Sync.icns"
	fi
	if [[ -d "/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Desktop App.app" ]]; then
		alertIcon="/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Desktop App.app/Contents/Resources/CreativeCloudApp.icns"
	else
		alertIcon="$icons/ToolbarInfo.icns"
	fi
	
	# Using all of the above information, prompt the user to see when they would like to install the updates.
	promptReponse=$("$jamfHelper" -lockHUD -showDelayOptions "0, 900, 3600, 86400" -windowType hud -button1 "Ok" -defaultButton 1 -icon "$alertIcon" -description "$(cat "$rumPrompt")" -windowPosition ur -title "Adobe Updates Available")
	
	# Record choices from the user prompt.
	userChoice=${promptReponse: -1}
	deferralTime=${promptReponse%?}
	
	if [[ "$userChoice" == "1" ]]; then # If the user said Yes - proceed to plan the updates.
		if [[ -z "$deferralTime" ]]; then # If the user did not opt to defer the updates, run the updates immediately.
			echo "User said yes, installing applications: ${rumArray[@]}."
			# Loop through all applications for update.
			for appUpdate in "${rumArray[@]}"; do
				echo "running command \"installUpdates($appUpdate)\""
				installUpdates $appUpdate
			done
			# Show an alert that updates are done.
			"$jamfHelper" -windowType hud -lockHUD -windowPosition ur -title "Adobe Updater" -description "All available updates have been installed." \
			-icon "$alertIcon" -button1 Ok -defaultButton 1
		elif [[ $deferralTime == "86400" ]]; then
			friendlyTime=$(printf '%dh:%02dm\n' $((deferralTime/3600)) $((deferralTime%3600/60)))
			echo "User chose to defer for $friendlyTime This is long enough to let Jamf handle the deferral. Exiting"
			exit 0
		else # If the user chose to defer the updates, create a Launch Daemon that will run a Jamf policy at the chosen time.
			friendlyTime=$(printf '%dh:%02dm\n' $((deferralTime/3600)) $((deferralTime%3600/60)))
			echo "User chose to defer for $friendlyTime Writing a launch agent to to handle the deferral."
			agentSchedule $deferralTime
		fi
	elif [[ "$userChoice" == "2" ]]; then # If the user said No, quit now.
		echo "User cancelled the update. Exiting."
	fi
fi

# Cleanup our temporary log files
rm -rf $logPath