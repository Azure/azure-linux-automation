#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

#######################################################################
#
# performance_mc.sh
#
# Description:
#     This tool uses the memslap to Load testing and benchmarking a server
#     More info : http://docs.libmemcached.org/bin/memaslap.html
#
#
# In general the script does the following:
#
# 1.Install memcached server on mentioned servers and starts memcached server service.
# 2.Benchmarks mem servers with memslap tool.
#
# Parameters:
# MC_VERSION=1.4.25
# MC_SERVERS="Server1:11211,Server2:11211"
# MC_CONCURRENCY=10
# MC_EXECUTE_NUMBER=10000
# MC_INITIAL_LOAD=1000
#######################################################################



ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
ICA_TESTFAILED="TestFailed"

#
# Function definitions
#
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` ": ${1}"
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
#
# LinuxRelease()
#
#######################################################################
LinuxRelease()
{
    DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`

    case $DISTRO in
        *buntu*)
            echo "UBUNTU";;
        Fedora*)
            echo "FEDORA";;
        CentOS*)
            echo "CENTOS";;
        EulerOS*)
            echo "EULEROS";;
        *SUSE*)
            echo "SLES";;
        Red*Hat*)
            echo "RHEL";;
        Debian*)
            echo "DEBIAN";;
    esac
}


######################################################################
#
#  Description:
#    Perform distro specific memcached configuratoin and tool installation steps 
#    and then run the benchmark tool
#
#######################################################################
ConfigUbuntuMemC()
{
    #
    # Note: A number of steps will use SSH to issue commands to the
    #       MC_SERVER.  This requires that the SSH keys be provisioned
    #       in advanced, and strict mode be disabled for both the SSH
    #       server and client.
    #

    LogMsg "Info: Running Ubuntu Config on client VM."
    LogMsg "Checking if memcached is installed or not.."
    memcslapInstalled=`which memcslap`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing memcslap"
        apt-get -y install libmemcached-tools
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install memcslap"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi        
        LogMsg "memcslap installed on client."
    fi
    arr=$(echo $MC_SERVERS | tr "," "\n")    
    for MCS in $arr
    do
        currentServer=${MCS/:11211/}
		LogMsg "Info: -----------------------------------------"
		LogMsg "Info: memcached server installation on server ${currentServer}"
		ssh root@${currentServer} "apt-get install -y memcached"
        ssh root@${currentServer} "sed --in-place -e 's/-l 127.0.0.1//g' /etc/memcached.conf"
        ssh root@${currentServer} "service memcached restart"
        if [ $? -ne 0 ]; then
            msg="Error: Unable to install package to server ${currentServer}"
            LogMsg "${msg}"
            echo "${msg}" >> ./summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        LogMsg "Info: memcached Server started successfully on ${currentServer}"

    done
}

ConfigRHELMemC()
{
    LogMsg "Info: Running CENTOS/EULEROS/RHEL Config on client VM."
    LogMsg "Checking if memcached is installed or not.."
    memslap --help > /dev/null
    if [ $? -ne 0 ]; then
        LogMsg "Installing memslap"
        yum install -y libmemcached
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install memcslap"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi        
        LogMsg "memslap installed on client."
    fi
    arr=$(echo $MC_SERVERS | tr "," "\n")    
    for MCS in $arr
    do
        currentServer=${MCS/:11211/}
		LogMsg "Info: -----------------------------------------"
		LogMsg "Info: memcached server installation on server ${currentServer}"
		ssh root@${currentServer} "yum install -y memcached"
        ssh root@${currentServer} "service memcached restart"
        if [ $? -ne 0 ]; then
            msg="Error: Unable to install package to server ${currentServer}"
            LogMsg "${msg}"
            echo "${msg}" >> ./summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
        LogMsg "Info: memcached Server started successfully on ${currentServer}"

    done
}

