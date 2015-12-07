#!/usr/bin/python
from azuremodules import *
import sys
import shutil
import time
import re
import os
import linecache
import imp
import os.path
import zipfile

current_distro        = "unknown"
distro_version        = "unknown"
sudo_password        = "rdPa$$w0rd"
startup_file = ""

rpm_links = {}
tar_link = {}
current_distro = "unknown"
packages_list_xml = "./packages.xml"
python_cmd="python"
waagent_cmd="waagent"
waagent_bin_path="/usr/sbin"

def set_variables_OS_dependent():
        global current_distro
        global distro_version
        global startup_file

        RunLog.info ("\nset_variables_OS_dependent ..")
        [current_distro, distro_version] = DetectDistro()
        if(current_distro == 'unknown'):
                RunLog.error ("unknown distribution found, exiting")
                ResultLog.info('ABORTED')
                exit()
        if(current_distro == "ubuntu" or current_distro == "debian"):
                startup_file = '/etc/rc.local'
        elif(current_distro == "centos" or current_distro == "rhel" or current_distro == "fedora" or current_distro == "Oracle"):
                startup_file = '/etc/rc.d/rc.local'
        elif(current_distro == "SUSE" or current_distro == "sles" or current_distro == "opensuse"):
                startup_file = '/etc/rc.d/after.local'
        
        if(current_distro == "coreos"):
                python_cmd="/usr/share/oem/python/bin/python"
                waagent_bin_path="/usr/share/oem/bin/python"
                waagent_cmd= "{0} {1}".format(python_cmd, waagent_bin_path)
                
        RunLog.info ("\nset_variables_OS_dependent ..[done]")

def download_and_install_rpm(package):
        RunLog.info("Installing Package: " + package+" from rpmlink")
        if package in rpm_links:
                if DownloadUrl(rpm_links.get(package), "/tmp/"):
                        if InstallRpm("/tmp/"+re.split("/",rpm_links.get(package))[-1], package):
                                RunLog.info("Installing Package: " + package+" from rpmlink done!")
                                return True

        RunLog.error("Installing Package: " + package+" from rpmlink failed!!")
        return False

def easy_install(package):
        RunLog.info("Installing Package: " + package+" via easy_install")
        temp = Run("command -v easy_install")
        if not ("easy_install" in temp):
            install_ez_setup()
        if package == "python-crypto":
            output = Run("easy_install pycrypto")
            return ("Finished" in output)
        if package == "python-paramiko":
            output = Run("easy_install paramiko")
            return ("Finished" in output)
        RunLog.error("Installing Package: " + package+" via easy_install failed!!")
        return False

def yum_package_install(package):
        if(YumPackageInstall(package) == True):
                return True
        elif(download_and_install_rpm(package) == True):
                return True
        elif(easy_install(package) == True):
		        return True
        else:
                return False

def zypper_package_install(package):
        if(ZypperPackageInstall(package) == True):
                return True
        elif(download_and_install_rpm(package) == True):
                return True
        else:
                return False

