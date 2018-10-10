#! /bin/bash

#set -euo pipefail

REPOSITORIES=repositories
ROOT_LOG=./$REPOSITORIES/logs.txt

create_group () {
	GROUP_NAME=$1
	#check if the group exists
	if  grep -q "^$GROUP_NAME" /etc/group; then
		echo "failed"
	else 
		#try adding the group
		sudo groupadd "$GROUP_NAME" && echo "success"
	fi
}

clean_up () {
	GROUP_NAME=$2
	DIR=./$REPOSITORIES/$1

	echo "Reverting changes..."

	#remove dir if exists
	if [[ -n $1 && -d $DIR ]]; then
		echo -e "\\nRemoving dir $DIR"
		echo
		sudo rm -r "$DIR" && echo "Removed"
	fi
	#remove group if exists
	if [[ -n "$GROUP_NAME" &&  $(grep -c "^$GROUP_NAME:" /etc/group) -gt 0 ]]; then
		echo -e "\\nRemoving group $GROUP_NAME"
		echo 
		sudo groupdel "$GROUP_NAME" && echo "Removed"
	fi
}

#used to format log message
log_message () {
	for var in "$@"; do
		echo "$(date -u): $var"
	done
}

#used to remove repository
#exported as a seperate function for refactoring
remove_repo () {
	DIR=$1
	GROUP_NAME=$(stat -c %G "$DIR")
	
	echo -e "\\nRemoving group: $GROUP_NAME"
	sudo gpasswd "$GROUP_NAME" -M '' && sudo groupdel "$GROUP_NAME" && echo "Removed" || exit 1

	echo -e "\\nRemoving repository: $DIR" 
	sudo rm -r "$DIR" && echo "Removed" || exit 1

	log_message "Repo $DIR was deleted by $USER" >> $ROOT_LOG
}

create_backup () {
	FP="$1"
	DIRECTORY="$(dirname "$FP")"
	BACKUPS="./$REPOSITORIES/$2/.lit/backups"

	if [[ "$(dirname "$FP")" == "." ]]; then DIRECTORY=""; fi
	if [[ ! -d "$BACKUPS/$DIRECTORY" ]]; then
		mkdir -p "$BACKUPS/$DIRECTORY" || return 1
	fi

	DT="$(date "+%Y-%m-%dT%H:%M:%SZ")"

	FN="$(basename "$FP")"

	FN="$FN.$DT"
	
		
	cp "./$REPOSITORIES/$2/$FP" "$BACKUPS/$DIRECTORY/$FN" || return 1 
	
	return 0
}


list_repo_files () {
	echo -e  "Files available in repository $1:\\n"
	#find ./$REPOSITORIES/$1/ -type f -not -path '^(\..*|.*?\.lit.*|.*\.lck)$' | cut -sd / -f 4-
	find ./"$REPOSITORIES"/"$1" -type f -not -path '*/.lit/*' -a -not -name '*.lck' | cut -sd / -f 4-
}

list_backups () {
	echo -e "\\nAvailable backups for rollback:"
	find ./"$REPOSITORIES"/"$1"/.lit/backups/ -type f | cut -sd / -f 6- 
}

list_editing_files () {
	echo -e "Files you have checked out:\\n"
	find ./"$REPOSITORIES"/"$1"/.lit/"$USER"/ -type f | cut -sd / -f 6- | grep . 
}

#checks if the repository exists
can_access_repo () {	
	if [[ -d "./$REPOSITORIES/$1" ]]; then 	
		GROUP_NAME=$(stat -c %G "./$REPOSITORIES/$1")
		if  [[ "$EUID" -eq 0 || "$(stat -c %U "./$REPOSITORIES/$1")" == "$USER"  || "$(id -Gn "$USER" | grep -c "$GROUP_NAME")" -gt 0 ]]; then
 			echo y
			return
		else 
			echo "You don't have access rights to the repository"
			log_message "Access denied to user $USER for repository $1" >> "$ROOT_LOG"
		fi
	else 
		echo "Repository $1 does not exist"
		list_available_repos
	fi
}

