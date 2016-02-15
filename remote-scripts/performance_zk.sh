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
# performance_zk.sh
#
# Description:
#     This tool uses the ZooKeeper (zk) python binding to test various operation latencies
#
#
# In general the script does the following:
#
# 1.create a root znode for the test, i.e. /zk-latencies
# 2.attach a zk session to each server in the ensemble (the --servers list)
# 3.run various (create/get/set/delete) operations against each server, note the latencies of operations
# 4.client then cleans up, removing /zk-latencies znode
#
#
# Parameters:
#	ZK_VERSION			zookeeper-server version
#      	ZK_SERVERS:               	comma separated list of host:port (default localhost:2181)
#	ZK_TIMEOUT;			session timeout in milliseconds (default 5000)
#	ZK_ZNODE_SIZE;			data size when creating/setting znodes (default 25)
#	ZK_ZNODE_COUNT;			the number of znodes to operate on in each performance section (default 10000)
#	ZK_FORCE; (optional)		force the test to run, even if root_znode exists -WARNING! don't run this on a real znode or you'll lose it !!!
#	ZK_SYNCHRONOUS;			by default asynchronous ZK api is used, this forces synchronous calls
#	ZK_VERBOSE;			verbose output, include more detail
#
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
# DoSlesAB()
#
# Description:
#    Perform distro specific Apache and tool installation steps for SLES
#    and then run the benchmark tool
#
#######################################################################
ConfigSlesZK()
{
    #
    # Note: A number of steps will use SSH to issue commands to the
    #       APACHE_SERVER.  This requires that the SSH keys be provisioned
    #       in advanced, and strict mode be disabled for both the SSH
    #       server and client.
    #

	LogMsg "Info: Running SLES"
	arr=$(echo $ZK_SERVERS | tr "," "\n")
	for ZK_SERVER in $arr
	do
	#echo "${ZK_SERVER}"
	SERVER=(`echo "${ZK_SERVER}" | awk -F':' '{print $1}'`)
	#echo "${SERVER}"
	#ssh root@${SERVER} "mkdir /root/kk"
	#exit 1
	LogMsg "Info: -----------------------------------------"
	LogMsg "Info: Zookeeper-Server installation on server ${SERVER}"
    	LogMsg "Info: Installing required packages first"
	ssh root@${SERVER} "zypper --non-interactive install wget"
	if [ $? -ne 0 ]; then
		msg="Error: Unable to install package to server ${SERVER}"
		LogMsg "${msg}"
		echo "${msg}" >> ./summary.log
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi
	
	#
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        ssh root@${SERVER} "zypper --non-interactive install jre-1.7.0"
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
        LogMsg "Info: Download ZK package"
	pkg=(`ssh root@${SERVER} "ls /root/ | grep ${ZK_ARCHIVE}"`)
	echo $pkg
	if [ -z "$pkg" ]; then
		LogMsg "Downloading ZK package ${ZK_ARCHIVE}"
		#exit 1	
        	ssh root@${SERVER} "wget ${ZK_URL}"
        	if [ $? -ne 0 ]; then
                	msg="Error: Unable to download ZK package to server ${SERVER}"
                	LogMsg "${msg}"
                	echo "${msg}" >> ./summary.log
                	UpdateTestState $ICA_TESTFAILED
                	exit 1
		fi	
        fi

	LogMsg "Info: Untar and Config ZK server"
        ssh root@${SERVER} "tar -xzf ./${ZK_ARCHIVE}"
        ssh root@${SERVER} "cp zookeeper-${ZK_VERSION}/conf/zoo_sample.cfg zookeeper-${ZK_VERSION}/conf/zoo.cfg"

	LogMsg "Info: Starting Zookeeper-Server ${SERVER}"
        ssh root@${SERVER} "zookeeper-${ZK_VERSION}/bin/zkServer.sh start"
	if [ $? -ne 0 ]; then
                msg="Error: Unable to start Zookeeper-Server on ${SERVER}"
                LogMsg "${msg}"
                echo "${msg}" >> ./summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 1
        fi

	LogMsg "Info: Server started successfully"

	done	
}

