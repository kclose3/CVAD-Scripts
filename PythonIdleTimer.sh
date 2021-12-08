#!/bin/bash

###########################################################################################
#
# IdleTimer written by KClose. 
# Last updated: April 2, 2020
#
# IdleTimer leverages Python and Quartz to get the actual idle time of a computer.
# Unlike the BASH altternative, this function works regardless of local or remote activity.
# Results will be acurate to +- 5 seconds as it takes a second for Python to run.
# 
###########################################################################################

echo "Getting idle time from Python."

# Use Python to get the actual idle time. 

# Define the IdleTime variable by running an embedded Python script (EOF - EOF)
IdleTime=$(python - << EOF

# Importing necessary functions from Quarts CoreGraphics and SystemEvents
from Quartz.CoreGraphics import *
NX_ALLEVENTS = int(4294967295)  # 32-bits, all on.

# Build the function to get actual Idle Time
def getIdleTime():
    """Get number of seconds since last user input"""
    idle = CGEventSourceSecondsSinceLastEventType(1, NX_ALLEVENTS)
    return idle

# Run Idletime Function
idle = getIdleTime()

# Return idle time
print(idle)

EOF
)

echo "IdleTimer Returned " $IdleTime

exit 0