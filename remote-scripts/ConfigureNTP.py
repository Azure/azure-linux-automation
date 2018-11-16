#!/usr/bin/python

import argparse
import sys
from azuremodules import *

parser = argparse.ArgumentParser()
parser.add_argument('-d', '--distro', help='UBUNTU/SUSE/SLES/CENTOS/ORACLE/EULEROS', required=True)
args = parser.parse_args()
DetectedDistro = args.distro

def SetNTPVariables(DetectedDistro):
        if DetectedDistro.upper() == 'UBUNTU':
                ntp_package = 'ntp'
                ntp_service = 'ntpdc'
                ntp_query = "dpkg-query -s ntp"
                ntp_installCommand = "apt-get install --force-yes -y ntp"
                ntp_status = "ntpdc -p"
        if DetectedDistro.upper() == 'SUSE':
                ntp_package = 'ntp'
                ntp_service = 'ntpd'
                ntp_query = "rpm -q ntp"
                ntp_installCommand = "zypper --non-interactive --no-gpg-checks install ntp"
                ntp_status = "ntpdc -p"
        if DetectedDistro.upper() == 'SLES':
                ntp_package = 'ntp'
                ntp_service = 'ntpd'
                ntp_query = "rpm -q ntp"
                ntp_installCommand = "zypper --non-interactive --no-gpg-checks install ntp"
                ntp_status = "ntpdc -p"
        if DetectedDistro.upper() == 'CENTOS':
                ntp_package = 'ntp'
                ntp_service = 'ntpd'
                ntp_query = "rpm -q ntp"
                ntp_installCommand = "yum install --nogpgcheck -y ntp"
                ntp_status = "ntpdc -p"
        if DetectedDistro.upper() == 'EULEROS':
                ntp_package = 'ntp'
                ntp_service = 'ntpd'
                ntp_query = "rpm -q ntp"
                ntp_installCommand = "yum install --nogpgcheck -y ntp"
                ntp_status = "ntpdc -p"
        if DetectedDistro.upper() == 'REDHAT':
                ntp_package = 'ntp'
                ntp_service = 'ntpd'
                ntp_query = "rpm -q ntp"
                ntp_installCommand = "yum install --nogpgcheck -y ntp"
                ntp_status = "ntpdc -p"
        if DetectedDistro.upper() == 'ORACLE':
                ntp_package = 'ntp'
                ntp_service = 'ntpd'
                ntp_query = "yum install --nogpgcheck -y ntp"
                ntp_installCommand = "yum install --nogpgcheck -y ntp"
                ntp_status = "ntpdc -p"
        return (ntp_package,ntp_service,ntp_query,ntp_installCommand)

def CheckNTPInstallation(ntp_query,ntp_installCommand):
        print('Checking NTP installation status')
        if IsNtpInstalled(ntp_query):
                print("NTP_INSTALLED")
        else:
                print("NTP not installed")
                InstallNTP(ntp_installCommand)

def InstallNTP(ntp_installCommand):
        Run(ntp_installCommand)
        print("NTP_INSTALLED")

def IsNtpInstalled(ntp_query):
        ntp_query_out = JustRun(ntp_query)
        if "is not installed" in ntp_query_out:
                return False
        else:
                return True
def AddNTPServers():
        Run("echo server 0.rhel.pool.ntp.org >> /etc/ntp.conf")
        Run("echo server 1.rhel.pool.ntp.org >> /etc/ntp.conf")
        Run("echo server 2.rhel.pool.ntp.org >> /etc/ntp.conf")
        Run("echo server 3.rhel.pool.ntp.org >> /etc/ntp.conf")
        print("NTP_SERVERS_INSTALLED")
def RestartNtpService(ntp_service):
        Run("service "+ntp_service+" restart")

def main(DetectedDistro):
        (ntp_package,ntp_service,ntp_query,ntp_installCommand)=SetNTPVariables(DetectedDistro)
        CheckNTPInstallation(ntp_query,ntp_installCommand)
        AddNTPServers()
        RestartNtpService(ntp_service)

main(DetectedDistro)
