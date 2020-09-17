#!/bin/bash
#
# sandbox.bash - Push the contents of a folder to a Virtual Machine for testing.
#
# This script provides functionality to quickly sync certain files of a project
# folder with a corresponding folder on a server (i.e. VirtualBox guest) via rsync.
# The general idea is that a shared folder set up for a virtual machine has
# file permissions that don't reflect the permissions on the host (development)
# system. E.g. in a virtual box guest (https://www.virtualbox.org/) the
# owner/group of the shared folder will be root/vboxsf.
# Therefore, sandbox.bash uses a ssh connection and rsync to the
# virtual testing machine to conveniently sync the contents of the development
# system with the testing 'sandbox'.
# No pull is provided as the idea is to make all the changes on the host, and
# only push the current state for testing the VM guest.
# 
# @Name:         sandbox.bash
# @Author:       Tobias Marczewski <vortex@e.mail.de>
# @Last Edit:    2020-09-02
# @Version:      1.0
# @Location:     /usr/local/bin/sandbox
#
#    Copyright (C) 2020 Tobias Marczewski
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#

# for +( ) in parameter expansion
shopt -s extglob

## Fixed variable settings
declare -r VERSION="1.0"
SANDBOX_PROJECT_DIR=$(pwd)
SANDBOX_SETTINGS_FOLDER="${SANDBOX_PROJECT_DIR}/.sandbox"
SANDBOX_SETTINGS_FILE="${SANDBOX_SETTINGS_FOLDER}/sandbox.settings"
SANDBOX_SSH_FOLDER="${SANDBOX_SETTINGS_FOLDER}/ssh"
SANDBOX_SSH_CONFIG="${SANDBOX_SSH_FOLDER}/config"
SANDBOX_SSH_KEY="${SANDBOX_SSH_FOLDER}/server_rsa"
SANDBOX_TRACKED_FILES_FILE="${SANDBOX_SETTINGS_FOLDER}/tracked.files"

## Read from the settings file $SANDBOX_SETTINGS_FILE
unset SANDBOX_SERVER_SANDBOX_DIR
declare -a EXCLUDED_FILES

## MAIN
function main() {
    ## Build an array for 'self' to be able to append the action
    ## chosen - for better error output.
    ##
    declare -a self=("${0##*/}")
    local action
    
    if [[ -z "$1" ]]; then
	echo "Error: No action specified!" >&2
	echo "See '${self} usage' for info." >&2
	exit 1
    fi

    readonly action="$1"
    shift
    self+=("${action}")
    
    case "$action" in
	"version")
	    echo "$VERSION"
	    ;;
	"usage")
	    usage
	    ;;
	"setup")
	    setup
	    ;;
	"clean")
	    ensure_dir_is_sandbox_enabled
	    clean_all
	    ;;
	"server")
	    ensure_dir_is_sandbox_enabled
	    server_settings "$@"
	    ;;
	"list")
	    ensure_dir_is_sandbox_enabled
	    list_tracked_files
	    ;;
	"add")
	    ensure_dir_is_sandbox_enabled
	    add_to_tracked_files "$@"
	    ;;
	"remove")
	    ensure_dir_is_sandbox_enabled
	    remove_from_tracked_files "$@"
	    ;;
	"list-excluded")
	    ensure_dir_is_sandbox_enabled
	    files_excluded_from_tracking "list"
	    ;;
	"add-excluded")
	    ensure_dir_is_sandbox_enabled
	    files_excluded_from_tracking "add" "$@"
	    ;;
	"remove-excluded")
	    ensure_dir_is_sandbox_enabled
	    files_excluded_from_tracking "remove" "$@"
	    ;;
	"push")
	    ensure_dir_is_sandbox_enabled
	    push_files_to_server
	    ;;
	"sync")
	    ensure_dir_is_sandbox_enabled
	    delete_untracked_files_on_sandbox_server
	    push_files_to_server
	    ;;
	*)
	    echo "Unknown action ${action}." >&2
	    echo "See '${self[0]} usage' for info." >&2
	    exit 1
    esac

    exit 0
}


