#! /bin/bash

REPOSITORIES=repositories
ROOT_LOG=./$REPOSITORIES/logs.txt

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
	GROUP_NAME=$2
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


#used to format log message
log_message () {
	for var in "$@"; do
		echo "$(date -u): $var"
	done
}

#initializing a new repository
#new reposiotry can only be created by a sys-admin due to group and user managment in unix
if [[ $1 == "-init" ]]; then

	#check if owner is specified, otherwise set current $USER as owner
	OWNER=$USER
	if [[ ! -z $3  ]]; then
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
	fi

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
		if sudo mkdir $REPOSITORIES; then
			echo "dir: $REPOSITORIES created"
			sudo touch $ROOT_LOG
			sudo chmod 777 $ROOT_LOG
		else 
			1>&2 
			clean_up $REPO_NAME
			echo -e "\nAborting"
			exit 1
		fi
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
				#ensures that new files in the repository will belong to its parent group
				sudo chmod g+s ./$REPOSITORIES/$REPO_NAME

				echo "Group $GROUP_NAME now has rwx permissions"
			else 
				1>&2; clean_up $REPO_NAME $GROUP_NAME; echo "Aborting"
			fi 

			echo -e "\nAdding owner $OWNER to the group $GROUP_NAME"
			sudo usermod -a -G $GROUP_NAME $OWNER && echo -e "Successfully added" || (1>&2; clean_up $REPO_NAME $GROUP_NAME; exit 1)

			echo -e "\nPlease re-log or spawn a new instance of shell in order for groups to take effect"

		else
			echo "Failed to assign repository: $REPO_NAME to the group: $GROUP_NAME"
			clean_up $REPO_NAME $GROUP_NAME
			exit 1
		fi


		#creating folder to store history, backups  and user checked-out files
		mkdir ./$REPOSITORIES/$REPO_NAME/.lit
		touch ./$REPOSITORIES/$REPO_NAME/.lit/logs.txt
		echo "$(log_message "Repo was created by $USER" "Owner of the group $OWNER")" >> ./$REPOSITORIES/$REPO_NAME/.lit/logs.txt
	else 
		echo "Repository $REPO_NAME already exists"
		exit 1
	fi
	echo "$(log_message "Repo $REPO_NAME created by $USER")" >> $ROOT_LOG
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

	echo "$(log_message "Repo $DIR was deleted by $USER")" >> $ROOT_LOG
}


