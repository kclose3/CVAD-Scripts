#!/bin/bash

#################################################################################################
#
# VNC Checker written by Austin Leath and KClose.
# Checks for VNC connection and triggers cleanup scripts if VNC was only recently disconnected.
# This script should be run on a timed cycle with a launch daemon.
#
#################################################################################################

### NECESSARY FUNCTIONS ###

# Function to see if VNC is currently in use. This simply reports a true/false response.
function checkvncuse() {
#  inuse=$(netstat -vanp tcp | grep 5900 | grep ESTABLISHED);
# testing function for false
inuse=""

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
    
    # Report to Install Log.
	echo $timestamp " - " $vncstate >> /tmp/VNCSwitch.txt
}

### MAIN SCRIPT ###

# Create Switch File if it doesn't already exist. Otherwise the tail check will fail.
if [ ! -f /tmp/VNCSwitch.txt ]; then
	touch /tmp/VNCSwitch.txt
fi

if checkvncuse "$notinuse"; 
	then
		if (tail -n 1 /tmp/VNCSwitch.txt | grep 'VNC in use.');
			then
				echo "Running disconnect scripts."
				switchfile "VNC Not in Use."
			else
				echo "Do nothing."	
				switchfile "VNC Not in Use."
		fi	
	else
		switchfile "VNC in use."
		echo "VNC in use."
fi

exit 0