function usage() {
    ## TODO add webpage (git hub)
    cat <<-EOF

   ${self[0]}  version ${VERSION}
   Copyright (C) 2020 Tobias Marczewski

   This program comes with ABSOLUTELY NO WARRANTY.  This is free software,
   and you are welcome to redistribute it under certain conditions.
   See the GNU General Public License for details.
   (https://www.gnu.org/licenses/)

   Sync selected files of a local project directory with a sandbox directory
   on a server (a virtual machine) for testing purposes.

   Usage: ${self[0]} ACTION
   
   Actions:
   
       usage	        Show this information.
   		        
       setup	        Enable the current project directory for sandbox.
		        
       clean	        Remove files and settings from sandbox server, and also
       		        from the local project directory.   
       server 	        
         show	        Display the current base directory on the sandbox server.
       	 set <path>     Set the base directory to <path>.
   	    	        (relative to the server-login-user HOME directory ~/<path>)
           	        
       list	        Display files currently tracked for syncing.
   
       add <files>      Add files to the tracked list (supports *).
       	   		Note: globbing happens before the list is passed to 'add',
       			hence don't quote the pattern (as opposed to 'remove').
   
       remove <files>   Remove files from the tracked list (supports *).
       	      		Note: When using wildcards the pattern has to be quoted,
       			as otherwise globbing takes place before the pattern is
       			passed to 'remove'.

       list-excluded	List files currently never added to the tracked files.

       add-excluded	Add files to the excluded list.

       remove-excluded	Remove files from the excluded list.
       			(Allow them to be tracked again)
   
       push   	        Update the tracked files on the sandbox server.

       sync             Delete untracked files from sandbox server, and then update
       			the tracked files. You should consider running 'sync' once after
                        changing the tracked files list.

       version		Print version of ${self[0]}.
   
EOF

    return 0
}



################################################################################
# Test for any function/action that needs the files created during setup to
# ensure the current directory contains those.
# Also set variables that are read from settings files.
#
function ensure_dir_is_sandbox_enabled() {
    local enclosing_IFS
    declare -i exit_code
    
    if ( ! is_sandbox_enabled ); then
	echo "Current project is not setup for ${self[0]} yet." >&2
	echo "Please see '${self[0]} usage' or use '${self[0]} setup'." >&2
	exit 1
    fi

    enclosing_IFS="$IFS"
    IFS=$'\n'
    
    ## set variables
    SANDBOX_SERVER_SANDBOX_DIR=$(read_setting "SANDBOX_SERVER_SANDBOX_DIR")

    exit_code="$?"
    if (( "$exit_code" != 0 )); then
	echo "Error setting SANDBOX_SERVER_SANDBOX_DIR." >&2
	exit 1
    fi

    ## don't allow an empty string as a 'sync' would then wipe the whole
    ## HOME dir clean
    ##
    if [[ -z "$SANDBOX_SERVER_SANDBOX_DIR" ]]; then
	echo "Error: sandbox server base directory not set or set to empty string." >&2
	exit 1
    fi
    
    EXCLUDED_FILES=($(files_excluded_from_tracking "list"))

    exit_code="$?"
    if (( "$exit_code" != 0 )); then
	echo "Error setting EXCLUDED_FILES." >&2
	exit 1
    fi

    if [[ ! "${EXCLUDED_FILES+xx}" == "xx" ]]; then
	echo "Error: EXCLUDED_FILES not set after reading settings." >&2
	exit 1
    fi
    

    IFS="$enclosing_IFS"
    
    return 0
}

################################################################################
# Check if the current project/directory has a setup sandbox environment.
# (Check if the folder and settings files are there...)
#
# Global Variables
#    SANDBOX_SETTINGS_FOLDER
#    SANDBOX_SETTINGS_FILE
#    SANDBOX_SSH_CONFIG
#    SANDBOX_SSH_KEY
#    SANDBOX_TRACKED_FILES_FILE

function is_sandbox_enabled() {

    if ( [[ ! -e "$SANDBOX_SETTINGS_FOLDER" ]] ||
	     [[ ! -e "$SANDBOX_SETTINGS_FILE" ]] ||
	     [[ ! -e "$SANDBOX_SSH_CONFIG" ]] ||
	     [[ ! -e "$SANDBOX_SSH_KEY" ]] ||
	     [[ ! -e "$SANDBOX_TRACKED_FILES_FILE" ]] )
    then
	return 1
    else
	return 0	
    fi	
}

################################################################################
# Setup a .sandbox directory and save all the settings for the server.
# Also check connectivity to the server and enable gpg key authentication.
#
# Global Variables:
#    SANDBOX_SETTINGS_FOLDER
#    SANDBOX_SETTINGS_FILE
#    SANDBOX_SSH_FOLDER
#    SANDBOX_SSH_CONFIG
#    SANDBOX_SSH_KEY
#    SANDBOX_TRACKED_FILES_FILE
#
function setup() {
    local server_ip
    local server_user_name

    if ( is_sandbox_enabled ); then
	echo "Current directory seems to be already set up for ${self[0]}" >&2
	exit 1
    fi
    
    ## Ensure needed folders exist
    mkdir "$SANDBOX_SETTINGS_FOLDER"

    if (( "$?" != 0 )); then
	setup_error "Couldn't create ${SANDBOX_SETTINGS_FOLDER}."
    fi

    mkdir "$SANDBOX_SSH_FOLDER"

    if (( "$?" != 0 )); then
	setup_error "Couldn't create ${SANDBOX_SSH_FOLDER}."
    fi

    ## Create needed files
    touch "$SANDBOX_SETTINGS_FILE"
    touch "$SANDBOX_TRACKED_FILES_FILE"

    ## Enter default settings into settings file
    write_setting "SANDBOX_SERVER_SANDBOX_DIR" "Sandbox/$(basename $(realpath .))"
    write_setting "EXCLUDED_FILES" \
       "$(realpath --relative-to=${SANDBOX_PROJECT_DIR} ${SANDBOX_SETTINGS_FOLDER}):.git*"
   
    ## Generate ssh key
    ssh-keygen -t rsa -N '' -f "$SANDBOX_SSH_KEY"

    if (( "$?" != 0 )); then
	setup_error "Couldn't create ssh key."
    fi

    echo "Setting up key-authorized server login."

    server_ip=$(read_server_ip)
    if (( "$?" != 0 )); then
	setup_error "could not determine IP address for the sandbox server."
    fi

    read -p 'Server User: ' server_user_name

    readonly server_ip
    readonly server_user_name

    ## Add public ssh-key to authorized_keys on server
    ssh-copy-id -i "${SANDBOX_SSH_KEY}.pub" \
		"${server_user_name}@${server_ip}" >/dev/null 2>&1

    if (( "$?" != 0 )); then
	setup_error "Couldn't copy public ssh-key to sandbox server. (ssh-copy-id)"
    fi
	
    ## Write config file
    cat <<EOF > "$SANDBOX_SSH_CONFIG"
Host Sandbox
    HostName ${server_ip}
    User ${server_user_name}
    IdentityFile ${SANDBOX_SSH_KEY}
EOF

    ## Check that ssh works
    if ( ! server_online ); then
	echo "Setup finished, but failed to connect to server - " \
	     "please check manually." >&2
	echo "ssh -F ${SANDBOX_SSH_CONFIG} Sandbox" >&2
	exit 1
    fi

    echo "Successfully enabled ${self[0]} for this project."
    
    return 0
}


################################################################################
# Remove files / folders created during setup (if this fails)
#
# Arguments:
#    $1 - message to display
#
function setup_error() {
    local error_message
    error_message=$(echo "$@")
    
    echo "${self[@]} Error: ${error_message}" >&2
    
    rm -rf "$SANDBOX_SSH_FOLDER"
    rm -rf "$SANDBOX_SETTINGS_FOLDER"
    
    exit 1
}

################################################################################
# Prompt and read the server ip as input; also test if it is ping-able.
#
# Output:
#    the server ip
# Returns:
#    0 - when ip valid and ping-able
#    1 - on cancel or error
# 
function read_server_ip() {
    local server_ip

    while true
    do
	read -p 'Server IP [C|cancel]: ' server_ip
	case "$server_ip" in
	    "C"|"c"|"Cancel"|"cancel")
		return 1
		;;
	esac
	

	if ( ping -c 3 "${server_ip}" >/dev/null ); then
	    echo "$server_ip"
	    return 0
	else
	    echo "Couldn't reach server at ${server_ip}." >&2
	    echo "Please make sure the server is online." >&2
	fi
    done
}