list_available_repos () {
	echo -e "\\nHere is a list of repositories you have access to:"
	for dir in ./"$REPOSITORIES"/; do
		GROUP_NAME=$(stat -c %G "$dir")
		if  [[ "$EUID" -eq 0 ]] || \
		    [[ "$(stat -c %U "$dir")" == "$USER" ]] || \
		    [[ "$(id -Gn "$USER" | grep -c "$GROUP_NAME")" -gt 0 ]]; then
		basename "$dir"
	fi
	done
	
	echo -e "\\nIf you don't see any repositories, you might need to relog in order for groups to take an effect"
}

print_help () {
	normal="\033[0m"
	bold="\033[1m"
	dim="\033[2m"
	italic="\033[3m"
	underlined="\033[4m"

	echo -e "\n${bold}HELP:${normal}\n"
	echo -e "${bold}cvs -init ${italic}repo_name${normal}${dim} -owner ${italic}user ${normal}: intialize repository"
	echo -e "${bold}cvs -list ${normal}: list available repositories"
	echo -e "${bold}cvs -delete-all ${normal}: delete all repositories"
	echo -e "${bold}cvs -logs ${normal}: display logs"
	echo -e "${bold}cvs -r/-repo ${italic}repo_name${normal}${bold} ${underlined}[OPTIONS]${normal} : perform actions on a repository"

	echo -e "\n${bold}OPTIONS:${normal}\n"
	echo -e "${bold}-d/-delete${normal} : delete repository"
	echo -e "${bold}-l/-list${normal} : list repository files"
	echo -e "${bold}-editing${normal} : list editing files"
	echo -e "${bold}-logs${normal} : display repository log"
	echo -e "${bold}-zip${normal} : compress repository and place it in \$HOME"
	echo -e "${bold}-add-user ${italic}user${normal} : add user to repository"
	echo -e "${bold}-remove-user ${italic}user${normal} : remove user from repository"
	echo -e "${bold}-add-file ${italic}file${normal} : add file to repository"
	echo -e "${bold}-remove-file ${italic}file${normal} : remove file from repository"
	echo -e "${bold}-check-out ${italic}file${normal} : check-out file from repository"
	echo -e "${bold}-check-in ${italic}file${normal} : check-in file to repository"
	echo -e "${bold}-restore ${italic}backup${normal} : restore state from backup"
	echo -e "${bold}-edit ${italic}file${normal} : edit checked-out file"
	echo -e "${bold}-view ${italic}file${normal} : view file contents"
	echo ""
}