def coreos_package_install():
        binpath="/usr/share/oem/bin"
        pythonlibrary="/usr/share/oem/python/lib64/python2.7"

        # create /etc/hosts
        ExecMultiCmdsLocalSudo(["touch /etc/hosts",\
                "echo '127.0.0.1 localhost' > /etc/hosts",\
                "echo '** modify /etc/hosts successfully **' >> PackageStatus.txt"])
        # copy tools to bin folder
        Run("unzip -d CoreosPreparationTools ./CoreosPreparationTools.zip")
        ExecMultiCmdsLocalSudo(["cp ./CoreosPreparationTools/killall " + binpath, \
                "cp ./CoreosPreparationTools/iperf " + binpath,\
                "cp ./CoreosPreparationTools/iozone " + binpath,\
                "cp ./CoreosPreparationTools/dos2unix " + binpath,\
                "cp ./CoreosPreparationTools/at " + binpath,\
                "chmod 755 "+ binpath + "/*",\
                "echo '** copy tools successfully **' >> PackageStatus.txt"])
        # copy python library to python library folder
        Run("tar zxvf ./CoreosPreparationTools/pycrypto.tar.gz -C "+ pythonlibrary)
        ExecMultiCmdsLocalSudo(["tar zxvf ./CoreosPreparationTools/ecdsa-0.13.tar.gz -C ./CoreosPreparationTools",\
                "cd ./CoreosPreparationTools/ecdsa-0.13",\
                "/usr/share/oem/python/bin/python setup.py install",\
                "cd ../.."])
        ExecMultiCmdsLocalSudo(["tar zxvf ./CoreosPreparationTools/paramiko-1.15.1.tar.gz -C ./CoreosPreparationTools",\
                "cd ./CoreosPreparationTools/paramiko-1.15.1",\
                "/usr/share/oem/python/bin/python setup.py install",\
                "cd ../..",\
                "tar zxvf ./CoreosPreparationTools/pexpect-3.3.tar.gz -C ./CoreosPreparationTools",\
                "cd ./CoreosPreparationTools/pexpect-3.3",\
                "/usr/share/oem/python/bin/python setup.py install",\
                "cd ../.."])
        ExecMultiCmdsLocalSudo(["tar zxvf ./CoreosPreparationTools/dnspython-1.12.0.tar.gz -C ./CoreosPreparationTools",\
                "cd ./CoreosPreparationTools/dnspython-1.12.0",\
                "/usr/share/oem/python/bin/python setup.py install",\
                "cd ../.."])
        if not os.path.exists (pythonlibrary + "/site-packages/pexpect"):
                RunLog.error ("pexpect package installation failed!")
                Run("echo '** pexpect package installation failed **' >> PackageStatus.txt")
                return False
        if not os.path.exists (pythonlibrary + "/site-packages/paramiko"):
                RunLog.error ("paramiko packages installation failed!")
                Run("echo '** paramiko packages installed failed **' >> PackageStatus.txt")
                return False
        if not os.path.exists (pythonlibrary + "/site-packages/dns"):
                RunLog.error ("dnspython packages installation failed!")
                Run("echo '** dnspython packages installed failed **' >> PackageStatus.txt")
                return False
        RunLog.info ("pexpect, paramiko and dnspython packages installed successfully!")
        Run("echo '** pexpect, paramiko and dnspython packages installed successfully **' >> PackageStatus.txt")
        return True

def install_ez_setup():
        RunLog.info ("Installing ez_setup.py...")

        ez_setup = os.path.join("/tmp", "ez_setup.py")
        DownloadUrl(tar_link.get("ez_setup.py"), "/tmp/", output_file=ez_setup)
        if not os.path.isfile(ez_setup):
                RunLog.error("Installing ez_setup.py...[failed]")
                RunLog.error("File not found: {0}".format(ez_setup))
                return False


        output = Run("{0} {1}".format(python_cmd, ez_setup))
        return ("Finished" in output)



def install_waagent_from_github():
        RunLog.info ("Installing waagent from github...")

        pkgPath = os.path.join("/tmp", "agent.zip")
        DownloadUrl(tar_link.get("waagent"), "/tmp/", output_file=pkgPath)
        if not os.path.isfile(pkgPath):
                RunLog.error("Installing waagent from github...[failed]")
                RunLog.error("File not found: {0}".format(pkgPath))
                return False
        
        unzipPath = os.path.join("/tmp", "agent")
        if os.path.isdir(unzipPath):
            shutil.rmtree(unzipPath)

        try:
                zipfile.ZipFile(pkgPath).extractall(unzipPath)
        except IOError as e:
                RunLog.error("Installing waagent from github...[failed]")
                RunLog.error("{0}".format(e))
                return False
        
        waagentSrc = os.listdir(unzipPath)[0]
        waagentSrc = os.path.join(unzipPath, waagentSrc)
        binPath20 = os.path.join(waagentSrc, "waagent")
        binPath21 = os.path.join(waagentSrc, "bin/waagent")
        if os.path.isfile(binPath20):
                #For 2.0, only one file(waagent) needs to be replaced.
                os.chmod(binPath20, 0o755)
                ExecMultiCmdsLocalSudo([
                        "cp {0} {1}".format(binPath20, waagent_bin_path)])
                return True                
        elif os.path.isfile(binPath21):
                #For 2.1, use setup.py to install/uninstall package
                os.chmod(binPath21, 0o755)
                setup_py = os.path.join(waagentSrc, 'setup.py')
                ExecMultiCmdsLocalSudo([
                        "{0} {1} install --register-service --force".format(python_cmd, setup_py)])
                return True                
        else:
                RunLog.error("Installing waagent from github...[failed]")
                RunLog.error("Unknown waagent verions")
                return False

