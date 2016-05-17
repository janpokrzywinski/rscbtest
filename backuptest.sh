#!/bin/bash
# Script to automate troubleshooting procedure for Rackspace Cloud Backup agent and Rackspace Cloud Backups
# Jan Pokrzywinski (Rackspace UK) 2015
Version=1.7
vDate=2016-05-17

# Check if script is executed as root, if not break
if [ $(whoami) != "root" ]
then
    echo "ERROR: This script needs to be run as root!"
    exit 1
fi

# Check if output is directed to file or to terminali and set variables for colors (Used to strip colors for text output)
if [ -t 1 ]
then
    ColourMag="\e[1;36m"
    ColourRed="\e[1;31m"
    ColourBlue="\e[1;34m"
    ColourGreen="\e[1;32m"
    ColourYellow="\e[1;33m"
    NoColour="\e[0m"
else
    ColorMag=""
    ColourRed=""
    ColourBlue=""
    ColourGreen=""
    ColourYellow=""
    NoColour=""
fi

# Setup variable for a specific region in which server is located
CurrentRegion=$(xenstore-read vm-data/provider_data/region 2>&1)

# Set numbers of endpoints to resolve/ping based on CurrentRegion
if [ ${CurrentRegion} == 'hkg' ] || [ ${CurrentRegion} == 'syd' ] || [ ${CurrentRegion} == 'iad' ]
then
    EndpointNumber=4
elif [ ${CurrentRegion} == 'dfw' ] || [ ${CurrentRegion} == 'ord' ]
then
    EndpointNumber=3
elif [ ${CurrentRegion} == 'lon' ]
then
    EndpointNumber=5
else
    echo -e "${ColourRed}ERROR : Cannot read the region from XenStore data!${NoColour}\nIs this Rackspace Cloud Server?\nPlease check if xe-daemon is running and check if xe-linux-distribution service is set to start at boot.\n"
    echo -e "${ColourRed}Test results may be inconsistent due to this!${NoColour}\n"
    EndpointNumber=3
fi

# Create table to replace veriable with correct name from API endpoints
declare -A Region
    Region[lon]="lon3"
    Region[dfw]="dfw1"
    Region[syd]="syd2"
    Region[iad]="iad3"
    Region[hkg]="hkg1"
    Region[ord]="ord1"

# Setting up endpoint hostnames for ping
if [ ${CurrentRegion} == 'lon' ]
then
Endpoint=(
    "api.drivesrvr.com"
    "rse.drivesrvr.com"
    "storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "snet-storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "rse.drivesrvr.co.uk"
    "api.drivesrvr.co.uk"
    "rse.${CurrentRegion}.drivesrvr.com"
    )
else
Endpoint=(
    "api.drivesrvr.com"
    "rse.drivesrvr.com"
    "storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "snet-storage101.${Region[$CurrentRegion]}.clouddrive.com"
    "rse.${CurrentRegion}.drivesrvr.com"
    )
fi

# Functions for printing of headers
print_header () {
    echo -e "\n${ColourMag}>======== $1:${NoColour}"
}

print_subheader () {
    echo -e "\n${ColourBlue}=> $1 :${NoColour}"
}

# Basis system information and execution date
print_header "System information"
    echo -e "Running kernel:${ColourYellow} $(uname -a) ${NoColour}"
    echo -e "Region pulled from XenStore:${ColourYellow} ${CurrentRegion} ${NoColour}"
    echo -e "Instance UUID from XenStore:${ColourYellow} $(xenstore-read name) ${NoColour}"
    echo -e "Script version:${ColourYellow} ${Version} ${NoColour}"
    echo -e "Runlevel :${ColourYellow} $(runlevel) ${NoColour}"
    echo -e "System date and time:${ColourYellow} $(date) ${NoColour}"

# Resolve all access points for all regions
#echo -e "\n${ColourMag}>======== Test DNS resolution:${NoColour}"
print_header "Test DNS resolution"
for ResNumber in $(seq 0 ${EndpointNumber})
do
    host ${Endpoint[ResNumber]}
done    

# Run single ping request to each of the access points
print_header "Test ping response from endpoints"
for PingNumber in $(seq 0 $EndpointNumber)
    do
        if ping -q -W3 -c1 ${Endpoint[PingNumber]} &> /dev/null
        then
            echo -e "Ping to${ColourBlue} ${Endpoint[PingNumber]} ${NoColour}:${ColourGreen} Success ${NoColour}"
        else
            echo -e "Ping to${ColourBlue} ${Endpoint[PingNumber]} ${NoColour}:${ColourRed} Error ${NoColour}"
        fi
    done

