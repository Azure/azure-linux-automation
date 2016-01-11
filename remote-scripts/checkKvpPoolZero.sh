#!/bin/bash
if [[ "`cat /var/lib/hyperv/.kvp_pool_0`" =~ NdDriverVersion.*142 ]]; then
    echo "NdDriverVersion == 142 found in /var/lib/hyperv/.kvp_pool_0"
    echo "Starting kernel update..."
    beforeUpdate=`uname -r`
    zypper --non-interactive --no-gpg-checks update kernel*
    afterUpdate=`uname -r`
    if [ $beforeUpdate == $afterUpdate ];then
        echo "Skipping reboot as no update available for kernel $beforeUpdate"
    else
        echo "Rebooting VM in 60 seconds ... Ctrl+C to abort reboot."
        sleep 60
        init 6
    fi
else
    echo "NdDriverVersion == 142 not found in /var/lib/hyperv/.kvp_pool_0"
fi