################################################################################
# Remove all files and settings from the sandbox server, and in the project dir
#
function clean_all() {
    local public_key
    local user_confirmation
    SANDBOX_SERVER_SANDBOX_DIR=$(read_setting "SANDBOX_SERVER_SANDBOX_DIR")

    echo "This will reset the sandbox server settings, and remove all " \
	 "settings for sandbox for this project!"
    read -p "Proceed? [ yes / Cancel ]: " user_confirmation

    case "$user_confirmation" in
	"Y"|"y"|"Yes"|"yes")
	    if ( ! server_online ); then
		echo "Error: could not connect to server, insure it is online." >&2
		exit 1
	    else
		echo "Cleaning up..."
	    fi
	    ;;
	*)
	    echo "Aborting..."
	    exit 0
	    ;;
    esac
    
    ## Clean files on server:
    ## 1) Remove Sandbox dir
    ##
    execute_on_server "rm -rf \"${SANDBOX_SERVER_SANDBOX_DIR}\""

    if (( "$?" != 0 )); then
	echo "Error: could not remove sandbox base dir on server." >&2
	exit 1
    fi
    
    ## 2) Delete public key from authorized_keys on server
    ##
    public_key=$(cat "${SANDBOX_SSH_KEY}.pub")
    execute_on_server "sed -i '\;${public_key};d' .ssh/authorized_keys"

    if (( "$?" != 0 )); then
	echo "Error: could not remove rsa key from authorized_keys on server." >&2
	exit 1
    fi
    
    ## Clean local files
    ## Delete the sandbox settings folder
    ##
    rm -rf "$SANDBOX_SSH_FOLDER"

    if (( "$?" != 0 )); then
	echo "Error: could not delete ${SANDBOX_SSH_FOLDER}." >&2
	exit 1
    fi
    
    rm -rf "$SANDBOX_SETTINGS_FOLDER"

    if (( "$?" != 0 )); then
	echo "Error: could not delete ${SANDBOX_SETTINGS_FOLDER}." >&2
	exit 1
    fi
    
    return 0
}