def install_package(package):
        RunLog.info ("\nInstall_package: "+package)
        if (package == "waagent"):
                return install_waagent_from_github()
        if (package == "ez_setup"):
                return install_ez_setup()
        else:
                if ((current_distro == "ubuntu") or (current_distro == "debian")):
                        return AptgetPackageInstall(package)
                elif ((current_distro == "rhel") or (current_distro == "Oracle") or (current_distro == 'centos') or (current_distro == 'fedora')):
                        return yum_package_install(package)
                elif (current_distro == "SUSE") or (current_distro == "openSUSE") or (current_distro == "sles") or (current_distro == "opensuse"):
                        return zypper_package_install(package)
                else:
                        RunLog.error (package + ": package installation failed!")
                        RunLog.info (current_distro + ": Unrecognised Distribution OS Linux found!")
                        return False

def ConfigFilesUpdate():
        firewall_disabled = False
        update_configuration = False
        IsStartUp = False
        RunLog.info("Updating configuration files..")

        #Provisioning.MonitorHostName=n -> y, in Ubuntu it is n by default
        Run("sed -i s/Provisioning.MonitorHostName=n/Provisioning.MonitorHostName=y/g  /etc/waagent.conf > /tmp/waagent.conf")         
        
        # Disable 'requiretty' in sudoers
        Run("sed -r 's/^.*Defaults\s*requiretty.*$/#Defaults requiretty/g' /etc/sudoers -i")

        #Configuration of /etc/security/pam_env.conf
        Run("sed -i 's/^#REMOTEHOST/REMOTEHOST/g' /etc/security/pam_env.conf")
        Run("sed -i 's/^#DISPLAY/DISPLAY/g' /etc/security/pam_env.conf")
        pamconf = Run("cat /etc/security/pam_env.conf")

        if ((pamconf.find('#REMOTEHOST') == -1) and (pamconf.find('#DISPLAY') == -1)):
                RunLog.info("/etc/security/pam_env.conf updated successfully\n")
                update_configuration = True
                Run("echo '** Config files are updated successfully **' >> PackageStatus.txt")
        else:
                RunLog.error('Config file not updated\n')
                Run("echo '** updating of config file is failed **' >> PackageStatus.txt")
                update_configuration = False

        if (update_configuration == True):
                RunLog.info('Config file updation succesfully!\n')
                
        else:
                RunLog.error('[Error] Config file updation failed!')
                

        #Configuration of Firewall(Disable)
        if (current_distro == "ubuntu"):
                FirewallInfo = Run("ufw disable")
                if (FirewallInfo.find('Firewall stopped and disabled on system startup')):
                        RunLog.info('**Firewall Stopped Successfully** \n')
                        firewall_disabled = True
                else:
                        RunLog.error('**Failed to disable Firewall**')
                        firewall_disabled = False

        if ((current_distro == "SUSE") or (current_distro == "openSUSE")):
                FWBootInfo = Run("/sbin/yast2 firewall startup manual")
                if(FWBootInfo.find('Removing firewall from the boot process')):
                        RunLog.info('Firewall Removed successfully from boot process \n')

                FirewallInfo = Run("/sbin/rcSuSEfirewall2 status")

                if (FirewallInfo.find('SuSEfirewall2') and FirewallInfo.find('unused')):
                        RunLog.info('**Firewall Stopped Successfully** \n')
                        firewall_disabled = True
                else:
                        RunLog.error('**Failed to disable Firewall**')
                        firewall_disabled = False
        else:
                FirewallCmds = ("iptables -F","iptables -X","iptables -t nat -F","iptables -t nat -X","iptables -t mangle -F","iptables -t mangle -X","iptables -P INPUT ACCEPT","iptables -P OUTPUT ACCEPT","iptables -P FORWARD ACCEPT","systemctl stop iptables.service","systemctl disable iptables.service","systemctl stop firewalld.service","systemctl disable firewalld.service","chkconfig iptables off")
                output = ExecMultiCmdsLocalSudo(FirewallCmds)
                RunLog.info("Firewall disabled successfully\n")
                Run("echo '** Firewall disabled successfully **' >> PackageStatus.txt")
        #Verify startup file        
        StartupStatus= Run('ls '+startup_file+' 2>&1')
        if("No such file or directory" in StartupStatus):
                RunLog.info( "'"+startup_file+"' not available.. ")
                RunLog.info( "creating '+startup_file+'.. ")
                cmds=["touch "+startup_file,"chmod a+x "+startup_file,"echo '#!/bin/sh' > "+startup_file,"echo ' ' >> "+startup_file,"echo 'exit 0' >> "+startup_file]
                ExecMultiCmdsLocalSudo(cmds)
                if(current_distro == "fedora"):
                        cmds = ["service rc-local start","service rc-local status"]
                        ExecMultiCmdsLocalSudo(cmds)
                RunLog.info("'+startup_file+' created successfully\n")
                Run("echo '** Is '"+startup_file+"' created successfully **' >> PackageStatus.txt")
                IsStartUp = True
                
        else:
                RunLog.info("'"+startup_file+"' available.. ")
                Run("echo '** Is '"+startup_file+"' verified successfully **' >> PackageStatus.txt")
                IsStartUp = True

        if(firewall_disabled and update_configuration and IsStartUp):
                success = True
        else:
                success = False

        return success