case "$1" in
"-init")

	#check if owner is specified, otherwise set current $USER as owner
	OWNER=$USER
	if [[ -n $3  ]]; then
		case $3 in
		"-o" | "-owner")
			if [[ -n $4 ]]; then
				if getent passwd "$4" > /dev/null 2>&1; then
					OWNER=$4
				else
					echo "User $4 does not exist, aborting"
					exit 1
				fi
			else
				echo -e "\\nflag -owner requires owner name, ex: -init <repo_name> -owner <user>"
				exit 1
			fi
			;;
		*)
			print_help
			exit 1;
		esac
	fi

	REPO_NAME=$2
	#check if repo name is provided
	if [[ -z "$REPO_NAME" ]]; then
		echo "Please provide a new name for the repository"
		echo "ex: -init your-repo-name"
		exit 1
	fi
		
	#if repositories dir does not exist new one is created
	#repositories folder will house all the repositories
	if [[ ! -d "$REPOSITORIES" ]]; then
		echo "repositories directory not found, intializing"
		if sudo mkdir $REPOSITORIES; then
			echo "dir: $REPOSITORIES created"
			sudo touch $ROOT_LOG
			sudo chmod 777 $ROOT_LOG
		else 
			clean_up "$REPO_NAME"
			echo -e "\\nAborting"
			exit 1
		fi
	fi		
	
	if [[ ! -e "$REPOSITORIES/$REPO_NAME" ]]; then 
		echo "creating repository called: $REPO_NAME"
		sudo mkdir "./$REPOSITORIES/$REPO_NAME" || (clean_up "$REPO_NAME"; exit 1)

		#assigning directory owner
		if ! { sudo chown -R "$OWNER" "./$REPOSITORIES/$REPO_NAME" && echo -e "\\nGiving ownership to $OWNER"; }; then
			clean_up "$REPO_NAME"
			exit 1
		fi

		#creating group for the project
		GROUP_NAME="$REPO_NAME-repo"
		if [[ $(create_group "$GROUP_NAME") != "success" ]]; then
			echo "Failed to create group, aborting"
			clean_up "$REPO_NAME" "$GROUP_NAME"
			exit 1
		fi

		echo -e "\\nGroup $GROUP_NAME has been successfully created"
		echo "Assigning group: $GROUP_NAME to repository: $REPO_NAME"

		#put the new repository under its own group
		if sudo chgrp "$GROUP_NAME" "./$REPOSITORIES/$REPO_NAME"; then
			echo -e  "\\nRepository: $REPO_NAME now belongs to the group: $GROUP_NAME"
			echo "Giving group $GROUP_NAME rwx permissions"

			#give the group rwx perms
			if sudo chmod g+rwx "./$REPOSITORIES/$REPO_NAME"; then 
				#ensures that new files in the repository will belong to its parent group
				sudo chmod g+s "./$REPOSITORIES/$REPO_NAME"

				echo "Group $GROUP_NAME now has rwx permissions"
			else 
				clean_up "$REPO_NAME" "$GROUP_NAME"
				echo "Aborting"
			fi 

			echo -e "\\nAdding owner $OWNER to the group $GROUP_NAME"
			if ! { sudo usermod -a -G "$GROUP_NAME" "$OWNER" && echo "Successfully added"; }; then
				clean_up "$REPO_NAME" "$GROUP_NAME"
				exit 1
			fi

			echo -e "\\nPlease re-log or spawn a new instance of shell in order for groups to take effect"

		else
			echo "Failed to assign repository: $REPO_NAME to the group: $GROUP_NAME"
			clean_up "$REPO_NAME" "$GROUP_NAME"
			exit 1
		fi


		#creating folder to store history, backups  and user checked-out files
		mkdir "./$REPOSITORIES/$REPO_NAME/.lit"
		touch "./$REPOSITORIES/$REPO_NAME/.lit/logs.txt"
		log_message "Repo was created by $USER" "Owner of the group $OWNER" >> ./"$REPOSITORIES/$REPO_NAME"/.lit/logs.txt
	else 
		echo "Repository $REPO_NAME already exists"
		exit 1
	fi
	log_message "Repo $REPO_NAME created by $USER" >> $ROOT_LOG
	echo "Done"
	
	exit 1
	;;
"-list")
	list_available_repos
	;;