################################################################################
# Show or set the sandbox base directory on the server.
#
# Arguments:
#    $1  - action ('show' or 'set')
#   [$2] - the new setting for the base dir [for action 'set']
#          (path relative to user@server:~/<path>)
#
# Global Varibles:
#    SANDBOX_SETTINGS_FILE
#    SANDBOX_SERVER_SANDBOX_DIR
#
function server_settings() {
    local action

    if [[ -z "$1" ]]; then
	echo "Error (${self[@]}): no action provided." >&2
	echo "See '${self[0]} usage' for help" >&2
	exit 1
    fi

    readonly action="$1"

    case "$action" in
	"show")
	    read_setting "SANDBOX_SERVER_SANDBOX_DIR"
	    return
	    ;;
	"set" )
	    if [[ -z "$2" ]]; then
		echo "(${self[@]}): No new base dir on the server provided." >&2
		echo "Unsetting the server dir is not supported." >&2
		echo "To set the dir to the root of the user home set it to '~'" >&2
		exit 1
	    fi
	    write_setting "SANDBOX_SERVER_SANDBOX_DIR" "$2"
	    return
	    ;;
	*)
	    echo "(${self[@]}): unknown action '${action}'" >&2
	    exit 1
	    ;;
    esac
}


################################################################################
# List files currently in the tracked files file
#
function list_tracked_files() {
    
    sort_and_remove_duplicates "$SANDBOX_TRACKED_FILES_FILE"
    
    cat "$SANDBOX_TRACKED_FILES_FILE"

    return 0
}

