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
# 5/6/24  	-	Initial Upload
#         	-	Added/Updated Application List
# 5/12/24 	-	Over the past week, I have effectively rewritten most of the UI.
#         	-	Additionally, both Acrobat Pro and Acrobat reader will be ignored due to failures in the install/update process.
# 5/14/24 	- 	Added deferral option. This option simply calls a Jamf policy to run the script again.
#         	-	Further testing and finalization of the UI.
# 5/20/24 	-	Added timestamp to deferral LaunchDaemon and added cleanup for old Daemons.
# 5/23/24 	-	Remove Cancel from the initial pop-up, but added 1-Day as a deferral option.
#				Also added "FriendlyTime" for logging.
# 5/28/24	-	Added prompt to quit each app before updating to prevent failures.
#			-	Added failure check.
# 6/3/24	-	Added some *** to a couple of comments to make them stand out better in the logs.
#			-	Filtered out Camera Raw from the search and added a line to include Camera Raw with the Adobe Photoshop updater.
# 6/5/24	-	Added 24-hour deferral count.
#				Changed deferral options to 30 minutes and 90 minutes to better accomodate user schedules.
#
#############################################################################################################################

#################
### VARIABLES ###
#################

icons="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources" # MacOS system icons directory
logPath="/Library/Application Support/CustomAdobeUpdater"
rumLog="$logPath/AdobeRUM_Updates.log"
rumPrompt="$logPath/AdobeRUM_Prompt.txt"
deferralLog="/private/var/log/rumdeferral.txt"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
rum="/usr/local/bin/RemoteUpdateManager"
jamf_bin="/usr/local/bin/jamf"
plistPal="/usr/libexec/PlistBuddy"
installRUM="${4}" # set RUM install trigger in parameter 4.
selfTrigger="${5}" # set the trigger to re-run this policy.
failCount=0

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
	# Now that we have the friendly name, if the application being updated is Photoshop, add Camera Raw to the update command.
	if [[ $sapTitle == "PSHP" ]]; then 
		sapTitle="PSHP,ACR"
	fi
	# Let's caffinate the mac because this can take long.
	caffeinate -d -i -m -u &
	caffeinatepid=$!
	# Prompting user to quit application in preparation for update. 
	if pgrep "$appTitle" > /dev/null 2>&1 # Check if the application is running.
	then # If it's running, prompt the user to quit.
		loopCounter=0
		echo "Attempting to quit $appTitle"
		# Give the user 30 seconds to acknowledge that the applicaiton needs to be closed.
		"$jamfHelper" -windowPosition ur -button1 "Quit App" -timeout 30 -icon $icons/ToolbarInfo.icns -defaultButton 1 -lockHUD -windowType hud -title "Quit Application" -description "$appTitle must be quit before proceeding." > /dev/null 2>&1
		# Attempt to quit the application cleanly.
		osascript -e 'quit app "'"$appTitle"'"'
		# If there is unsaved work, give the user another 30 seconds to save and quit.
		while pgrep "$appTitle" > /dev/null 2>&1
		do
			if [[ $loopCounter -lt 30 ]]; then
				sleep 1
				loopCounter=$(($loopCounter+1))
			else
				# User never responded, so we will skip this update for now.
				echo "$appTitle failed to close. Continuing."
				failCount=$(($failCount+1))
				return 
			fi
		done
	fi
	# Displaying jamfHelper update "progress".
	echo "Downloading and Installing\n  • $appTitle Update\n\nThis may take some time..." > $rumPrompt
	"$jamfHelper" -windowType hud -windowPosition ur -title "Adobe Updater" -description "$(cat "$rumPrompt")" -icon "$installIcon" -button1 "Ok" -lockHUD -defaultButton 1 > /dev/null 2>&1 &
	# Run update for the current application in the loop.
	if $rum --action=install --productVersions=$sapTitle; then
		echo "$appTitle updated successfully."
	else
		echo "$appTitle update failed"
		failCount=$(($failCount+1))
	fi
	# Kill jamfhelper
	killall jamfHelper > /dev/null 2>&1
	# No more caffeine please. I've a headache.
	kill "$caffeinatepid"
}

# Function to set up the log files.
configureLog ()
{
	# if the log directory doesn't exist, create the dir.
	if [[ ! -d "$logPath" ]]; then
		mkdir -p "$logPath"
	else
		for newLog in "$rumLog" "$rumPrompt"
		do
			# if the log file exists, clear the old log.
			if [[ -f "$newLog" ]] ; then
				rm "$newLog"
			fi
			# create a fresh log file.
			touch "$newLog"
		done
	fi
}

configDeferralLog ()
{
	# if the log doesn't exist, create it.
	if [[ ! -f $deferralLog ]]; then
		touch $deferralLog
		deferralCount="0"
		echo "$deferralCount" > $deferralLog
	else
		deferralCount="$(cat $deferralLog)"
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
		KBRG) appTitle="Bridge" ;;
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