ConfigUbuntuZK()
{
    #
    # Note: A number of steps will use SSH to issue commands to the
    #       ZK_SERVER.  This requires that the SSH keys be provisioned
    #       in advanced, and strict mode be disabled for both the SSH
    #       server and client.
    #

	LogMsg "Info: Running Ubuntu"
	arr=$(echo $ZK_SERVERS | tr "," "\n")
	for ZK_SERVER in $arr
	do	
	SERVER=(`echo "${ZK_SERVER}" | awk -F':' '{print $1}'`)
	LogMsg "Info: -----------------------------------------"
	LogMsg "Info: Zookeeper-Server installation on server ${SERVER}"
    	LogMsg "Info: Installing required packages first"
	ssh root@${SERVER} "apt-get install -y wget"
	if [ $? -ne 0 ]; then
		msg="Error: Unable to install package to server ${SERVER}"
		LogMsg "${msg}"
		echo "${msg}" >> ./summary.log
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi
	
	#
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        ssh root@${SERVER} "apt-get -y install default-jdk"
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi

        LogMsg "Info: Download ZK package"
	pkg=(`ssh root@${SERVER} "ls /root/ | grep ${ZK_ARCHIVE}"`)
	echo $pkg
	if [ -z "$pkg" ]; then
		LogMsg "Downloading ZK package ${ZK_ARCHIVE}"
		#exit 1	
        	ssh root@${SERVER} "wget ${ZK_URL}"
        	if [ $? -ne 0 ]; then
                	msg="Error: Unable to download ZK package to server ${SERVER}"
                	LogMsg "${msg}"
                	echo "${msg}" >> ./summary.log
                	UpdateTestState $ICA_TESTFAILED
                	exit 1
		fi	
        fi

	LogMsg "Info: Untar and Config ZK server"
        ssh root@${SERVER} "tar -xzf ./${ZK_ARCHIVE}"
        ssh root@${SERVER} "cp zookeeper-${ZK_VERSION}/conf/zoo_sample.cfg zookeeper-${ZK_VERSION}/conf/zoo.cfg"

	LogMsg "Info: Starting Zookeeper-Server ${SERVER}"
        ssh root@${SERVER} "zookeeper-${ZK_VERSION}/bin/zkServer.sh start"
	if [ $? -ne 0 ]; then
                msg="Error: Unable to start Zookeeper-Server on ${SERVER}"
                LogMsg "${msg}"
                echo "${msg}" >> ./summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 1
        fi

	LogMsg "Info: Server started successfully"

	done	
}

