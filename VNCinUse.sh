#!/bin/bash

#########################################################################################################################
#
# VNC Checker written by Austin Leath and KClose.
# Checks for VNC connection and triggers cleanup scripts if VNC was only recently disconnected.
# This script should be run on a timed cycle with a launch daemon.
#
# Updated 01/24/2022:	Check *only* connecttions from subnet 129.120.207.*
#						This is to ignore any and any management connections that may be made (ARD, ScreenSharing, etc.)
#						Also added IP reporting to the switchfile to check for unexpected connections.
#
# ToDo: move subnet to a variable for future, wider use applications.
#
#########################################################################################################################

### NECESSARY FUNCTIONS ###

# Function to see if VNC is currently in use. This simply reports a true/false response.
#	If using this script on another subnet, be sure to change the the last grep option accordingly.
function checkvncuse() {
	inuse=$(netstat -vanp tcp | grep 5900 | grep ESTABLISHED | awk '{print $5}' | grep 129.120.207);

	if [ -n "$inuse" ];
		then
    		#VNC in use. return 1
        	return 1
  		else
    		#VNC not in use. return 0
    		return 0
  	fi
}

# Function to write out a switch file to record current state.
switchfile() {

	# Collect variables for switch.
	vncstate=$1
	timestamp=$(date)
    
	# Write the result to the switch file.
	echo "writing output to switch file."
	echo $timestamp " - " $vncstate >> /tmp/VNCSwitch.txt
}

### MAIN SCRIPT ###

# Create Switch File if it doesn't already exist. Otherwise the tail check will fail.
if [ ! -f /tmp/VNCSwitch.txt ]; then
	echo "switch file not found. creating switch file."
	touch /tmp/VNCSwitch.txt
	switchfile "New Switchfile."
fi

# Run function "checkvncuse" and use the boolean return to determine actions.
#	We are  *only* looking for changes in state.
#	If VNC is "not in use", then we only care if it was previously "in use";
#		in which case we register that as a change and perform the approrpriate cleanup.
#
#	If VNC is "in use", then we only care if it was previously "not in use";
#		in which case we register that as a change, but do nothing else.

if checkvncuse "$notinuse";
	then
		if (tail -n 1 /tmp/VNCSwitch.txt | grep 'VNC in use.');
			then
				echo "vnc recently in use. running disconnect scripts and writing to switch file."
				/usr/local/jamf/bin/jamf policy -event cvad.guacdisconnect
				switchfile "VNC not in use."
		fi	
	else
		if (tail -n 1 /tmp/VNCSwitch.txt | grep 'VNC not in use.') || (tail -n 1 /tmp/VNCSwitch.txt | grep 'New Switchfile.');
			then
				connectedip=$(netstat -vanp tcp | grep 5900 | grep ESTABLISHED | awk '{print $5}')
				echo "vnc in use from writing to switch file."
				switchfile "VNC in use. Connected IP is $connectedip."
		fi
fi

exit 0