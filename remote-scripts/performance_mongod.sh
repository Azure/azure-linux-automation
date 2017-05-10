#!/bin/bash

#######################################################################
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
#######################################################################

#######################################################################
#
# performance_mongodb.sh
#
# Description:
#    Install and configure mongodb so the mongoperf benchmark can
#    be run.  This script needs to be run on single VM.
#
#    mongo perf needs Java runtime is also installed.
#
#    Installing and configuring Hadoop consists of the following
#    steps:
#
#     1. Install a Java JDK
#     2. Download the MongoDB tar.gz archive
#     3. Unpackage the Mongo archive
#     4. Move the mongo directory to /usr/bin/
#     5. Update the ~/.bashrc file with mongodb specific exports
#     8. Start mongoperf test
#######################################################################


#
# Constants/Globals
#
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occurred during the test

CONSTANTS_FILE="/root/constants.sh"
SUMMARY_LOG=~/summary.log

MONGODB_VERSION="2.4.0"
MONGODB_ARCHIVE="mongodb-linux-x86_64-${MONGODB_VERSION}.tgz"
MONGODB_URL="http://fastdl.mongodb.org/linux/${MONGODB_ARCHIVE}"

#######################################################################
#
# LogMsg()
#
#######################################################################
LogMsg()
{
    echo `date "+%b %d %Y %T"` : "${1}"    # Add the time stamp to the log message
    echo "${1}" >> ~/mongodb.log
}


#######################################################################
#
# UpdateTestState()
#
#######################################################################
UpdateTestState()
{
    echo "${1}" > ~/state.txt
}


#######################################################################
#
# UpdateSummary()
#
#######################################################################
UpdateSummary()
{
    echo "${1}" >> ~/summary.log
}


#######################################################################
#
# TimeToSeconds()
#
#######################################################################
TimeToSeconds()
{
    read -r h m s <<< $(echo $1 | tr ':' ' ')
    #echo $(((h*60*60)+(m*60)+s))
    echo `echo "${h}*60*60+${m}*60+${s}" | bc`
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


#######################################################################
#
# ConfigRhel()
#
#######################################################################
ConfigRhel()
{
    LogMsg "ConfigRhel"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        yum -y install java-1.7.0-openjdk
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install Java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
	ssh root@${MD_SERVER} "yum -y install java-1.7.0-openjdk"
    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    LogMsg "Create JAVA_HOME variable"

    javaConfig=`echo "" | update-alternatives --config java | grep "*"`
    tokens=( $javaConfig )
    javaPath=${tokens[2]}
    if [ ! -e $javaPath ]; then
        LogMsg "Error: Unable to find the Java install path"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp=`dirname $javaPath`
    JAVA_HOME=`dirname $temp`
    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    #
    # This is a hack so we can use the same mongodb config on all Linux
    # distros.  With RHEL, localhost fails.  By setting the hostname
    # to localhost, then the default config works in RHEL.
    # Need to revisit this to find a better solution.
    #
    #hostname localhost
}


#######################################################################
#
# ConfigSles()
#
#######################################################################
ConfigSles()
{
    LogMsg "ConfigSles"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        zypper --non-interactive install jre-1.7.0
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
	ssh root@${MD_SERVER} "zypper --non-interactive install jre-1.7.0"
    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    javaConfig=`update-alternatives --config java`
    tempHome=`echo $javaConfig | cut -f 2 -d ':' | cut -f 2 -d ' '`

    if [ ! -e $tempHome ]; then
        LogMsg "Error: The Java directory '${tempHome}' does not exist"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp1=`dirname $tempHome`
    JAVA_HOME=`dirname $temp1`

    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    #
    # Depending on how the user configs the SLES system, we may or may not
    # need the following workaround to allow mongodb to use localhost
    #
    #hostname localhost
}


#######################################################################
#
# ConfigUbuntu()
#
#######################################################################
ConfigUbuntu()
{
    LogMsg "ConfigUbuntu"

    #
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"
        apt-get update
        apt-get -y install default-jdk
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
	ssh root@${MD_SERVER} "apt-get update"
	ssh root@${MD_SERVER} "apt-get -y install default-jdk"
    #
    # Figure out where Java is installed so we can configure a JAVA_HOME variable
    #
    javaConfig=`update-alternatives --config java`
    tempHome=`echo $javaConfig | cut -f 2 -d ':' | cut -f 2 -d ' '`
    if [ ! -e $tempHome ]; then
        LogMsg "Error: The Java directory '${tempHome}' does not exist"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    temp1=`dirname $tempHome`
    temp2=`dirname $temp1`
    JAVA_HOME=`dirname $temp2`
    if [ ! -e $JAVA_HOME ]; then
        LogMsg "Error: Invalid JAVA_HOME computed: ${JAVA_HOME}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
}

#######################################################################
#
# Main script body
#
#######################################################################

cd ~

UpdateTestState $ICA_TESTRUNNING
LogMsg "Updated test case state to running"

rm -f ~/summary.log
touch ~/summary.log

if [ -e ${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    errMsg="Error: missing ${CONSTANTS_FILE} file"
    LogMsg "${errMsg}"
    echo "${errMsg}" >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ ! ${MONGODB_VERSION} ]; then
	errMsg="The MONGODB_VERSION test parameter is not defined. Setting as ${MONGODB_VERSION} "
    LogMsg "${errMsg}"
    echo "${errMsg}" >> ~/summary.log
fi

if [ ! ${MD_SERVER} ]; then
    nThreads=16
	LogMsg "Info : nThreads not defined in constants.sh. Setting as ${nThreads}"
fi

#
# Install Java
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "EULEROS" | "RHEL")
        ConfigRhel
    ;;
    "UBUNTU")
        ConfigUbuntu
    ;;
    "DEBIAN")
        LogMsg "Debian is not supported"
        UpdateTestState "TestAborted"
        UpdateSummary "  Distro '${distro}' is not currently supported"
        exit 1
    ;;
    "SLES")
        ConfigSles
    ;;
     *)
        LogMsg "Distro '${distro}' not supported"
        UpdateTestState "TestAborted"
        UpdateSummary " Distro '${distro}' not supported"
        exit 1
    ;; 
