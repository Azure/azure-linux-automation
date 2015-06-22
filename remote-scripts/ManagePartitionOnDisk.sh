#!/bin/bash
#V-SHISAV@MICROSOFT.COM

#HOW TO PARSE THE ARGUMENTS.. SOURCE - http://stackoverflow.com/questions/4882349/parsing-shell-script-arguments

while echo $1 | grep ^- > /dev/null; do
    eval $( echo $1 | sed 's/-//g' | tr -d '\012')=$2
    shift
    shift
done
diskName=$diskName
delete=$delete
create=$create
forRaid=$forRaid
if [ "$create" = "yes" ]; then
    if [ "$forRaid" = "yes" ]; then
        (echo n; echo p; echo 1; echo; echo; echo t; echo fd;  echo w) | fdisk $diskName
        exitVal=$?
    elif [ "$forRaid" = "no" ]; then
        (echo n; echo p; echo 1; echo; echo; echo w) | fdisk $diskName
        exitVal=$?
    fi
fi
if [ "$delete" = "yes" ]; then
    (echo d; echo w;) | fdisk $diskName
    exitVal=$?
fi
exit $exitVal