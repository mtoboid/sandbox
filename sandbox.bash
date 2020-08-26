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
# @Last Edit:    2020-08-26
# @Version:      0.1
# @Location:     /usr/local/bin/sandbox
#

# for +( ) in parameter expansion
shopt -s extglob

SANDBOX_PROJECT_DIR=$(pwd)
#SANDBOX_SETTINGS_FOLDER=""${SANDBOX_PROJECT_DIR}/.sandbox"
SANDBOX_SETTINGS_FOLDER="${SANDBOX_PROJECT_DIR}/sandbox_test"
SANDBOX_SETTINGS_FILE="${SANDBOX_SETTINGS_FOLDER}/sandbox.settings"
SANDBOX_SSH_FOLDER="${SANDBOX_SETTINGS_FOLDER}/ssh"
SANDBOX_SSH_CONFIG="${SANDBOX_SSH_FOLDER}/config"
SANDBOX_SSH_KEY="${SANDBOX_SSH_FOLDER}/server_rsa"
SANDBOX_TRACKED_FILES_FILE="${SANDBOX_SETTINGS_FOLDER}/tracked.files"

# SANDBOX_SERVER_SANDBOX_DIR


# rsync options:
# -t   only transfer changed files
# --files-from=FILE   transfer files listed in FILE


# have a function that adds/removes filenames from a file, which
# - can be listed
# - are used for rsync to push them to the sandbox server


function main() {

    local project_dir

    readonly project_dir=$(pwd)
    ## TODO
    # var - files to be synced when 'push'
    
    exit 0
}

function usage() {
    echo "not implemented"
    return 0
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
    mkdir "$SANDBOX_SSH_FOLDER"

    ## Create needed files
    touch "$SANDBOX_SETTINGS_FILE"
    touch "$SANDBOX_TRACKED_FILES_FILE"

    ## Enter default settings into settings file
    write_setting "SANDBOX_SERVER_SANDBOX_DIR" "Sandbox"

    
    ## Generate ssh key
    ssh-keygen -t rsa -N '' -f "$SANDBOX_SSH_KEY"

    
    ## Add key to authorized_keys on server
    ## get login details for server
    echo "Setting up key authorized server login."

    server_ip=$(read_server_ip)
    if (( "$?" != 0 )); then
	echo "Error setting the IP address for the sandbox server." >&2
	return 1
    fi

    read -p 'Server User: ' server_user_name

    readonly server_ip
    readonly server_user_name
    
    ssh-copy-id -i "${SANDBOX_SSH_KEY}.pub" \
		"${server_user_name}@${server_ip}" >/dev/null 2>&1
    
    ## Write config file
    cat <<EOF > "$SANDBOX_SSH_CONFIG"
Host Sandbox
    HostName ${server_ip}
    User ${server_user_name}
    IdentityFile ${SANDBOX_SSH_KEY}
EOF

    ## Check that ssh works
    execute_on_server 'exit' >/dev/null 2>&1
    if (( "$?" != 0 )); then
	echo "SSH setup not working correctly, check manually!" >&2
	return 1
    fi
    
    return 0
}

################################################################################
# Add one or more files / directories to the SANDBOX_TRACKED_FILES_FILE.
#
# Arguments:
#    $1..$n - files to add
#
# Global Variables:
#    SANDBOX_TRACKED_FILES_FILE
#
function add_file_to_tracked_files() {
    return 0
}

################################################################################
# Remove one or several files from the SANDBOX_TRACKED_FILES_FILE.
#
# Arguments:
#    $1..$n - files to remove
#
# Global Variables:
#    SANDBOX_TRACKED_FILES_FILE
#
function remove_file_from_tracked_files() {
    return 0
}

################################################################################
# Push the files listed in the SANDBOX_TRACKED_FILES_FILE to the sandbox server.
#
# Global Variables:
#    SANDBOX_TRACKED_FILES_FILE
#
function push() {
    
    echo "not implemented"
    return 0
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
# Arguments:
#    $1 - commands to execute
#
# Global Variables:
#    SANDBOX_SSH_CONFIG
#
function execute_on_server() {
    local command

    if [[ -z "$1" ]]; then
	command='exit 0'
    else
	command="$1"
    fi
    
    ssh -F "$SANDBOX_SSH_CONFIG" Sandbox -o PasswordAuthentication=no "$command"
    return
}