esac

#
# Download MongoDB to server and start mongodb server.
#
LogMsg "Downloading MangoDB if we do not have a local copy"

if [ ! -e "/root/${MONGODB_ARCHIVE}" ]; then
    LogMsg "Downloading Hadoop from ${MONGODB_URL}"
    ssh root@${MD_SERVER} "wget ${MONGODB_URL}"
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to download mongodb from ${MONGODB_URL}"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi
    LogMsg "MangoDB successfully downloaded"
fi

	

#
# Untar and install Hadoop
#
LogMsg "Extracting the mongodb archive"

ssh root@${MD_SERVER} "tar xfvz mongodb-linux-x86_64-${MONGODB_VERSION}.tgz"
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to extract mongodb from its archive"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi    

LogMsg "Download YCSB on client VM"
curl -O --location https://github.com/brianfrankcooper/YCSB/releases/download/0.5.0/ycsb-0.5.0.tar.gz
if [ $? -ne 0 ]; then
	LogMsg "Error: Unable to download YCSB"
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi
LogMsg "Extract YCSB on client VM"
tar xfvz ycsb-0.5.0.tar.gz
if [ $? -ne 0 ]; then
	LogMsg "Error: Unable to download YCSB"
	UpdateTestState $ICA_TESTFAILED
	exit 1
fi

LogMsg "Check if MangoDB specific exports are in the .bashrc file"

grep -q "mangodb exports start" ~/.bashrc
if [ $? -ne 0 ]; then
    LogMsg "MongoDB exports not found in ~/.bashrc, adding them"
    echo "" >> ~/.bashrc
    echo "# mango exports start" >> ~/.bashrc
    echo "export JAVA_HOME=${JAVA_HOME}" >> ~/.bashrc
    echo "# MangoDB exports end" >> ~/.bashrc
fi

#
# Sourcing the update .bashrc
#
source ~/.bashrc
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to source .bashrc"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

LogMsg "Starting MongoDB on ${MD_SERVER}"
ssh root@${MD_SERVER} "killall mongod"
ssh root@${MD_SERVER} "mkdir -p /tmp/mongodb"
#ssh root@${MD_SERVER} "nohup /root/mongodb-linux-x86_64-${MONGODB_VERSION}/bin/mongod --dbpath /tmp/mongodb > mongodServerConsole.txt &"
ssh root@${MD_SERVER} "/root/mongodb-linux-x86_64-${MONGODB_VERSION}/bin/mongod --dbpath /tmp/mongodb --fork --logpath mongodServerConsole.txt"
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to start mongod server"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

LogMsg "Using the asynchronous driver to load the test data"
/root/ycsb-0.5.0/bin/ycsb load mongodb-async -s -P workloadAzure -p mongodb.url=mongodb://${MD_SERVER}:27017/ycsb?w=0
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable load the test data"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

LogMsg "Using the asynchronous driver to load the test data"
/root/ycsb-0.5.0/bin/ycsb run mongodb-async -s -P workloadAzure -p mongodb.url=mongodb://${MD_SERVER}:27017/ycsb?w=0
if [ $? -ne 0 ]; then
    LogMsg "Error: Unable to run test"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

#
# If we made it here, everything worked.
#
UpdateTestState $ICA_TESTCOMPLETED
exit 0
