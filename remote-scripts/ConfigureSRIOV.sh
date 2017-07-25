#!/bin/bash

#Reference:  https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-create-vm-accelerated-networking
bootLogs=`dmesg`
if [[ $bootLogs =~ "Data path switched to VF" ]];
then
	echo "DATAPATH_SWITCHED_TO_VF"
else
	wget https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git/plain/tools/hv/bondvf.sh
	chmod +x ./bondvf.sh
	./bondvf.sh
	cp bondvf.sh /etc/init.d
	update-rc.d bondvf.sh defaults
	echo "SYSTEM_RESTART_REQUIRED"
fi
exit 0