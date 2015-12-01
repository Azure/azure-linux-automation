#!/bin/bash

while echo $1 | grep ^- > /dev/null; do
    eval $( echo $1 | sed 's/-//g' | tr -d '\012')=$2
    shift
    shift
done

newUser=$newUser
newPassword=$newPassword

AddUser()
{
	egrep "^$newUser" /etc/passwd >/dev/null
    if [ $? -eq 0 ]; then
        echo "$newUser exists!"
        userdel -r $newUser
    fi
	if [ -e /etc/debian_version ]; then
		echo -e $newPassword'\n'$newPassword | adduser --gecos "" --force-badname -q $newUser
		isUserAdded=$?
	elif [ -e /etc/redhat-release ]; then
		adduser $newUser -c "AutomationUser" -m
		isUserAdded=$?
		if [ $isUserAdded = "0" ]; then
			echo User added $newUser
			echo -e $newPassword'\n'$newPassword | passwd $newUser
			isUserAdded=$?
		fi
		
	elif [ -e /etc/SuSE-release ]; then
		useradd $newUser -c "AutomationUser" -m
		isUserAdded=$?
		if [ $isUserAdded = "0" ]; then
			echo User added $newUser
			echo -e $newPassword'\n'$newPassword | passwd $newUser
			isUserAdded=$?
		fi
	elif [ -e /etc/os-release ]; then
		tmp=`cat /etc/os-release`
		if [[ "$tmp" == *coreos* ]]; then
			useradd $newUser -c "AutomationUser" -m
			isUserAdded=$?
			if [ $isUserAdded = "0" ]; then
				echo User added $newUser
				echo $newUser:$newPassword | chpasswd
				isUserAdded=$?
			fi
		fi
	fi

	
	if [ $isUserAdded = "0" ]; then
        echo "$newUser ALL=(ALL) ALL" > /etc/sudoers.d/$newUser
		chmod 0440 /etc/sudoers.d/$newUser
	    echo "AUTOMATION_USER_ADDED"
	else
	    echo "AUTOMATION_USER_ADD_FAILED"
	fi

}
AddUser
exit 0
