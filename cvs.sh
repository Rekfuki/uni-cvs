#! /bin/bash

REPOSITORIES=repositories

create_group () {
	GROUP_NAME=$1
	#check if the group exists
	if  grep -q "^$GROUP_NAME" /etc/group; then
		echo "failed"
	else 
		#try adding the group
		sudo groupadd $GROUP_NAME && echo "success" || 1>&2
	fi
}

clean_up () {
	GROUP_NAM=$2
	DIR=./$REPOSITORIES/$1

	echo "Reverting changes..."

	#remove dir if exists
	if [[ ! -z $1 && -d $DIR ]]; then
		echo -e "\nRemoving dir $DIR"
		echo
		sudo rm -r $DIR && echo "Removed" | 1>&2
	fi
	#remove group if exists
	if [[ ! -z $GROUP_NAME &&  $(grep -c "^$GROUP_NAME:" /etc/group) -gt 0 ]]; then
		echo -e "\nRemoving group $GROUP_NAME"
		echo 
		sudo groupdel "$GROUP_NAME" && echo "Removed" | 1>&2
	fi
}

#If no params are passed, show help info
if [ $# -eq 0 ]; then
	echo "This will be help menu"
	exit 1	
fi

#use to activate addded group to the user without 
activate_group () {
	(	
		if exec sg $1 newgrp `id -gn`; then
			return 0
		else
			1>&2
		fi
		return 1
	)
}



#initializing a new repository
#new reposiotry can only be created by a sys-admin due to group and user managment in unix
if [[ $1 == "-init" ]]; then

	#check if owner is specified, otherwise set current $USER as owner
	OWNER=$USER
	case $3 in
	"-o" | "-owner")
		if [[ ! -z $4 ]]; then
			if getent passwd $4 > /dev/null 2>&1; then
				OWNER=$4
			else
				echo "User $4 does not exist, aborting"
				exit 1
			fi
		else
			echo -e "\nflag -owner requires owner name, ex: -init <repo_name> -owner <user>"
			exit 1
		fi
		;;
	*)
		echo "Unsupported flag $3, display help"
		exit 1;
	esac

	REPO_NAME=$2
	#check if repo name is provided
	if [ -z $REPO_NAME ]; then
		echo "Please provide a new name for the repository"
		echo "ex: -init your-repo-name"
		exit 1
	fi
		
	#if repositories dir does not exist new one is created
	#repositories folder will house all the repositories
	if [ ! -d "repositories" ]; then
		echo "repositories directory not found, intializing"
		sudo mkdir $REPOSITORIES && echo "dir: $REPOSITORIES created" || (1>&2; clean_up $REPO_NAME; echo -e "\nAborting"; exit 1)
	fi		
	
	if [ ! -e $REPOSITORIES/$REPO_NAME ]; then 
		echo "creating repository called: $REPO_NAME"
		sudo mkdir ./$REPOSITORIES/$REPO_NAME || (1>&2; clean_up $REPO_NAME; exit 1)

		#assigning directory owner
		sudo chown -R $OWNER ./$REPOSITORIES/$REPO_NAME && echo -e "\nGiving ownership to $OWNER" || (1>&2; clean_up $REPO_NAME; exit 1)

		#creating group for the project
		GROUP_NAME="$REPO_NAME-repo"
		if [[ $(create_group $GROUP_NAME) != "success" ]]; then
			echo "Failed to create group, aborting"
			clean_up $REPO_NAME $GROUP_NAME
			exit 1
		fi

		echo -e "\nGroup $GROUP_NAME has been successfully created"
		echo "Assigning group: $GROUP_NAME to repository: $REPO_NAME"

		#put the new repository under its own group
		if sudo chgrp $GROUP_NAME ./$REPOSITORIES/$REPO_NAME; then
			echo -e  "\nRepository: $REPO_NAME now belongs to the group: $GROUP_NAME"
			echo "Giving group $GROUP_NAME rwx permissions"

			#give the group rwx perms
			if sudo chmod g+rwx ./$REPOSITORIES/$REPO_NAME; then 
				echo "Group $GROUP_NAME now has rwx permissions"
			else 
				1>&2; clean_up $REPO_NAME $GROUP_NAME; echo "Aborting"
			fi 

			echo -e "\nAdding owner $OWNER to the group $GROUP_NAME"
			sudo usermod -a -G $GROUP_NAME $OWNER && echo -e "Successfully added" || (1>&2; clean_up $REPO_NAME $GROUP_NAME; exit 1)

			#in order for groups to take effect user normally has to relog
			#however, im using a little hack
		#	echo "Activating  group $GROUP_NAME"
		#	if $(activate_group $GROUP_NAME); then 
		#		clean_up $REPO_NAME $GROUP_NAME && echo "Aborting"
		#		exit 1
		#	fi
		#
		#	echo -e "\nGroup has been activated"
				
			echo -e "\nPlease re-log or spawn a new instance of shell in order for groups to take effect"

		else
			echo "Failed to assign repository: $REPO_NAME to the group: $GROUP_NAME. Aborting"
			exit 1
		fi
			
	else 
		echo "Repository $REPO_NAME already exists"
		exit 1
	fi
	echo "Done"
	exit 1
