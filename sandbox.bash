#!/bin/bash
#
# Push your project to a sandbox folder for quick testing.
# Script to provide functionality to sync a project folder with a corresponding
# folder on a server (Virtual Box Guest).
# Just using a shared folder turned out to be problematic, as the file
# permissions set for this folder (root/vboxsf) change the environment when
# e.g. testing makefile installs ...
# No pull is provided as the idea is to make all the changes on the host, and
# only push for testing the current state.
# 
# @Name:         sandbox.bash
# @Author:       Tobias Marczewski
# @Last Edit:    2020-08-28
# @Version:      0.8
# @Location:     /usr/local/bin/sandbox
#

# for +( ) in parameter expansion
shopt -s extglob

## Fixed variable settings
SANDBOX_PROJECT_DIR=$(pwd)
SANDBOX_SETTINGS_FOLDER="${SANDBOX_PROJECT_DIR}/.sandbox"
SANDBOX_SETTINGS_FILE="${SANDBOX_SETTINGS_FOLDER}/sandbox.settings"
SANDBOX_SSH_FOLDER="${SANDBOX_SETTINGS_FOLDER}/ssh"
SANDBOX_SSH_CONFIG="${SANDBOX_SSH_FOLDER}/config"
SANDBOX_SSH_KEY="${SANDBOX_SSH_FOLDER}/server_rsa"
SANDBOX_TRACKED_FILES_FILE="${SANDBOX_SETTINGS_FOLDER}/tracked.files"

## Read from the settings file $SANDBOX_SETTINGS_FILE
unset SANDBOX_SERVER_SANDBOX_DIR

## MAIN
function main() {
    ## Build an array for 'self' to be able to append the action
    ## chosen - for better error output.
    ##
    declare -a self=("${0##*/}")
    local action
    
    if [[ -z "$1" ]]; then
	echo "Error: No action specified!" >&2
	echo "See '${self} usage for info." >&2
	exit 1
    fi

    readonly action="$1"
    shift
    self+=("${action}")

    case "$action" in
	"usage")
	    usage
	    ;;
	"setup")
	    setup
	    ;;
	"clean")
	    clean_all
	    ;;
	"server")
	    server_settings "$@"
	    ;;
	"list")
	    list_tracked_files
	    ;;
	"add")
	    add_to_tracked_files "$@"
	    ;;
	"remove")
	    remove_from_tracked_files "$@"
	    ;;
	"push")
	    push_files_to_server
	    ;;
	*)
	    echo "Unknown action ${action}." >&2
	    echo "See '${self[0]} usage for info." >&2
	    exit 1
    esac
}


function usage() {

    cat <<-EOF

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
   
       add <files>      Add files to the tracked list (supports globbing).
   
       remove <files>   Remove files from the tracked list (supports globbing).
   
       push   	        Sync the tracked files with the sandbox server.
   
EOF

    exit 0
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
    
    exit 0
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
    
    exit 0
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
	    exit
	    ;;
	"set" )
	    if [[ -z "$2" ]]; then
		echo "(${self[@]}): No new base dir on the server provided." >&2
		echo "Unsetting the server dir is not supported." >&2
		echo "To set the dir to the root of the user home set it to '~'" >&2
		exit 1
	    fi
	    write_setting "SANDBOX_SERVER_SANDBOX_DIR" "$2"
	    exit
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
    echo "Currently tracked files:"
    echo "----------------------------------------------------------------------"
    cat "$SANDBOX_TRACKED_FILES_FILE"
    echo "----------------------------------------------------------------------"
    exit 0
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
    declare -a FILES

    add_files_to_FILES "$@"

    IFS=$'\n'
    echo "${FILES[*]}" >> "$SANDBOX_TRACKED_FILES_FILE"
    unset IFS

    sort_and_remove_duplicates "$SANDBOX_TRACKED_FILES_FILE"
    exit
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

    exit
}

################################################################################
# Sort the filenames / paths in a file (one per line) and remove duplicates.
# Also remove any non-existing files from the list.
#
# Arguments:
#    $1 - path to file containing filenames / dirnames (one per line)
#
# Output:
#    none - file provided as argument is changed in place.
#
function sort_and_remove_duplicates() {
    local textfile
    declare -a files

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

    IFS=$'\n'
    
    files=($(sort "$textfile" | uniq))

    rm "$textfile" && touch "$textfile"
    
    for file in "${files[@]}"; do
	if [[ -e "$file" ]]; then
	    echo "$file" >> "$textfile"
	fi
    done

    unset IFS
 
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
# Push the files listed in the SANDBOX_TRACKED_FILES_FILE to the sandbox server.
#
# Global Variables:
#    SANDBOX_SETTINGS_FILE
#        - SANDBOX_SERVER_SANDBOX_DIR (in settings file)
#    SANDBOX_TRACKED_FILES_FILE
#
function push_files_to_server() {
    SANDBOX_SERVER_SANDBOX_DIR=$(read_setting "SANDBOX_SERVER_SANDBOX_DIR")

    if ( ! server_online ); then
	echo "Error: could not connect to server, ensure it is online." >&2
	exit 1
    fi

    ## Ensure Sandbox folder exists on server
    local exec_command
    exec_command=$(echo "[[ ! -e \"${SANDBOX_SERVER_SANDBOX_DIR}\" ]] && " \
    			"mkdir -p \"${SANDBOX_SERVER_SANDBOX_DIR}\"")

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
    
    exit 0
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
