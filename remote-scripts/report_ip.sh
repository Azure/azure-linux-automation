#!/bin/sh
mimicArpServer=$1
username=$2
sshKey=$3
if [ -z "$mimicArpServer" -o -z "$username" -o -z "$sshKey" ]; then
    echo "usage: $0 mimic_arp_server username ssh_key"
    exit 1
fi

ipMaxTry=10
echo -----------------------------
date
mac=$(ifconfig -a eth0 | grep -oP "([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}")
mac=$(echo $mac | tr -d ':' | tr '[:upper:]' '[:lower:]')
echo Try get ip
for i in $(seq 1 $ipMaxTry)
do
    echo Iterate $i ...
    ipconfig=$(ifconfig eth0)
    echo $ipconfig
    ip=$(echo $ipconfig | grep -oP "((?<=inet )|(?<=inet addr:))(\d{1,3}.){3}\d{1,3}")
    if [ -n "$ip" ]; then
        break
    fi
    sleep 5
done

if [ -z "$ip" ]; then
    echo Get IP failed ...
    exit 1
fi
log="Add $mac -\> $ip"
echo $log
echo $ip > $mac

#escape dollar before date to run date commend on mimic arp server
ssh -i ~/.ssh/$sshKey $username@$mimicArpServer "echo \$(date) : $log >> ~/mimic-arp/log"
scp -i ~/.ssh/$sshKey $mac $username@$mimicArpServer:~/mimic-arp