################################################################################
# Add files/directories to the tracked files file
#
# Arguments:
#    $1..$n - files to add (globbing supported)
#
# Global Variables:
#    SANDBOX_TRACKED_FILES_FILE
#
function add_to_tracked_files() {
    local enclosing_IFS
    declare -a FILES

    add_files_to_FILES "$@"

    readonly enclosing_IFS="$IFS"
    IFS=$'\n'
    echo "${FILES[*]}" >> "$SANDBOX_TRACKED_FILES_FILE"
    IFS="$enclosing_IFS"

    sort_and_remove_duplicates "$SANDBOX_TRACKED_FILES_FILE"

    return
}

################################################################################
# Remove files/directories from the tracked files file
#
# Arguments:
#    $1..$n - files to remove (globbing supported)
#             to use a regex on the added files list, quote the pattern
#             file* will do globbing in the terminal, resulting in all files
#             starting with file.. in the current directory to be passed.
#             "file*" will instead be changed to the regex 'file.*' and
#             apply to all files in the tracked files that match the pattern.
#
# Global Variables:
#    SANDBOX_TRACKED_FILES_FILE
#
function remove_from_tracked_files() {

    sort_and_remove_duplicates "$SANDBOX_TRACKED_FILES_FILE"
    
    for pattern in "${@//\*/.*}"; do
	sed -i "\;^${pattern}$;d" "$SANDBOX_TRACKED_FILES_FILE"
    done

    return
}

################################################################################
# Check if the file passed is being tracked, OR
# if the passed directory is part of a path of a tracked file
# (or being tracked itself)
#
# Arguments:
#    $1 - file / dir to test
#
# Global Variables:
#    SANDBOX_TRACKED_FILES_FILE
#
# Returns:
#    0 - (true) = the file is listed in the tracked files file
#    1 - (false) = the file/dir is not being tracked.
#
function file_is_being_tracked() {
    local file
    local pattern

    if [[ -z "$1" ]]; then
	echo "file_is_being_tracked() Error: no argument provided." >&2
	exit 1
    fi

    file="${1##/}"
    pattern="^${file%%/}"
    
    if (( $(grep -c "$pattern" "$SANDBOX_TRACKED_FILES_FILE") > 0 )); then
	return 0
    else
	return 1
    fi
}

################################################################################
# Sort the filenames / paths in a file (one per line) and remove duplicates.
# Also removes:
#    - any non-existing files
#    - files listed in EXCLUDED_FILES setting
#
# Arguments:
#    $1 - path to file containing filenames / dirnames (one per line)
#
# Global Variables:
#    EXCLUDED_FILES
#
# Output:
#    none - file provided as argument is changed in place.
#
function sort_and_remove_duplicates() {
    local enclosing_IFS
    local textfile
    declare -a files
    declare -a excluded_files

    if [[ -z "$1" ]]; then
	echo "sort_and_remove_duplicates() Error: No file specified." >&2
	exit 1
    fi

    readonly textfile="$1"

    if [[ ! -f "$textfile" ]]; then
	echo "sort_and_remove_duplicates() Error: " \
	     "File ${textfile} not found." >&2
	exit 1
    fi

    if [[ ! -r "$textfile" ]] || [[ ! -w "$textfile" ]]; then
	echo "sort_and_remove_duplicates() Error: " \
	     "No adequate read/write permissions for ${textfile}." >&2
	exit 1
    fi

    readonly enclosing_IFS="$IFS"
    IFS=$'\n'
    
    files=($(sort "$textfile" | uniq))

    ## escape dots
    excluded_files="${EXCLUDED_FILES//./\\.}"
    ## replace globbing * with regex .*
    excluded_files="${excluded_files//\*/.*}"

    rm "$textfile" && touch "$textfile"
    
    for file in "${files[@]}"; do
	## Do not add if in excluded files
	for ex_file in "${excluded_files[@]}"; do
	    if (( $(echo "$file" | grep -c "^${ex_file}") > 0 )); then
		continue 2
	    fi
	done
	
	## Do not add if it does not exist
	if [[ -e "$file" ]]; then
	    echo "$file" >> "$textfile"
	fi
    done

    IFS="$enclosing_IFS"
 
    return 0
}