def CheckCmdPyModExist(it):
        ret = True
        if(it.lower().startswith('python')):
                try:
                        pymod_name = it[it.index('-')+1:]
                        if(pymod_name == 'crypto'):
                                pymod_name = 'Crypto'
                        imp.find_module(pymod_name)
                except ImportError:
                        ret = False
                        RunLog.error("requisite python module: "+it+" is not exists on system.")
        else:
                output = Run('command -v '+it)
                if(output.find(it) == -1):
                        ret = False
                        RunLog.error("requisite command: "+it+" is not exists on system.")
        return ret

def RunTest():
        UpdateState("TestRunning")
        success = True
        try:
                import xml.etree.cElementTree as ET
        except ImportError:
                import xml.etree.ElementTree as ET

        #Parse the packages.xml file into memory
        packages_xml_file = ET.parse(packages_list_xml)
        xml_root = packages_xml_file.getroot()

        parse_success = False
        Run("echo '** Installing Packages for '"+current_distro+"' Started.. **' > PackageStatus.txt")
        for branch in xml_root:
                for node in branch:
                        if (node.tag == "packages"):
                                if(node.attrib['distro'] == 'universal'):
                                        required_packages_list = node.text.split(',')
                                elif(current_distro == node.attrib["distro"]):
                                        packages_list = node.text.split(",")
                        elif node.tag == "waLinuxAgent_link":
                                tar_link[node.attrib["name"]] = node.text
                        elif node.tag == "ez_setup_link":
                                tar_link[node.attrib["name"]] = node.text
                        elif node.tag == "rpm_link":
                                rpm_links[node.attrib["name"]] = node.text
                        elif node.tag == "tar_link":
                                tar_link[node.attrib["name"]] = node.text
        
        if not (current_distro=="coreos"):
                for package in packages_list:
                        if(not install_package(package)):
                                if(package in required_packages_list):
                                        if(not CheckCmdPyModExist(package)):
                                                success = False
                                                Run("echo '"+package+"' failed to install >> PackageStatus.txt")
                                else:
                                        Run("echo '"+package+"' failed to install but can be ingored for tests >> PackageStatus.txt")
                                #break
                        else:
                                Run("echo '"+package+"' installed successfully >> PackageStatus.txt")
        else:
                if (not coreos_package_install()):
                        success = False
                        Run("echo 'coreos packages failed to install' >> PackageStatus.txt")
                else:
                        Run("echo 'coreos support tools installed successfully' >> PackageStatus.txt")                

        if (current_distro == "SUSE") or (current_distro == "openSUSE") or (current_distro == "sles") or (current_distro == "opensuse"):
                iperf_cmd = Run("command -v iperf")
                iperf3_cmd = Run("command -v iperf3")
                if not iperf_cmd and iperf3_cmd:
                        RunLog.info('iperf3 has been installed instead of iperf from default repository')                        
                        if (ZypperPackageRemove('iperf') and download_and_install_rpm('iperf') and CheckCmdPyModExist('iperf')):
                                Run("echo 'iperf' installed successfully >> PackageStatus.txt")
                        else:
                                Run("echo 'iperf' failed to install >> PackageStatus.txt")
                                success = False

                                
        Run("echo '** Packages Installation Completed **' >> PackageStatus.txt")                
        if success == True:
                if not (current_distro=="coreos"):
                        ConfigFilesUpdate()
                if success == True:
                        RunLog.info('PACKAGE-INSTALL-CONFIG-PASS')
                        Run("echo 'PACKAGE-INSTALL-CONFIG-PASS' >> SetupStatus.txt")
                else:
                        RunLog.info('PACKAGE-INSTALL-CONFIG-FAIL')
                        Run("echo 'PACKAGE-INSTALL-CONFIG-FAIL' >> SetupStatus.txt")
        else:
                RunLog.info('PACKAGE-INSTALL-CONFIG-FAIL')
                Run("echo 'PACKAGE-INSTALL-CONFIG-FAIL' >> SetupStatus.txt")
        

#Code execution starts from here
if not os.path.isfile("packages.xml"):
        RunLog.info("'packages.xml' file is missing\n")
        exit ()

set_variables_OS_dependent()
UpdateRepos(current_distro)

RunTest()

