fatal () {
	# Messages go to stderr
	echo "$0: fatal error:" "$@" >&2
	exit 1
}

# ./newchange.sh message user changes file
if [ $# -ne 4 ]
then
	fatal not enough arguments
fi

# create directory if it is not existant
dir=".lit/changes"
if [[ ! -e $dir ]]; then
    mkdir -p $dir
elif [[ ! -d $dir ]]; then
    fatal "$dir already exists but is not a directory"
fi

# store changes
filename="$4-$2-$(date +%s)"
echo "$filename"
printf "Message: \"$1\"\nUser: \"$2\"\n$3\n" > "$dir/$filename"
