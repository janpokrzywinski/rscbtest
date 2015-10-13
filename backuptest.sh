#!/bin/bash
# Script to automate troubleshooting procedure for Rackspace Cloud Backup agent and Rackspace Cloud Backups
# Jan Pokrzywinski (Rackspace UK) 2015
# Version: 1.4.2 (2015-07-01)

# Check if output is directed to file or to terminali and set variables for colors (Used to strip colors for text output)

if [ $(whoami) != "root" ]
then
    echo "ERROR: This script needs to be run as root!"
    exit 1
fi

if [ -t 1 ]
then
    ColourMag="\e[1;36m"
    ColourRed="\e[1;31m"
    ColourBlue="\e[1;34m"
    ColourGreen="\e[1;32m"
    NoColour="\e[0m"
else
    ColorMag=""
    ColourRed=""
    ColourBlue=""
    ColourGreen=""
    NoColour=""
fi

# Setup variable for a specific region in which server is located
CurrentRegion=$(xenstore-read vm-data/provider_data/region 2>&1)

# Set numbers of endpoints to resolve/ping based on CurrentRegion
if [ $CurrentRegion == 'hkg' ] || [ $CurrentRegion == 'syd' ] || [ $CurrentRegion == 'iad' ]
then
    EndpointNumber=4
elif [ $CurrentRegion == 'dfw' ] || [ $CurrentRegion == 'ord' ]
then
    EndpointNumber=3
elif [ $CurrentRegion == 'lon' ]
then
    EndpointNumber=5
else
    echo -e "$ColourRed ERROR : Cannot read the region from XenStore data!$NoColour\nIs this Rackspace Cloud Server?\nPlease check if xe-daemon is running and check if xe-linux-distribution service is set to start at boot.\n"
    echo -e "$ColourRed Test results may be inconsistent due to this!$NoColour\n"
    EndpointNumber=3
fi

# Create table to eplace veriable with correct name from API endpoints
declare -A Region
    Region[lon]="lon3"
    Region[dfw]="dfw1"
    Region[syd]="syd2"
    Region[iad]="iad3"
    Region[hkg]="hkg1"
    Region[ord]="ord1"

# Setting up endpoint hostnames for ping
if [ $CurrentRegion == 'lon' ]
then
Endpoint=(
    "api.drivesrvr.com"
    "rse.drivesrvr.com"
    "storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "snet-storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "rse.drivesrvr.co.uk"
    "api.drivesrvr.co.uk"
    "rse.$CurrentRegion.drivesrvr.com"
    )
else
Endpoint=(
    "api.drivesrvr.com"
    "rse.drivesrvr.com"
    "storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "snet-storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "rse.$CurrentRegion.drivesrvr.com"
    )
fi

# Resolve all access points for all regions
echo -e "\n$ColourMag>======== Test DNS resolution:$NoColour"
for ResNumber in $(seq 0 $EndpointNumber)
do
    host ${Endpoint[ResNumber]}
done    

# Run single ping request to each of the access points
echo -e "\n$ColourMag>======== Test ping:$NoColour"
for PingNumber in $(seq 0 $EndpointNumber)
do
    if ping -q -W3 -c1 ${Endpoint[PingNumber]} &> /dev/null
    then
        echo -e "Ping to$ColourBlue ${Endpoint[PingNumber]} $NoColour:$ColourGreen Success $NoColour"
    else
        echo -e "Ping to$ColourBlue ${Endpoint[PingNumber]} $NoColour:$ColourRed Error $NoColour"
    fi
done

# Showing network interface configuration and routes routes
echo -e "\n$ColourMag>======== Network settings:$NoColour"
    route -n
    echo
    ifconfig eth0 | head -3
    echo
    ifconfig eth1 | head -3
    echo -e "\n$ColourBlue> DNS settings (contents of resolv.conf):$NoColour"
    cat /etc/resolv.conf

# Check Backup API health status:
echo -e "\n$ColourMag>======== API Nodes status:$NoColour"
echo "Status of https://rse.drivesrvr.com/health :"
curl -s https://rse.drivesrvr.com/health
echo "Status of https://$CurrentRegion.backup.api.rackspacecloud.com/v1.0/help/apihealth :"
curl -s https://$CurrentRegion.backup.api.rackspacecloud.com/v1.0/help/apihealth
echo -e "\nStatus of https://$CurrentRegion.backup.api.rackspacecloud.com/v1.0/help/health :"
curl -s https://$CurrentRegion.backup.api.rackspacecloud.com/v1.0/help/health
echo

# Show contents from bootstrap.json (config file)
echo -e "\n$ColourMag>======== Bootstrap contents:$NoColour"
    cat /etc/driveclient/bootstrap.json

# Listing processes and checking if backup agent is present
echo -e "\n$ColourMag>======== Processes running:$NoColour"
    ps aux | grep '[d]riveclient\|[c]loudbackup-updater'
    if [ "$(pidof driveclient)" ] 
    then
        # process running
        echo -e "$ColourGreen> driveclient process present $NoColour"
    else
        echo -e "$ColourRed> driveclient service is not running! $NoColour\nIf the agent is installed and configured correctly run this:\nservice driveclient start\n"
    fi

# Location of the binary
echo -e "\n$ColourMag>======== Location of binaries (whereis):$NoColour"
    whereis driveclient
    whereis cloudbackup-updater

# Check version of driveclient
echo -e "\n$ColourMag>======== Driveclient version:$NoColour"
    driveclient --version

# Show contents of cache directory and check if lock file exists
echo -e "\n$ColourMag>======== Cache directory conents (/var/cache/driveclient/):$NoColour"
    ls -hla /var/cache/driveclient/

LockFile=/var/cache/driveclient/backup-running.lock
    if [ -f $LockFile ];
    then
        echo -e "\n$ColourRed!!! Lock File present! ($LockFile)\e$NoColour\nIf backups are stuck in queued state or showing as skipped for last few attempts follow these steps:\n1) Stop backup task in control panel\n2) Stop driveclient service\n3) Delete lock file\n4) Start driveclient service"
    fi

# Last 10 entries of log file
echo -e "\n$ColourMag>======== Last 10 log entries:$NoColour"
    tail /var/log/driveclient.log

# Checking just for log entries containing "err"
echo -e "\n$ColourMag>======== Last 5 Errors in log:$NoColour"
    grep -i err /var/log/driveclient.log | tail -5

# Show disk space and inodes
echo -e "\n$ColourMag>======== Disk space and inodes:$NoColour"
    df -h
    echo
    df -i
# Clear echo to give clean closing
echo
