#!/bin/bash
# Filename: backuptest.sh
# Script to automate troubleshooting procedure for linux of
# Rackspace Cloud Backup agent and Rackspace Cloud Backups
# Jan Pokrzywinski (Rackspace UK) 2015-2016
# Script lives here:
# https://github.com/janpokrzywinski/rscbtest
# https://community.rackspace.com/products/f/25/t/4917
Version=1.9
vDate=2016-09-27

# Check if script is executed as root, if not break
if [ $(whoami) != "root" ]
then
    echo "ERROR: This script needs to be run as root!"
    exit 1
fi

# Check if output is directed to file or to terminali and set variables 
# for colors (Used to strip colors for text output).
# This is in place in case if someone downloads this scripts and redirects
# it to the local output.
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
# This is in place as there are different endpoints for specific regions
# it is to later resolve and ping the endpoints, they will be picked from
# array in the order they are placed there, thus the number for different
# regions. To exclude endpoints from the end of the list.
# Only HKG, SYD and IAD need the rse.${Region}.drivesrvr.com
case ${CurrentRegion} in
    hkg|syd|iad)
        EndpointNumber=4
        ;;
    dfw|ord)
        EndpointNumber=3
        ;;
    lon)
        EndpointNumber=5
        ;;
    *)
        EndpointNumber=3
        echo -e """
${ColourRed}ERROR: Cannot read the region from XenStore data!${NoColour}
Is this Rackspace Cloud Server?
Please check if xe-daemon is running and check if xe-linux-distribution
services are set to start at boot

        """
        ;;
esac

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
    "storage101.${Region[${CurrentRegion}]}.clouddrive.com"
    "snet-storage101.${Region[${CurrentRegion}]}.clouddrive.com"
    "rse.drivesrvr.co.uk"
    "api.drivesrvr.co.uk"
    )
else
Endpoint=(
    "api.drivesrvr.com"
    "rse.drivesrvr.com"
    "storage101.${Region[${CurrentRegion}]}.clouddrive.com"
    "snet-storage101.${Region[${CurrentRegion}]}.clouddrive.com"
    "rse.${CurrentRegion}.drivesrvr.com"
    )
fi

# Functions for printing of headers
print_header () {
    echo -e "\n${ColourMag}###>========> $1:${NoColour}"
}

print_subheader () {
    echo -e "\n${ColourBlue}=> $1 :${NoColour}"
}

print_warning () {
    echo -e "\n${ColourRed}!!! WARNING: $1 !!!${NoColour}"
}

# Basis system information and execution date
print_header "System information"
    echo -e """Running kernel                 :${ColourYellow} $(uname -a) ${NoColour}
Region pulled from XenStore    :${ColourYellow} ${CurrentRegion} ${NoColour}
Instance UUID from XenStore    :${ColourYellow} $(xenstore-read name) ${NoColour}
Script version                 :${ColourYellow} ${Version} (${vDate})${NoColour}
Runlevel                       :${ColourYellow} $(runlevel) ${NoColour}
System date and time           :${ColourYellow} $(date) ${NoColour}"""

