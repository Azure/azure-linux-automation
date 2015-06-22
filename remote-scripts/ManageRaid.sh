#!/bin/bash
#V-SHISAV@MICROSOFT.COM

#HOW TO PARSE THE ARGUMENTS.. SOURCE - http://stackoverflow.com/questions/4882349/parsing-shell-script-arguments

while echo $1 | grep ^- > /dev/null; do
    eval $( echo $1 | sed 's/-//g' | tr -d '\012')=$2
    shift
    shift
done
diskNames=$diskNames
create=$create
RaidName=$RaidName
totalDisks=$totalDisks
diskNames=${diskNames//^/ }
if [ "$create" = "yes" ]; then
	echo y | mdadm --create $RaidName --level 0 --raid-devices $totalDisks $diskNames
	exitVal=$?
fi
exit $exitVal