# Showing network interface configuration and routes routes
print_header "Network settings"
    route -n
    # this one grabs the gateway used for ServiceNet
    RouteGW=$(route -n | awk '/10.208.0.0/ {print $2}')
    echo
    ifconfig eth0
    echo
    ifconfig eth1
    print_subheader "ARP table"
    arp
    print_subheader "DNS settings (contents of resolv.conf)"
    cat /etc/resolv.conf
    for interface in $(xenstore-ls vm-data/networking | awk '{print $1}')
        do 
            #echo -e "${ColourBlue}> Xenstore Data for Interface ${interface} :${NoColour}"
            print_subheader "Xestore data for interface ${Interface}"
            xenstore-read vm-data/networking/${interface}
        done
    if [ -z "$RouteGW" ]
    then
        echo -e "\n${ColourRed}!!! WARNING: Missing route for ServiceNet!${NoColour} \nIf this server was created before june 2013 please check this article:"
        echo "http://www.rackspace.com/knowledge_center/article/updating-servicenet-routes-on-cloud-servers-created-before-june-3-2013"
        echo -e "\nIt can also mean that ServiceNet network is not attached at all or is attached in non default order to the server."
    fi

# Check Backup API health status:
print_header "API Nodes status"
    print_subheader "Status of https://rse.drivesrvr.com/health"
    curl -s "https://rse.drivesrvr.com/health"
    print_subheader "Status of https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/apihealth"
    curl -s "https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/apihealth"
    print_subheader "Status of https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/health"
    curl -s "https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/health"
    echo

# Show contents from bootstrap.json (config file)
BootstrapFile=/etc/driveclient/bootstrap.json
print_header "Bootstrap contents (${BootstrapFile})"
    if [ -e ${BootstrapFile} ]
    then
        cat ${BootstrapFile}
        echo
    else
        echo -e "\n${ColourRed}!!! WARNING: Missing agent configuration file (${BootstrapFile})!${NoColour}\nWas the configuration of the backup ran on the server? To run setup after installation execute this:\ndriveclient --configure\n"
    fi

# Listing processes and checking if backup agent is present
print_header "Relevant processes"
    ps aux | head -1
    ps aux | grep '[d]riveclient\|[c]loudbackup-updater\|[n]ova-agent\|[x]e-daemon'
    if [ "$(pidof driveclient)" ] 
    then
        # process running
        echo -e "${ColourGreen}> driveclient process present ${NoColour}"
    else
        echo -e "${ColourRed}!!! WARNING: driveclient service is not running! ${NoColour}\nIf the agent is installed and configured correctly run this:\nservice driveclient start\n"
    fi
    if [ "$(pidof nova-agent)" ]
    then
        NovaRunning=true
    else
        echo -e "${ColourRed}!!! WARNING: nova-agent service is not running! ${NoColour}\nPlease check the /var/nova-agent.log for more details and attempt to start it with:\nservice nova-agent start\n"
    fi

# Location of the binary
print_header "Location of binaries (whereis)"
    whereis driveclient
    whereis cloudbackup-updater

# Check version of driveclient
print_header "Driveclient version"
    driveclient --version

# Show contents of cache directory and check if lock file exists
print_header "Cache directory contents (/var/cache/driveclient/)"
    ls -hla /var/cache/driveclient/

LockFile=/var/cache/driveclient/backup-running.lock
    if [ -f ${LockFile} ];
    then
        echo -e "\n${ColourRed}!!! WARNING: Lock File present (${LockFile})\e${NoColour}\nIf backups are stuck in queued state or showing as skipped for last few attempts follow these steps:\n1) Stop backup task in control panel\n2) Stop driveclient service\n3) Delete lock file\n4) Start driveclient service"
    fi

LogFile=/var/log/driveclient.log
# Last 10 entries of log file
print_header "Last 15 entries from the log file (${LogFile})"
    tail -15 ${LogFile}
    print_subheader "Number of entries with today's date"
    grep -c $(date +%Y-%m-%d) ${LogFile}

# Checking just for log entries containing "err"
print_header "Last 10 Errors in log file (${LogFile})"
    grep -i err ${LogFile} | tail -10

# Show disk space and inodes
print_header "Disk space left, inodes and mount-points"
    df -h
    echo
    df -i
    echo
    mount | column -t

# Display memory information
print_header "Memory usage information"
    free

# Clear echo to give clean closing
echo
