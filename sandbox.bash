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
# @Last Edit:    2020-08-24
# @Version:      0.1
# @Location:     /usr/local/bin/sandbox
#

# for +( ) in parameter expansion
shopt -s extglob

#SANDBOX_SETTINGS_FOLDER=".sandbox"
SANDBOX_SETTINGS_FOLDER="sandbox_test"
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

    ## TODO
    # var - files to be synced when 'push'
    
    exit 0
}

function usage() {
    echo "not implemented"
    return 0
}


################################################################################
# Setup a .sandbox directory and save all the settings for the server...
#
## notes
# in the directory on the host, the folder will contain a .sandbox folder
# containing all the settings for the 'sandbox server':
# - server name / ip
# - login user
# >> when setup the user will be asked for the password, and then ssh gpg
#    keys will be setup automatically
# >> option to add .sandbox to .gitignore
#
function setup() {
    echo "not implemented"
    return 0
}


################################################################################
# Push a file or the whole project to the server
#
# Arguments:
#    $1 - filename(s) to push OR push-all to push the whole repo
#
function push() {
    
    echo "not implemented"
    return 0
}


################################################################################
# Read the value for the specified setting from the settings file.
#
# Arguments:
#    $1 - setting
#
# Global Variables:
#    SETTINGS_FILE
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
    setting_line=$(grep "^\\s*${setting}\\s*=" "$SETTINGS_FILE")
    value="${setting_line##*=+( )}"
    
    echo "${value}"	      
}


################################################################################
# Arguments:
#    $1 - setting (name)
#    $2 - value
#
# Global Variables:
#    SETTINGS_FILE
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
	    "$SETTINGS_FILE"
    else
	## enter the setting and the value
	echo "${setting} = ${value}" >> "$SETTINGS_FILE"
    fi
}

################################################################################
# Arguments:
#    $1 - setting
#    $2 - (optional) the string "once"; when provided only return 0 if the
#         setting has exactly one match
#
# Global Variables:
#    SETTINGS_FILE
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

    
    number_of_matches=$(grep -c "^\\s*${setting}\\s*=" "$SETTINGS_FILE")

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
# Global Variables:

function generate_ssh_key() {
    #ssh-keygen -t rsa -N '' -f $filename
    return 0
}



function write_sandbox_ssh_config() {
    local config_file

    config_file="$1"

    cat <<-EOF > "$config_file"
    Host ${server_name}
    	 HostName ${server_ip}
	 User ${server_user_name}
	 IdentityFile ${ssh_identity_file}
EOF
    
    return 0
}


function connect_to_server() {
    ssh -F $ssh_config_file
    return
}


# ssh
# server_ip 192.168.56.200
# server_user tester
ssh -F $ssh_config_file

# ssh config


read_setting "$@"