#wipes all of the repositories
if [[ $1 == "-delete-all" ]]; then 
	if ! find ./$REPOSITORIES/ -mindepth 1 | read; then echo "No repositories found, aborting" && exit 1; fi 
	read -p "Are you sure you want to delete everything (y/n)?" -n 1 -r
	echo 


	if [[ ! $REPLY = ^[Yy]$ ]]; then
		for DIR in ./$REPOSITORIES/*; do
			[[ -d "$DIR" ]] || continue
			remove_repo $DIR
		done
		echo "Done"
	else
		echo "Aborting"
	fi

	
	exit 1
fi

if [[ $1 == "-logs" ]];  then
	if [[ -f $ROOT_LOG ]]; then
		cat $ROOT_LOG
	else
		echo "Nothing is in the logs"
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
			echo "$(log_message "Access denied to user $USER")" >> ./$REPOSITORIES/$1/.lit/logs.txt
		fi
	else 
		echo "Repository $1 does not exist"
	fi
}

#create_backup () {
#	FILE_PATH="$1/"
#	BAK_PATH="./$REPOSITORIES/$FILE_PATH"
#	if [[   ]]
#	mkdir -p $FILE_PATH
#}

#functions available to each repository
if [[ "$1" == "-r" ]]; then
	if [[ ! -z $2 ]]; then
		ACCESS=$(can_access_repo $2)
		if  [[ "$ACCESS" == "y" ]]; then 
			GROUP_NAME=$(stat -c %G ./$REPOSITORIES/$2)
			REPO_LOG=./$REPOSITORIES/$2/.lit/logs.txt
			case $3 in
			"-d" | "-delete")
				if [[ $EUID -eq 0 || $(stat -c %U ./$REPOSITORIES/$2) == $USER ]]; then
					read -p "Are you sure you want to delete repository $2 (y/n)?" -n 1 -r
					echo 

					if [[ ! $REPLY = ^[Yy]$ ]]; then
						remove_repo ./$REPOSITORIES/$2
						echo "$(log_message "User $USER removed repo $2")" >> $ROOT_LOG
						echo "Done"
					else 
						echo "Aborting"
					fi	
				else
					echo -e "\nYou don't have the rights to remove this repository"
					echo "$(log_message "User $USER tried to remove repo $2")" >> $ROOT_LOG
				fi

				;;
			"-add-user")
				if getent passwd $4 > /dev/null 2>&1; then			
					if ! id -Gn $4 | grep -c $GROUP_NAME > /dev/null; then
						if sudo usermod -a -G $GROUP_NAME $4; then
							echo "Added user $4 to repo $2. User $4 needs to relog in order to gain access"
							echo "$(log_message "User $USER added user $4 to the repo")" >> $REPO_LOG
							exit 1
						else
							echo "$log_message "Failed to add user $4 to repo"" >> $REPO_LOG
							1>&2; echo "failed"; exit 1
						fi
			
					else 
						echo "User $4 is already added to the repository $2"
					fi
				else 
					echo "User $4 does not exist, aborting"; exit 1
				fi
				;;
			"-remove-user")
				if id -Gn $4 | grep -c $GROUP_NAME > /dev/null; then
					if sudo deluser $4 $GROUP_NAME; then
						echo "Removed user $4 from repo $2"
						echo "$(log_message "User $USER removed user $4 from repo $2")" >> $REPO_LOG
					else
						echo "$(log_message "Failed to remove user $4 from repo $2")" >> $REPO_LOG
						(1>&2; echo "Aborting"; exit 1)
					fi
				else 
					echo "User $4 does not belong to the group $GROUP_NAME";
				fi
				;;
			"-l" | "-list")
					echo -e  "Files available in repository $2:\n"
					find ./$REPOSITORIES/$2/* | cut -sd / -f 3- | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
				;;
			"-add-file")
				if [[ ! -z $4  ]]; then
					case "$4" in 
					*/)
						echo "No file provided (cannot be an empty directory)" && exit 1		
						;;
					*)
						DIR=./$REPOSITORIES/$2						
						FILE_DIR=$(dirname "$4")

						if [[ "$FILE_DIR" != "." ]]; then DIR=$DIR/$FILE_DIR; fi

						FILE=$(basename "$4")

						if [[ ! -f $DIR/$FILE ]]; then
							mkdir -p $DIR
							touch $DIR/$FILE
							echo "$(log_message "File $DIR/$FILE has been created by $USER")" >> $REPO_LOG
							echo "FILE $DIR/$FILE has been created" && exit 1
							
						else 
							echo "FILE $DIR/$FILE already exists" && exit 1
						fi
						;;
					esac
				else 
					echo "Please provide file name"
				fi
				;;
			"-remove-file")
				if [[ ! -z $4 ]]; then
					case "$4" in
					*/)
						echo "Cannot remove dir, please remove all the files from the dir first" && exit 1	
						;;
					*)
						DIR=./$REPOSITORIES/$2/$4

						if [[ -e $DIR ]]; then
							if rm $DIR; then
								echo "FILE $DIR has been removed"
								echo "$(log_message "FILE $DIR has been removed by $USER")" >> $REPO_LOG
								find ./$REPOSITORIES/$2/* -type d -empty -delete || 2>&1
							else
								echo -e "Failed to remove file"; 2>&1
							fi
						else
							echo "FILE $DIR does not exist" && exit 1
						fi
					esac
				else 
					echo "Please provide file name"
				fi
				;;
			"-check-out")
				if [[ ! -z $4 ]]; then
					case $4 in
					*/)
						echo "Cannot checkout directories, must be a single file"
						;;
					*)
		#				if [[ -f ./$REPOSITORIES/$2/$4 ]]; then
		#											
		#				fi
						;;
					esac
				else 
					echo "Please provide file name"
				fi
				;;
			#TODO add further support
			"-check-in")
				;;
			"-logs")
				cat $REPO_LOG
				;;
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