# Install RUM if it is not installed already.
if [[ ! -f $rum ]] ; then
	echo "Installing RUM from JSS"
	$jamf_bin policy -event "$installRUM"
	if [[ ! -f $rum ]] ; then
		echo "Couldn't install RUM! Exiting."
		exit 1
	fi
fi

# Cleanup old LaunchDaemons.
daemonCleanup

# Generate RUM list.
echo "*** Checking for Updates. ***"
configureLog
$rum --action=list > "$rumLog"

# Check for updates, ignoring Acrobat and Camera Raw ("Acr") and extract the Sap Code.
#	- Adobe Acrobat is omitted becasue there are issues with updating all flavors of Acrobat with RUM
#	- Adobe Camera Raw is omitted becuase it cannot update if Photoshop is running - so we will pair Camera Raw with Photoshop
rumUpdates=$(cat "$rumLog" | grep "(" | grep -vi -e "Acr" -e "Return Code" | awk -F '[(/]' '{print $2}')

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
	echo "*** No updates found. Exiting without proceeding. ***"
	exitCode=0
else # If there are updates, prompt the user to update.	
	# Check for Deferral Log and grab deferral count.
	configDeferralLog

	# Begining user prompt.
	echo "*** ${#rumArray[@]} update(s) found. Prompting user to install updates. ***"
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
	echo "\nThe above $appNumText to quit before $instNumText can be installed.\n\nWhen would you like to install $instNumText?" >> $rumPrompt
	
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
	
	# Determine if 24-Hour Deferral limit of 3 has been exceeded.
	if [[ $deferralCount -le "3" ]]; then
		deferralOptions="0, 1800, 5400, 86400"
	else
		echo "*** 24-Hour Deferrals have been exceeded. ***"
		deferralOptions="0, 1800, 5400"
	fi
	
	# Using all of the above information, prompt the user to see when they would like to install the updates.
	promptReponse=$("$jamfHelper" -lockHUD -showDelayOptions "$deferralOptions" -windowType hud -button1 "Ok" -defaultButton 1 -icon "$alertIcon" -description "$(cat "$rumPrompt")" -windowPosition ur -title "Adobe Updates Available")
	
	# Record choices from the user prompt.
	userChoice=${promptReponse: -1}
	deferralTime=${promptReponse%?}
	
	if [[ "$userChoice" == "1" ]]; then # If the user said Yes - proceed to plan the updates.
		if [[ -z "$deferralTime" ]]; then # If the user did not opt to defer the updates, run the updates immediately.
			# Since the user chose to install the updates, we can clear the Deferral Count.
			rm "$deferralLog"
			echo "*** User said yes, installing applications: ${rumArray[@]}. ***"
			# Loop through all applications for update.
			for appUpdate in "${rumArray[@]}"; do
				installUpdates $appUpdate
			done
			# Show an alert that updates are done.
			if [[ $failCount == "0" ]]; then
				echo "All available updates have been installed." > $rumPrompt
				"$jamfHelper" -windowType hud -lockHUD -windowPosition ur -title "Adobe Updater" -description "$(cat "$rumPrompt")" -icon "$alertIcon" -button1 Ok -defaultButton 1 > /dev/null 2>&1
				exitCode=0
			else
				echo "Some updates may have failed.\n\nThe Adobe Updater will try again tomorrow, or you can run the updates yourself from the Adobe CC Application." > $rumPrompt
				"$jamfHelper" -windowType hud -lockHUD -windowPosition ur -title "Adobe Updater" -description "$(cat "$rumPrompt")" -icon "$alertIcon" -button1 Ok -defaultButton 1 > /dev/null 2>&1
				exitCode=1
			fi
		elif [[ $deferralTime == "86400" ]]; then
			friendlyTime=$(printf '%dh:%02dm\n' $((deferralTime/3600)) $((deferralTime%3600/60)))
			echo "*** User chose to defer for $friendlyTime. This is long enough to let Jamf handle the deferral. ***"
			echo "*** Incrementing Deferral Count and Exiting. ***"
			deferralCount=$((deferralCount+1))
			echo $deferralCount > $deferralLog
			exitCode=0
		else # If the user chose to defer the updates, create a Launch Daemon that will run a Jamf policy at the chosen time.
			friendlyTime=$(printf '%dh:%02dm\n' $((deferralTime/3600)) $((deferralTime%3600/60)))
			echo "*** User chose to defer for $friendlyTime. ***"
			echo "*** Writing a launch agent to to handle the deferral. ***"
			agentSchedule $deferralTime
		fi
	else
		echo "There was a problem."
		exitCode=1
	fi
fi

# Cleanup our temporary log files
rm -rf $logPath
exit $exitCode