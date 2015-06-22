#!/bin/sh
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
#
# Sample script to run sysbench.
# In this script, we want to test 3 different devices, all mounted on the same
# machine.  You can adapt this script to other situations easily.  The only
# thing to keep in mind is that each different configuration you're testing
# must log its output to a different directory.
#
# For any info contact v-shisav@microsoft.com

while echo $1 | grep ^- > /dev/null; do
    eval $( echo $1 | sed 's/-//g' | tr -d '\012')=$2
    shift
    shift
done
PrepareFiles=$PrepareFiles
RunTest=$RunTest
CleanUp=$CleanUp
CustomLogDir=$CustomLogDir
testIO=$testIO
testThread=$testThread
ioRuntime=$ioRuntime
testMode=$testMode
fileSize=$fileSize
set -u
set -x
#export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/oem/bin:/usr/share/oem/python/bin:/opt/bin

FILEIO="--test=fileio --file-total-size=${fileSize} --file-extra-flags=dsync --file-fsync-freq=0"
#FILEIO="--test=fileio --file-total-size=134G "

####################################
#All run config set here
#
LOGDIR=$CustomLogDir
mkdir -p $CustomLogDir
LOGFILE="${LOGDIR}/sysbench.log.txt"
#FILE PREPARE
echo "===================================== Starting Run $(date +"%x %r %Z") script generated 2/9/2015 4:24:44 PM ================================" >> $LOGFILE
if [ "$PrepareFiles" = "yes" ]; then
	echo "" > $LOGFILE
	chmod 666 $LOGFILE
	echo "SYSBENCH-FILE-PREPARE-PROGRESS" > $LOGDIR/CurrentSysbenchStatus.txt	
	echo "Preparing Files: $FILEIO"
	echo "Preparing Files: $FILEIO" >> $LOGFILE
	# Remove any old files from prior runs (to be safe), then prepare a set of new files.
	sysbench $FILEIO cleanup
	echo "--- Disk Usage Before Generating New Files ---" >> $LOGFILE
	df >> $LOGFILE
	iostatfilename="${LOGDIR}/iostat-sysbench-file-prepare.txt"
	nohup iostat -x 5 -t -y > $iostatfilename &
	sysbench $FILEIO prepare
	echo "--- Disk Usage After Generating New Files ---" >> $LOGFILE
	df >> $LOGFILE	
	echo "=== End Preparation  $(date +"%x %r %Z") ===" >> $LOGFILE
	echo "SYSBENCH-FILE-PREPARE-FINISH" > $LOGDIR/CurrentSysbenchStatus.txt
	iostatPID=`ps -ef | awk '/iostat/ && !/awk/ { print $2 }'`
	kill -9 $iostatPID	
fi
#TEST RUN
if [ "$RunTest" = "yes" ]; then
	iostatfilename="${LOGDIR}/iostat-sysbench-${testMode}-${testIO}-${testThread}.txt"
	nohup iostat -x 5 -t -y > $iostatfilename &
	echo "------------------------------- ${testMode}, ${testIO}, ${testThread} threads ${ioRuntime} seconds------------------ $(date +"%x %r %Z") ---" >> $LOGFILE
	echo "SYSBENCH-TEST-RUNNING-${testMode}-${testIO}K-${testThread}-${ioRuntime}" > $LOGDIR/CurrentSysbenchStatus.txt
	sysbench $FILEIO --file-test-mode=$testMode --file-block-size=${testIO} --max-requests=0 --max-time=$ioRuntime --num-threads=$testThread run >> $LOGFILE
	iostatPID=`ps -ef | awk '/iostat/ && !/awk/ { print $2 }'`
	kill -9 $iostatPID
	echo "SYSBENCH-TEST-FINISHED" > $LOGDIR/CurrentSysbenchStatus.txt
fi
#CLEANUP
if [ "$CleanUp" = "yes" ]; then
	echo "===================================== Completed Run $(date +"%x %r %Z") script generated 2/9/2015 4:24:44 PM ================================" >> $LOGFILE
	sysbench $FILEIO cleanup >> $LOGFILE
fi