fi

#used to remove repository
#exported as a seperate function for refactoring
remove_repo () {
	DIR=$1
	GROUP_NAME=$(stat -c %G $DIR)
	
	echo -e "\nRemoving group: $GROUP_NAME"
	sudo gpasswd $GROUP_NAME -M '' && sudo groupdel $GROUP_NAME && echo "Removed" || (1>&2; exit 1)

	echo -e "\nRemoving repository: $DIR" 
	sudo rm -r $DIR && echo "Removed" || (1>&2; exit 1) 

	echo
}


#wipes all of the repositories
if [[ $1 == "-delete-all" ]]; then 
	if ! find ./$REPOSITORIES/ -mindepth 1 | read; then echo "No repositories found, aborting" && exit 1; fi 
	read -p "Are you sure you want to delete everything (y/n)?" -n 1 -r
	echo 


	if [[ ! $REPLY = ^[Yy]$ ]]; then
		for DIR in ./$REPOSITORIES/*; do
			remove_repo $DIR
		done
		echo "Done"
	else
		echo "Aborting"
	fi

exit 1

fi

#checks if the repository exists
can_access_repo () {	
	if [[ -d ./$REPOSITORIES/$1 ]]; then 	
		GROUP_NAME=$(stat -c %G ./$REPOSITORIES/$1)
		if  [[ "$EUID" -eq 0 || "$(stat -c %U ./$REPOSITORIES/$1)" == $USER  || "$(id -Gn $USER | grep -c $GROUP_NAME)" -gt 0 ]]; then
 			echo y
			return
		else 
			echo "You don't have access rights to the repository"
		fi
	else 
		echo "Repository $1 does not exist"
	fi
}


#functions available to each repository
if [[ "$1" == "-r" ]]; then
	if [[ ! -z $2 ]]; then
		ACCESS=$(can_access_repo $2)
		if  [[ "$ACCESS" == "y" ]]; then 
			GROUP_NAME=$(stat -c %G ./$REPOSITORIES/$2)
			case $3 in
			"-d" | "-delete")
				if [[ $EUID -eq 0 || $(stat -c %U ./$REPOSITORIES/$2) == $USER ]]; then
					read -p "Are you sure you want to delete repository $2 (y/n)?" -n 1 -r
					echo 

					if [[ ! $REPLY = ^[Yy]$ ]]; then
						remove_repo ./$REPOSITORIES/$2
						echo "Done"
					else 
						echo "Aborting"
					fi	
				else
					echo -e "\nYou don't have the rights to remove this repository"
				fi

				;;
			"-add-user")
				if getent passwd $4 > /dev/null 2>&1; then			
					if ! id -Gn $4 | grep -c $GROUP_NAME > /dev/null; then
						sudo usermod -a -G $GROUP_NAME $4 && echo "Added user $4 to group $GROUP_NAME" || (1>&2; echo "failed"; exit 1)
					else 
						echo "User $4 is already added to the repository $2"
					fi
				else 
					echo "User $4 does not exist, aborting"; exit 1
				fi
				;;
			"-remove-user")
				if id -Gn $4 | grep -c $GROUP_NAME > /dev/null; then
					sudo deluser $4 $GROUP_NAME && echo "Removed user $4 from repo $2" || (1>&2; echo "Aborting"; exit 1)
				else 
					echo "User $4 does not belong to the group $GROUP_NAME";
				fi
				;;
			"-l" | "-list")
				
				;;
			#TODO add further support
			*)
				echo "show help"
				;;
			esac
		else 
			echo "$ACCESS"
		fi	
	else 
		echo "Show help for -r"
	fi

	exit 1
fi