################################################################################
# Check if the arguments passed are existing files/dirs and if so, add them
# to the array 'FILES'
#
# Arguments:
#    $1..$n file names or globs
#
# Global Variables:
#    SANDBOX_PROJECT_DIR
#
# Output:
#    none - files added to FILES
#
function add_files_to_FILES() {

    ## check if variable FILES exists FIXME

    ## add files to FILES
    for file in "$@"; do
	## don't follow . or ..
	if [[ "$file" == "." ]] || [[ "$file" == ".." ]]; then
	    continue
	fi
	## only accept existing files
	if [[ -e "$file" ]]; then
	    FILES+=($(realpath --relative-to="${SANDBOX_PROJECT_DIR}" "$file"))
	fi
    done
}


################################################################################
# List, add, and remove files from being excluded to be tracked.
#
# Arguments:
#    $1     - action [one of "list", "add", "remove"]
#    $2..$n - files to add or remove
#             (if a filename / path contains whitespace it has to be enclosed
#              in quotation marks)
#
# Global Variables:
#    SANDBOX_SETTINGS_FILE [read_setting(); write_setting()]
#
# Output:
#    "list" - writes the files contained in the setting separated by newlines
#    "add"  - adds the files to the setting EXCLUDED_FILES [write_setting()]
#    "remove" - removes files from setting EXCLUDED_FILES [write_setting()]
#
function files_excluded_from_tracking() {
    local enclosing_IFS
    declare -a excluded_files
    local action

    if [[ -z "$1" ]]; then
	echo "excluded_files() Error: no action specified." >&2
	exit 1
    fi

    ## use path separator ':' to allow spaces in names
    readonly enclosing_IFS="$IFS"
    IFS=$':\n'    
    excluded_files=($(read_setting "EXCLUDED_FILES"))

    action="$1"
    shift
    self+=("$action")

    case "$action" in
	"list")
	    ## Output the files separated by new lines
	    ##
	    printf "%s\n" "${excluded_files[@]}"
	    ;;
	
	"add")
	    ## Append the newly specified names
	    ##
	    for file in "$@"; do
    		excluded_files+=("$file")
	    done
	    
	    write_setting "EXCLUDED_FILES" "${excluded_files[*]}"
	    excluded_sort_and_remove_duplicates
	    ;;
	
	"remove")
	    ## Check if one of the specified files matches, and if so,
	    ## do not keep it in the excluded files list.
	    ##
	    declare -a new_excluded_files
	    
	    for ex_file in "${excluded_files[@]}"; do
		for file in "$@"; do
    		    if [[ "$file" == "$ex_file" ]]; then
			continue 2
		    fi
		done
		new_excluded_files+=("$ex_file")
	    done

	    write_setting "EXCLUDED_FILES" "${new_excluded_files[*]}"
	    excluded_sort_and_remove_duplicates
	    ;;
	
	*)
	    unset IFS
	    echo "${self[@]} unknown action ${action}" >&2
	    exit 1
    esac
    
    IFS="$enclosing_IFS"
    
    return 0
}

################################################################################
# Helper for excluded_files() 
#
function excluded_sort_and_remove_duplicates() {
    local enclosing_IFS
    declare -a excluded_files
    declare -a sorted_files

    readonly enclosing_IFS="$IFS"
    IFS=$':\n'
    
    excluded_files=($(read_setting "EXCLUDED_FILES"))
    sorted_files=($(printf "%s\n" "${excluded_files[@]}" | sort | uniq ))
    
    write_setting "EXCLUDED_FILES" "${sorted_files[*]}"
    
    IFS="$enclosing_IFS"
}