ConfigRHELZK()
{
    #
    # Note: A number of steps will use SSH to issue commands to the
    #       ZK_SERVER.  This requires that the SSH keys be provisioned
    #       in advanced, and strict mode be disabled for both the SSH
    #       server and client.
    #

	LogMsg "Info: Running RHEL"
	arr=$(echo $ZK_SERVERS | tr "," "\n")
	for ZK_SERVER in $arr
	do	
	SERVER=(`echo "${ZK_SERVER}" | awk -F':' '{print $1}'`)
	LogMsg "Info: -----------------------------------------"
	LogMsg "Info: Zookeeper-Server installation on server ${SERVER}"
    	LogMsg "Info: Installing required packages first"
	ssh root@${SERVER} "yum install -y wget"
	if [ $? -ne 0 ]; then
		msg="Error: Unable to install package to server ${SERVER}"
		LogMsg "${msg}"
		echo "${msg}" >> ./summary.log
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi
	
	#
    # Install Java
    #
    LogMsg "Check if Java is installed"

    javaInstalled=`which java`
    if [ ! $javaInstalled ]; then
        LogMsg "Installing Java"

        ssh root@${SERVER} "yum -y install java-1.7.0-openjdk"
        if [ $? -ne 0 ]; then
            LogMsg "Error: Unable to install Java"
            UpdateTestState $ICA_TESTFAILED
            exit 1
        fi
    fi
	
        LogMsg "Info: Download ZK package"
	pkg=(`ssh root@${SERVER} "ls /root/ | grep ${ZK_ARCHIVE}"`)
	echo $pkg
	if [ -z "$pkg" ]; then
		LogMsg "Downloading ZK package ${ZK_ARCHIVE}"
		#exit 1	
        	ssh root@${SERVER} "wget ${ZK_URL}"
        	if [ $? -ne 0 ]; then
                	msg="Error: Unable to download ZK package to server ${SERVER}"
                	LogMsg "${msg}"
                	echo "${msg}" >> ./summary.log
                	UpdateTestState $ICA_TESTFAILED
                	exit 1
		fi	
        fi

	LogMsg "Info: Untar and Config ZK server"
        ssh root@${SERVER} "tar -xzf ./${ZK_ARCHIVE}"
        ssh root@${SERVER} "cp zookeeper-${ZK_VERSION}/conf/zoo_sample.cfg zookeeper-${ZK_VERSION}/conf/zoo.cfg"

	LogMsg "Info: Starting Zookeeper-Server ${SERVER}"
        ssh root@${SERVER} "zookeeper-${ZK_VERSION}/bin/zkServer.sh start"
	if [ $? -ne 0 ]; then
                msg="Error: Unable to start Zookeeper-Server on ${SERVER}"
                LogMsg "${msg}"
                echo "${msg}" >> ./summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 1
        fi

	LogMsg "Info: Server started successfully"

	done	
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
if [ "${ZK_VERSION:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the ZK_VERSION test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${ZK_SERVERS:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the ZK_SERVER test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    UpdateTestState $ICA_TESTFAILED
    exit 20
fi

if [ "${ZK_TIMEOUT:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the ZK_TIMEOUT test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    ZK_TIMEOUT=100000
fi

if [ "${ZK_ZNODE_SIZE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the ZK_ZNODE_SIZE test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    ZK_ZNODE_SIZE=100
fi

if [ "${ZK_ZNODE_COUNT:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the ZK_ZNODE_COUNT test parameter is missing"
    LogMsg "${msg}"
    echo "${msg}" >> ~/summary.log
    ZK_ZNODE_SIZE=100
fi

if [ "${ZK_FORCE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the ZK_FORCE test parameter is missing"
    LogMsg "${msg}"
    ZK_FORCE=$false
fi

if [ "${ZK_VERBOSE:="UNDEFINED"}" = "UNDEFINED" ]; then
    msg="Error: the ZK_VERBOSE test parameter is missing"
    LogMsg "${msg}"
    ZK_VERBOSE=$false
fi

LogMsg "Info: Test run parameters"
echo "ZK_VERSION               = ${ZK_VERSION}"
echo "ZK_SERVERS               = ${ZK_SERVERS}"
echo "ZK_TIMEOUT    = ${ZK_TIMEOUT}"
echo "ZK_ZNODE_SIZE = ${ZK_ZNODE_SIZE}"
echo "ZK_ZNODE_COUNT = ${ZK_ZNODE_COUNT}"
echo "ZK_FORCE = ${ZK_FORCE}"
echo "ZK_SYNCHRONOUS = ${ZK_SYNCHRONOUS}"
echo "ZK_VERBOSE = ${ZK_VERBOSE}"


LogMsg "Info : ZK_VERSION = ${ZK_VERSION}"
ZK_ARCHIVE="zookeeper-${ZK_VERSION}.tar.gz"
ZK_URL=http://apache.spinellicreations.com/zookeeper/zookeeper-${ZK_VERSION}/${ZK_ARCHIVE}

#
# Configure ZK server - this has distro specific behaviour
#
distro=`LinuxRelease`
case $distro in
    "CENTOS" | "RHEL")
        ConfigRHELZK
    ;;
    "UBUNTU")
        ConfigUbuntuZK
    ;;
    "DEBIAN")
        ConfigDebianZK
    ;;
    "SLES")
        ConfigSlesZK
    ;;
     *)
        msg="Error: Distro '${distro}' not supported"
        LogMsg "${msg}"
        echo "${msg}" >> ~/summary.log
        UpdateTestState "TestAborted"
        exit 1
    ;; 
esac

IFS=',' read -ra ADDR <<< "$ZK_SERVERS"
for zk_server in "${ADDR[@]}"; 
do
	LogMsg "Prepare ZK test cmd for ${zk_server}"
	testBaseString='PYTHONPATH="lib.linux-x86_64-2.6" LD_LIBRARY_PATH="lib.linux-x86_64-2.6" python ./zk-latencies.py '
	#testBaseString='./zk-latencies.py PYTHONPATH=lib.linux-x86_64-2.6 LD_LIBRARY_PATH=lib.linux-x86_64-2.6 '
	testString="${testBaseString}""--servers=${zk_server} --timeout=${ZK_TIMEOUT} --znode_count=${ZK_ZNODE_COUNT} --znode_size=${ZK_ZNODE_SIZE}"

	if [ "${ZK_FORCE}" = true ]; then
		testString="${testString}"" --force"
	fi

	if [ "${ZK_SYNCHRONOUS}" = true ]; then
			testString="${testString}"" --synchronous"
	fi

	if [ "${ZK_VERBOSE}" = true ]; then
		testString="${testString}"" --verbose"
	fi

	LogMsg "Running zookeeper tests with cmd: ${testString}"
	eval $testString
	if [ $? -ne 0 ]; then
		msg="Error: Unable to run test"
		LogMsg "${msg}"
		echo "${msg}" >> ./summary.log
		UpdateTestState $ICA_TESTFAILED
		exit 1
	fi
done


#
# If we made it here, everything worked.
# Indicate success
#
LogMsg "Test completed successfully"
UpdateTestState $ICA_TESTCOMPLETED

exit 0