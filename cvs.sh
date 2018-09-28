#! /bin/bash

REPOSITORIES=repositories

create_group () {
	GROUP_NAME=$1
	#check if the group exists
	if  grep -q "^{$GROUP_NAME}" /etc/group; then
		echo "failed"
	else 
		#try adding the group
		sudo groupadd $GROUP_NAME && echo "success" || 1>&2
	fi
}

clean_up () {
	GROUP_NAME=$2
	DIR=./$REPOSITORIES/$1
	
	#remove dir if exists
	if [[ ! -z $1 && -d $DIR ]]; then
		sudo rm -r $DIR && echo "Cleaning up repository directory" | 1>&2
	fi
	
	#remove group if exists
	if [[ ! -z $GROUP_NAME && ! -z $(grep -q "^{$GROUP_NAME}" /etc/group) ]] ; then
		sudo groupdel "$GROUP_NAME" && echo "Removing group" | 1>&2
	fi
}

#If no params are passed, show help info
if [ $# -eq 0 ]; then
	echo "This will be help menu"
	exit 1	
fi

#initializing a new repository
#new reposiotry can only be created by a sys-admin due to group and user managment in unix
if [[ $1 == "-init" ]]; then
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
		sudo mkdir $REPOSITORIES && echo "dir: $REPOSITORIES created" | (1>&2; clean_up $REPO_NAME echo "Aborting"; exit 1)
	fi		

	if [ ! -e $REPOSITORIES/$REPO_NAME ]; then 
		echo "creating repository called: $REPO_NAME"
		sudo mkdir ./$REPOSITORIES/$REPO_NAME

		#creating a group for the repository in order to grant access rights later on
		#TODO assign specified user as the owner and add the user to the project group
		GROUP_NAME="$REPO_NAME-repo"
		if [[ $(create_group $GROUP_NAME) != "success" ]]; then
			echo "Failed to create group, aborting"
			clean_up $REPO_NAME
			exit 1
		fi

		echo "Group $GROUP_NAME has been successfully created"
		echo "Assigning group: $GROUP_NAME to repository: $REPO_NAME"

		#put the new repository under its own group
		if sudo chgrp $GROUP_NAME ./$REPOSITORIES/$REPO_NAME; then
			echo "Repository: $REPO_NAME now belongs to the group: $GROUP_NAME"
		else
			echo "Failed to assign repository: $REPO_NAME to the group: $GROUP_NAME. Aborting"
			clean_up $REPO_NAME $GROUP_NAME
			exit 1
		fi
			
	else 
		echo "Repository $REPO_NAME already exists" 1>&2
		exit 1
	fi
	echo "Done"
	exit 1
fi

remove_repo () {
	DIR=$1
	GROUP_NAME=$(stat -c %G $DIR)
	
	echo "removing group: $GROUP_NAME"
	sudo groupdel $GROUP_NAME && echo "Removed" | (1>&2; exit 1)

	echo "removing repository: $DIR" 
	sudo rm -r $DIR && echo "Removed" | (1>&2; exit 1) 

	echo
}

if [[ $1 == "-delete" && ! -z $2 ]]; then 
	if ! find $REPOSITORIES/ -mindepth 1 | read; then echo "No repositories found, aborting" && exit 1; fi 
	if [[ "$2" == "-a" || "$2" == "-all" ]]; then
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

	elif [[ -d $REPOSITORIES/$2 ]]; then
		read -p "Are you sure you want to delete repository $2 (y/n)?" -n 1 -r
		echo 

		if [[ ! $REPLY = ^[Yy]$ ]]; then
			remove_repo ./$REPOSITORIES/$2
			echo "Done"
		fi	
	else 
		echo "Repoitory $2 does not exist"
	fi 	
else 
	echo "No argument provided for deletion"

exit 1

fi