ConfigRHELMemSlap()
{
    #
    # Note: MemSlap is client for memcached to benchmark memcached server. 
    #        This is long running client so far.
    #

    LogMsg "Info: Running RHEL"    
    LogMsg "Info: -----------------------------------------"
    LogMsg "Info: memslap installation"
    LogMsg "Info: Installing required packages first"
    yum install -y wget gcc make gcc-c++
    if [ $? -ne 0 ]; then
        msg="Error: Unable to install client packages"
        LogMsg "${msg}"
        echo "${msg}" >> ./summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    
    LogMsg "Info: Download memslap package"
    pkg=(`ssh root@${SERVER} "ls /root/ | grep ${MEMSLAP_VERSION}"`)
    echo $pkg
    if [ -z "$pkg" ]; then
        LogMsg "Downloading memslap package ${MEMSLAP_VERSION}"
        #exit 1    
            wget https://launchpad.net/libmemcached/1.0/1.0.18/+download/libmemcached-1.0.18.tar.gz
            if [ $? -ne 0 ]; then
                    msg="Error: Unable to download memslap package"
                    LogMsg "${msg}"
                    echo "${msg}" >> ./summary.log
                    UpdateTestState $ICA_TESTFAILED
                    exit 1
            fi    
    fi

    LogMsg "Info: Untar and Config ZK server"
    tar -xvzf libmemcached-1.0.18.tar.gz
    cd libmemcached-1.0.18/
    ./configure
    make 
    make install
    
    if [ $? -ne 0 ]; then
                msg="Error: Unable install memslap"
                LogMsg "${msg}"
                echo "${msg}" >> ./summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 1
        fi
    LogMsg "Info: memslap client setup successfully"
}

#######################################################################
#
# Main script body
#
#######################################################################

cd ~
UpdateTestState $ICA_TESTRUNNING
LogMsg "Starting test"

#
# Delete any old summary.log file
#
LogMsg "Cleaning up old summary.log"
if [ -e ~/summary.log ]; then
    rm -f ~/summary.log
fi

touch ~/summary.log

#
# Source the constants.sh file
#
LogMsg "Sourcing constants.sh"
if [ -e ~/constants.sh ]; then
    . ~/constants.sh
else
    msg="Error: ~/constants.sh does not exist"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure the required test parameters are defined
#

if [ "${MC_VERSION:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the MC_VERSION test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${MC_SERVERS:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the MC_SERVER test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${MC_CONCURRENCY:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the MC_CONCURRENCY test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    MC_CONCURRENCY=100
fi

if [ "${MC_EXECUTE_NUMBER:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the MC_EXECUTE_NUMBER test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    MC_EXECUTE_NUMBER=10000
fi

if [ "${MC_INITIAL_LOAD:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the MC_INITIAL_LOAD test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    MC_INITIAL_LOAD=10000
fi

LogMsg "Info: Test run parameters"
echo "MC_VERSION        = ${MC_VERSION}"
echo "MC_SERVERS        = ${MC_SERVERS}"
echo "MC_CONCURRENCY    = ${MC_CONCURRENCY}"
echo "MC_EXECUTE_NUMBER = ${MC_EXECUTE_NUMBER}"
echo "MC_INITIAL_LOAD   = ${MC_INITIAL_LOAD}"

#
# Configure MC server - this has distro specific behaviour
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "EULEROS" | "RHEL")
        ConfigRHELMemC
		testString="memslap --servers=${MC_SERVERS} --concurrency=${MC_CONCURRENCY} --execute-number=${MC_EXECUTE_NUMBER} --initial-load=${MC_INITIAL_LOAD} --flush"
    ;;
    "UBUNTU")
        ConfigUbuntuMemC
		testString="memcslap --servers=${MC_SERVERS} --concurrency=${MC_CONCURRENCY} --execute-number=${MC_EXECUTE_NUMBER} --initial-load=${MC_INITIAL_LOAD} --flush"
    ;;
    "DEBIAN")
		LogMsg "Debian distro not yet supported"
        #ConfigDebianMemC
    ;;
    "SLES")
		LogMsg "SLES distro not yet supported"
        #ConfigSlesMemC        
    ;;
     *)
        msg="Error: Distro '${distro}' not supported"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 1
    ;; 
esac

LogMsg "Running memslap tests with cmd: ${testString}"
eval $testString
if [ $? -ne 0 ]; then
    msg="Error: Error in running tests"
    LogMsg "${msg}"
    echo "${msg}" >> ./summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# If we made it here, everything worked.
# Indicate success
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0