################################################################################
# Push the files listed in the SANDBOX_TRACKED_FILES_FILE to the sandbox server.
#
# Global Variables:
#    SANDBOX_SETTINGS_FILE
#        - SANDBOX_SERVER_SANDBOX_DIR (in settings file)
#    SANDBOX_TRACKED_FILES_FILE
#
function push_files_to_server() {

    sort_and_remove_duplicates "$SANDBOX_TRACKED_FILES_FILE"
    
    if ( ! server_online ); then
	echo "Error: could not connect to server, ensure it is online." >&2
	exit 1
    fi

    ## Ensure Sandbox folder exists on server
    local exec_command
    exec_command=$(echo "[[ ! -e \"${SANDBOX_SERVER_SANDBOX_DIR}\" ]] && " \
    			"mkdir -p \"${SANDBOX_SERVER_SANDBOX_DIR}\" ||
			exit 0")

    execute_on_server "$exec_command"

    if (( "$?" != 0 )); then
    	echo "Could not create project dir ${SANDBOX_SERVER_SANDBOX_DIR}" \
    	     "on server." >&2
    	exit 1
    fi
    
    ## Sync the tracked files
    declare -i exit_code

    rsync -tR --files-from="$SANDBOX_TRACKED_FILES_FILE" --delete-before \
    	  -e "ssh -F ${SANDBOX_SSH_CONFIG} Sandbox -o PasswordAuthentication=no" \
    	  "${SANDBOX_PROJECT_DIR}" :"${SANDBOX_SERVER_SANDBOX_DIR}"
    # where:
    # -t only transfer when newer at source
    # -R use relative paths at destination

    exit_code="$?"
    
    if (( "$exit_code" != 0 )); then
	echo "Error during rsync (code: ${exit_code})" >&2
	exit 1
    fi
    
    return 0
}


################################################################################
# Delete files and directories that are not in the tracked files list on the
# server.
#
# Global Variables:
#    SANDBOX_SERVER_SANDBOX_DIR
#
function delete_untracked_files_on_sandbox_server() {
    local enclosing_IFS
    local ssh_command
    declare -i exit_code
    declare -a files_on_server
    declare -a files_to_delete

    readonly enclosing_IFS="$IFS"
    IFS=$'\n'

    files_on_server=($(list_sandbox_server_files))

    for file in "${files_on_server[@]}"; do
	if ( ! file_is_being_tracked "$file" ); then
	    files_to_delete+=("$file")
	fi
    done

    ## if no files are to be deleted, exit here
    ##
    if (( "${#files_to_delete[@]}" <= 0 )); then
	IFS="$enclosing_IFS"
	return 0
    fi
    
    read -r -d '' ssh_command <<-EOF
    declare -a files_to_delete=($(printf "\"%s\" " "${files_to_delete[@]}"))

    for file in "\${files_to_delete[@]}"; do
    	rm -rf "./${SANDBOX_SERVER_SANDBOX_DIR}/\${file}"
    done

    exit
EOF

    execute_on_server "${ssh_command}"

    exit_code="$?"
    
    if (( "$exit_code" != 0 )); then
	echo "delete_untracked_files_on_sandbox_server() SSH Error code: ${exit_code}." >&2
	exit "$exit_code"
    fi

    IFS="$enclosing_IFS"
    
    return 0
}

################################################################################
# List all files currently on the sanbox server
#
# Global Variables:
#    SANDBOX_SERVER_SANDBOX_DIR
#
# Output:
#    a list of files, each entry separated by new line '\n'
#
function list_sandbox_server_files() {
    declare -a files_on_server
    declare -i  exit_code
    local ssh_command
    local enclosing_IFS

    ## If the sandbox folder exists list the files, otherwise there is
    ## nothing to list...
    ##
    read -r -d '' ssh_command <<-EOF
    if [[ -e "./${SANDBOX_SERVER_SANDBOX_DIR}" ]]; then
       find "./${SANDBOX_SERVER_SANDBOX_DIR}" -mindepth 1 -path "*"
    fi
    exit 0
EOF

    enclosing_IFS="$IFS"
    IFS=$'\n'

    files_on_server=($(execute_on_server "$ssh_command"))

    exit_code="$?"
    
    if (( "$exit_code" != 0 )); then
	echo "list_sandbox_server_files() SSH Error code: ${exit_code}." >&2
	exit "$exit_code"
    fi

    echo  "${files_on_server[*]#./${SANDBOX_SERVER_SANDBOX_DIR}/}"
    IFS="$enclosing_IFS"
    
    return 0
}


################################################################################
# Read the value for the specified setting from the settings file.
#
# Arguments:
#    $1 - setting
#
# Global Variables:
#    SANDBOX_SETTINGS_FILE
#
# Output:
#    value of the setting
#
function read_setting() {
    local setting
    local setting_line
    local value
    
    if [[ -z "$1" ]]; then
	echo "read_setting() Error: no setting provided." >&2
	exit 1
    fi

    readonly setting="$1"

    ## Ensure the setting is matched exactly once
    ##
    if ( ! settings_file_contains_setting "$setting" ); then
	echo "read_setting() Error: setting ${setting} not in settings file." >&2
	exit 1
    elif ( ! settings_file_contains_setting "$setting" 'once' ); then
	echo "read_setting() Error: more than one match found for setting '${setting}'." >&2
	exit 1
    fi

    ## Extract the value
    ##
    setting_line=$(grep "^\\s*${setting}\\s*=" "$SANDBOX_SETTINGS_FILE")
    value="${setting_line##*=+( )}"
    
    echo "${value}"
}


################################################################################
# Arguments:
#    $1 - setting (name)
#    $2 - value
#
# Global Variables:
#    SANDBOX_SETTINGS_FILE
#
function write_setting() {
    local setting
    local value

    if [[ -z "$1" ]]; then
	echo "write_setting() Error: no setting provided." >&2
	exit 1
    fi

    if [[ -z "$2" ]]; then
	echo "write_setting() Error: no value provided." >&2
	exit 1
    fi

    readonly setting="$1"
    readonly value="$2"

    if ( settings_file_contains_setting "$setting" ); then
	## change value for existing setting
	## use ';' as delimiter for the sed command, as some of the values
	## are paths, and will contain '/'. As variables are replaced
	## by the shell before they are interpreted by sed, a '/' in the $value
	## will be read as separator in the command for sed!
	##
	sed -i "s;^\\s*\(${setting}\)\\s*=\\s*\(\\S.*\)\\s*$;\1 = ${value};" \
	    "$SANDBOX_SETTINGS_FILE"
    else
	## enter the setting and the value
	echo "${setting} = ${value}" >> "$SANDBOX_SETTINGS_FILE"
    fi
}

################################################################################
# Arguments:
#    $1 - setting
#    $2 - (optional) the string "once"; when provided only return 0 if the
#         setting has exactly one match
#
# Global Variables:
#    SANDBOX_SETTINGS_FILE
#
function settings_file_contains_setting() {
    local setting
    local ignore_duplicates
    declare -i number_of_matches

    if [[ -z "$1" ]]; then
	echo "settings_file_contains_setting() Error: no setting provided." >&2
	exit 1
    fi

    readonly setting="$1"

    
    if [[ -n "$2" ]] && [[ "$2" == "once" ]]; then
	readonly ignore_duplicates=false
    else
	readonly ignore_duplicates=true
    fi

    
    number_of_matches=$(grep -c "^\\s*${setting}\\s*=" "$SANDBOX_SETTINGS_FILE")

    if (( $number_of_matches == 1 )); then
	return 0
    elif ( (( $number_of_matches > 1 )) && $ignore_duplicates ); then
	return 0
    else
	return 1
    fi
}


################################################################################
# Check if server is online and ssh is working
#
function server_online() {
    declare -i exit_code
    execute_on_server 'exit 0'
    exit_code="$?"
    return "$exit_code"
}

################################################################################
# Execute a command on the sandbox server via ssh.
#
# Arguments:
#    $1..$n - commands to execute
#             if ssh options are passed the switch and value should be passed
#             as separate arguments, e.g.: "-o" "ConnectionAttempts=3"
#             commands should be enclosed in single quotes:
#             'for i in {1..5}; do echo $i; done'
#
# Global Variables:
#    SANDBOX_SSH_CONFIG
#
function execute_on_server() {
    declare -a ssh_args

    ## Not providing a command would lead to a non-terminated ssh connection
    ## to the server, which we don't want within this script.
    ##
    if [[ -z "$1" ]]; then
	echo "execute_on_server() Error: no command specified" >&2
	exit 1
    fi
    
    ssh_args+=("-F" "$SANDBOX_SSH_CONFIG")
    ssh_args+=("Sandbox")
    ssh_args+=("-o" "PasswordAuthentication=no")
    ssh_args+=("-o" "ConnectTimeout=3")

    while [[ -n "$1" ]]; do
	ssh_args+=("$1")
	shift
    done

    ssh "${ssh_args[@]}"
    
    return
}


## ENTRY POINT
##
main "$@"