"-delete-all")
	if ! find ./"$REPOSITORIES"/ -mindepth 1 | read -r; then echo "No repositories found, aborting" && exit 1; fi 
	read -p "Are you sure you want to delete everything (y/n)?" -n 1 -r
	echo 


	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Aborting"
	else
		for DIR in ./"$REPOSITORIES"/*; do
			[[ -d "$DIR" ]] || continue
			remove_repo "$DIR"
		done
		echo "Done"
	fi

	
	exit 1
	;;
"-logs")
	if [[ -f $ROOT_LOG ]]; then
		cat $ROOT_LOG
	else
		echo "Nothing is in the logs"
	fi
	exit 1
	;;
"-help")
	print_help
	;;
"-r" | "-repo")
	if [[ -n $2 ]]; then
		ACCESS=$(can_access_repo "$2")
		if  [[ "$ACCESS" == "y" ]]; then 
			GROUP_NAME=$(stat -c %G "./$REPOSITORIES/$2")
			REPO_LOG=./$REPOSITORIES/$2/.lit/logs.txt
			case $3 in
			"-d" | "-delete")
				if [[ $EUID -eq 0 || "$(stat -c %U "./$REPOSITORIES/$2")" == "$USER" ]]; then
					read -p "Are you sure you want to delete repository $2 (y/n)?" -n 1 -r
					echo 

					if [[ ! $REPLY =~ ^[Yy]$ ]]; then
						echo "Aborting"
					else 
						remove_repo "./$REPOSITORIES/$2"
						log_message "User $USER removed repo $2" >> "$ROOT_LOG"
						echo "Done"
					fi	
				else
					echo -e "\\nYou don't have the rights to remove this repository"
					log_message "User $USER tried to remove repo $2" >> "$ROOT_LOG"
				fi

				;;
			"-add-user")
				if [[ -n $4 ]]; then
					if getent passwd "$4" > /dev/null 2>&1; then			
						if ! id -Gn "$4" | grep -c "$GROUP_NAME" > /dev/null; then
							if sudo usermod -a -G "$GROUP_NAME" "$4"; then
								echo "Added user $4 to repo $2. User $4 needs to relog in order to gain access"
								log_message "User $USER added user $4 to the repo" >> "$REPO_LOG"
								exit 1
							else
								log_message "Failed to add user $4 to repo" >> "$REPO_LOG"
								echo "failed"
								exit 1
							fi
				
						else 
							echo "User $4 is already added to the repository $2"
						fi
					else 
						echo "User $4 does not exist, aborting"; exit 1
					fi
				else
					echo "Please provide username"
				fi
				;;
			"-remove-user")
				if id -Gn "$4" | grep -c "$GROUP_NAME" > /dev/null; then
					if sudo deluser "$4" "$GROUP_NAME"; then
						echo "Removed user $4 from repo $2"
						log_message "User $USER removed user $4 from repo $2" >> "$REPO_LOG"
					else
						log_message "Failed to remove user $4 from repo $2" >> "$REPO_LOG"
						echo "Aborting";
						exit 1
					fi
				else 
					echo "User $4 does not belong to the group $GROUP_NAME";
				fi
				;;
			"-l" | "-list")
					list_repo_files "$2"
				;;
			"-add-file")
				if [[ -n $4  ]]; then
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
							mkdir -p "$DIR"
							touch "$DIR/$FILE"
							log_message "File $DIR/$FILE has been created by $USER" >> "$REPO_LOG"
							echo "FILE $DIR/$FILE has been created"
							exit 1
							
						else 
							echo "FILE $DIR/$FILE already exists"
							exit 1
						fi
						;;
					esac
				else 
					echo "Please provide file name"
				fi
				;;
			"-remove-file")
				if [[ -n $4 ]]; then
					case "$4" in
					*/)
						echo "Cannot remove dir, please remove all the files from the dir first" && exit 1	
						;;
					*)
						DIR=./$REPOSITORIES/$2/$4

						if [[ -e $DIR ]]; then
							if rm "$DIR"; then
								echo "FILE $DIR has been removed"
								log_message "FILE $DIR has been removed by $USER" >> "$REPO_LOG"
								find ./"$REPOSITORIES/$2"/* -type d -empty -delete
							else
								echo -e "Failed to remove file"
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
				if [[ -n $4 ]]; then
					case $4 in
					*/)
						echo "Cannot checkout directories, must be a single file"
						;;
					*)
						if [[ -f ./$REPOSITORIES/$2/$4 ]]; then
							DIR="./$REPOSITORIES/$2"
							
							if [[ -f $DIR/$4.lck  ]]; then
								echo "File is currently being edited by $(grep . "$DIR/$4.lck")"
								exit 1
							fi

							if create_backup "$4" "$2"; then
								log_message "Backup of file $4 created" >> "$REPO_LOG"
							else
								echo "Failed to create backup"
								exit 1
							fi

							if [[ ! -d $DIR/.lit/$USER ]]; then mkdir "$DIR/.lit/$USER"; fi
							
							#creating a lock file and writing the user who is editing the file
							#in order to prevent other users from editing the file
							echo "$USER" > "$DIR/$4.lck"
							
							BASE="$(dirname "$4")"
							if [[ -n "$BASE" ]]; then		
								if [[ "$BASE" != "." ]]; then
									mkdir -p "$DIR/.lit/$USER/$BASE" || exit 1
								else
									BASE=""
								fi
							fi
							
							#FILE="$(basename $4)"
							cp "$DIR/$4" "$DIR/.lit/$USER/$4" ||  exit 1
							
							echo "File $4 checked-out"
							log_message "File $4 has been checked-out by user $USER" >> "$REPO_LOG"
							
						else 
							echo "File $4 does not exist"
						fi

						exit 1
						;;
					esac
				else 
					echo "Please provide a file to check-out"
					list_repo_files "$2"
					
				fi
				;;
			"-check-in")
				DIR=./$REPOSITORIES/$2
				if [[ -n $4 ]]; then
					case $4 in 
					*/)
						echo "Cannot check-out whole dir have to check-out file by file"; exit 1
						;;
					*)
						COMMIT_MSG="not provided"
						if [[ -n $5 ]]; then
							if [[ "$5" != "-m" ]]; then echo "unsupported flag $5" &&  exit 1; fi
							 COMMIT_MSG="$6"
						fi
						if [[ ! -f "$DIR"/.lit/"$USER"/"$4"  ]]; then
							echo "File $4 not checked-out"
							echo "Make sure you provide the full path starting from repo root"
							exit 1
						fi

						DF="$(diff -u "$DIR/.lit/$USER/$4" "$DIR/$4")"				
	
						mv "$DIR/.lit/$USER/$4" "$DIR/$4" && rm "$DIR/$4.lck" || exit 1
					 
						log_message "File $4 has been checked-in by $USER" >> "$REPO_LOG"
						if [[ -n $COMMIT_MSG ]]; then
							echo "Commit note: $COMMIT_MSG" >> "$REPO_LOG"
						fi
						echo -e  "\\nChanges made: \\n" >> "$REPO_LOG"
						echo "$DF" >> "$REPO_LOG"
						echo -e "\\n\\n" >> "$REPO_LOG"
						echo "Successfully checked-in file $4"
						;;
					esac
				else
					echo "Please provide a file to check-in"
					
					list_editing_files "$2"
				fi
			
				exit 1
				;;
			"-editing")
				list_editing_files "$2"
				;;
			"-logs")
				cat "$REPO_LOG"
				;;
			"-restore")
				DIR="./$REPOSITORIES/$2"
				BACKUPS="$DIR/.lit/backups"
				if [[ -n "$4" ]]; then
					if [[ -f "$BACKUPS/$4" ]]; then
						if cp "$BACKUPS/$4" "$DIR/${4%.*}"; then
							echo "File $4 has been restored"
							log_message "File $4 has been retored by $USER" >> "$REPO_LOG"
							exit 1
						else
							echo "Failed to restore file $4"
							log_message "$USER failed to restore file $4" >> "$REPO_LOG"
							exit 1
						fi
					else
						echo "Backup not found"
						list_backups "$2"
						exit 1
					fi 	
				else
					list_backups "$2"	
				fi
				;;
			"-edit")
				DIR="./$REPOSITORIES/$2"
				if [[ -n $4 ]]; then
					EDITING="$DIR/.lit/$USER/$4"
					if [[ -f $EDITING ]]; then
						vi "$EDITING"
					else
						echo "You have not checked out file $4"
					fi
				else
					echo "Provide a file you have checked out to edit"
					list_editing_files "$2"
				fi
				;;
			"-zip")
					FNAME="$2-repo.tar.gz"
					if tar -zcf "$HOME/$FNAME" "./$REPOSITORIES/$2"; then
						echo "Repo $4 has been compressed and placed in your $HOME dir"
					else
						echo "Failed to archive repository $2"
					fi
					exit 1
				;;
			"-view")
				if [[ -n $4 ]]; then
					if [[ -f "./$REPOSITORIES/$2/$4" ]]; then
						echo "=========BEGINNING========="
						cat "./$REPOSITORIES/$2/$4"
						echo "=========END========="
					else 
						echo "File $4 does not exist"
						list_repo_files "$2"
					fi
				else
					echo "Please provide a file to show"
					list_repo_files "$2"
				fi
				;;
			*)
				print_help
				;;
			esac
		else 
			echo "$ACCESS"
		fi	
	else 
		print_help
	fi

	exit 1
	;;
*)
	print_help
	
	exit 1	
	;;
esac