# Resolve all access points for all regions
print_header "Test DNS resolution"
for ResolveNumber in $(seq 0 ${EndpointNumber})
do
    echo -en "${Endpoint[ResolveNumber]}"
    LineNum=$(expr 45 - ${#Endpoint[ResolveNumber]})
    for i in $(seq 1 ${LineNum})
        do
            echo -en " "
        done
    echo -en ": ${ColourYellow}"
    getent ahosts ${Endpoint[ResolveNumber]} | tac \
    | awk '/RAW/ {print $1}' | sed ':a;N;$!ba;s/\n/     /g'
    echo -en "${NoColour}"
    LineNum=0
done    

# Run single ping request to each of the access points
print_header "Test ping response from endpoints"
for PingNumber in $(seq 0 $EndpointNumber)
    do
        if ping -q -W4 -c1 ${Endpoint[PingNumber]} &> /dev/null
        then
            PingStatus="${ColourGreen}Success${NoColour}"
        else
            PingStatus="${ColourRed}Error${NoColour}"
        fi
        echo -en "Ping to${ColourBlue} ${Endpoint[PingNumber]} ${NoColour}"
        LineNum=$(expr 36 - ${#Endpoint[PingNumber]})
        for i in $(seq 1 ${LineNum})
            do
                echo -en " "
            done
        echo -e ": ${PingStatus}"
    done

# Showing network interface configuration and routes routes
print_header "Network settings"
    route -n
    # this one grabs the gateway used for ServiceNet
    RouteGW=$(route -n | awk '/10.208.0.0/ {print $2}')
    if [ -z "$RouteGW" ]
    then
        print_warning "Missing route for ServiceNet"
        echo "If this server was created before june 2013 please check this article:"
        echo "https://support.rackspace.com/how-to/updating-servicenet-routes-on-cloud-servers-created-before-june-3-2013/"
        echo "It can also mean that ServiceNet network is not attached at all or is attached in non default order to the server."
    fi

    AddrDirs=$(ls -d /sys/class/net/eth*)
    for Iface in $(echo "${AddrDirs}" | cut -d "/" -f5)
    do
        print_subheader "${Iface} configuration on the system"
        ifconfig $Iface
        XSIfaceMAC=$(cat /sys/class/net/${Iface}/address | tr -d ':' | tr '[:lower:]' '[:upper:]')
        print_subheader "${Iface} configuration in XenStore data"
        xenstore-read vm-data/networking/${XSIfaceMAC}
    done

    print_subheader "ARP table"
    arp
    print_subheader "DNS settings (contents of resolv.conf)"
    cat /etc/resolv.conf

# Check Backup API health status:
print_header "API Nodes status"
    print_subheader "Status of https://rse.drivesrvr.com/health"
    curl -s "https://rse.drivesrvr.com/health"
    print_subheader "Status of https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/apihealth"
    curl -s "https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/apihealth"
    echo
# Commenting out below as it gives error response, need to confirm status of
# this healthcheck
#    print_subheader "Status of https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/health"
#    curl -s "https://${CurrentRegion}.backup.api.rackspacecloud.com/v1.0/help/health"
#    echo

# Show contents from bootstrap.json (config file)
BootstrapFile=/etc/driveclient/bootstrap.json
print_header "Bootstrap contents (${BootstrapFile})"
    if [ -e ${BootstrapFile} ]
    then
        #cat ${BootstrapFile}
        grep --color -i -E '^|Username|AgentId' ${BootstrapFile}
        echo
    else
        print_warning "Missing agent configuration file (${BootstrapFile})"
        echo "Was the configuration of the backup ran on the server?"
        echo "To run setup after installation execute this:"
        echo "driveclient --configure"
        echo
    fi

# Listing processes and checking if backup agent is present
print_header "Relevant processes"
    ps aux | head -1
    ps aux | grep '[d]riveclient\|[c]loudbackup-updater\|[n]ova-agent\|[x]e-daemon'
    echo
    if [ "$(pidof driveclient)" ] 
    then
        # process running
        echo -e "${ColourGreen}> driveclient process present (Backup Service is running) ${NoColour}"
    else
        print_warning "driveclient service is not running"
        echo "If the agent is installed and configured correctly run this:"
        echo "service driveclient start"
        echo
    fi
    if [ "$(pidof nova-agent)" ]
    then
        NovaRunning=true
    else
        print_warning "nova-agent service is not running"
        echo "Please check the /var/nova-agent.log for more details and attempt to start it with:"
        echo "service nova-agent start"
        echo
    fi

# Location of the binary
print_header "Location of binaries (whereis)"
    whereis driveclient
    whereis cloudbackup-updater

# Check version of driveclient
print_header "Driveclient version"
    driveclient --version

# Check if the cache directory exists and if so, check its contents.
CacheDir=/var/cache/driveclient
print_header "Cache directory contents (${CacheDir})"
if [ -d "${CacheDir}" ]
then
    ls -hla ${CacheDir}
else
    print_warning "Cache Directory not present"
    echo "Is the agent installed?"
    echo "Was the agent started for the first time?"
    echo
fi

# This was code for old versions of backup agent for bug which should not
# be causing any issues nowadays. Still good to verify if lock is there.
LockFile=/var/cache/driveclient/backup-running.lock
    if [ -f ${LockFile} ];
    then
        print_warning "Lock file present (${LockFile})"
        echo "If backups are stuck in queued state or showing as skipped for last few attempts follow these steps:"
        echo "1) Stop backup task in control panel"
        echo "2) Stop driveclient service"
        echo "3) Delete lock file"
        echo "4) Start driveclient service"
    fi

# Set variable for lock file and check if it exists
LogFile=/var/log/driveclient.log
if [ -a "${LogFile}" ]
then
    # Last 10 entries of log file
    print_header "Last 15 lines from the log file (${LogFile})"
        tail -15 ${LogFile}
        print_subheader "Number of entries with today's date"
        grep -c $(date +%Y-%m-%d) ${LogFile}
        print_subheader "Size of log file (bytes)"
        stat --printf="%s" ${LogFile}
        echo

    # Checking just for log entries containing "err"
    print_header "Last 10 Errors in log file (${LogFile})"
        grep -i err ${LogFile} | tail -10
else
    print_header "Checking log file presence (${LogFile})"
        print_warning "Log file does not exist"
        echo "Is the agent installed? Was it started for the first time?"
        echo "Check if disk is not full or in read only state"
fi

# Show disk space and inodes
print_header "Disk space left, inodes and mount-points"
    df -h
    echo
    df -i
    print_subheader "Mount points"
    mount | column -t

# Display memory nformation
print_header "Memory usage information"
    free

# Clear echo to give clean closing
echo
