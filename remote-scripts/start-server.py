#!/usr/bin/python


##########################################
#THIS SCRIPT ACCETPS SOME SERVER PARAMETERS.
#PLEASE RUN THE SCRIPT WITH -h OR -help FOR MORE DETAILS.
##########################################


from azuremodules import *


import argparse
import sys
 #for error checking
parser = argparse.ArgumentParser()

parser.add_argument('-u', '--udp', help='switch : starts the server in udp data packets listening mode.', choices=['yes', 'no'] )
parser.add_argument('-p', '--port', help='specifies which port should be used', required=True, type= int)
#parser.add_argument('-m', '--maxsegdisplay', help='Maximum Segment Size display ', choices=['yes', 'no'])
#parser.add_argument('-M', '--maxsegset', help='Maximum Segment Size Settings', type = int)
parser.add_argument('-m', '--mss_print', help='Maximum Segment Size display ', choices=['yes', 'no'])
parser.add_argument('-M', '--mss', help='Maximum Segment Size Settings', type = int)
parser.add_argument('-i', '--interval', help='specifies frequency of the output to be displyed on screen', type= int)

args = parser.parse_args()
#if no value specified then stop
command = 'iperf -s' + ' -p' + str(args.port) + ' -f K'
if args.interval != None :
        command = command + ' -i' + str(args.interval)
if args.udp == 'yes':
        command = command + ' -u'
if args.mss != None:
        command = command + ' -M' + str(args.mss)
if args.mss_print == 'yes':
        command = command + ' -m'
#finalCommand = 'nohup ' + command + ' >>  iperf-server.txt &'
finalCommand = command + ' >>  iperf-server.txt'


server = finalCommand
print(server)
#Run('echo "TestStarted" > iperf-server.txt')
StopServer()
StartServer(server)
#Run('echo "TestCompleted" >> iperf-server.txt')
