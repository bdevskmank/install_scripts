#!/bin/bash


sudo apt-get install gcc  curl autoconf gdb libpcap-dev -y

rm -f gitclone.sh
cat <<'EOF' >> gitclone.sh
#!/bin/bash

# Script to initialize and manage a Git repository with a private access token on Ubuntu 24.04

# Exit on any error
set -e

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo "Git is not installed. Installing..."
    sudo apt update
    sudo apt install -y git
fi

# Prompt for repository details if not provided as arguments
if [ $# -lt 4 ]; then
    echo "Usage: $0 <repository_url> <github_username> <destination_folder> <personal_access_token>"
    echo "Example: $0 https://github.com/bdevskmank/nDPI.git bdevskmank my_project ghp_xxxxxxxxxxxxxxxx"
    exit 1
fi

REPO_URL="$1"
USERNAME="$2"
DEST_FOLDER="$3"
PAT="$4"

# Validate repository URL format
if [[ ! "$REPO_URL" =~ ^https://github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.git$ ]]; then
    echo "Error: Invalid repository URL. Expected format: https://github.com/username/repo.git"
    exit 1
fi

# Validate destination folder
if [ -z "$DEST_FOLDER" ]; then
    echo "Error: Destination folder cannot be empty."
    exit 1
fi

# Validate PAT
if [ -z "$PAT" ]; then
    echo "Error: Personal Access Token cannot be empty."
    exit 1
fi

# URL-encode the username and PAT to handle special characters
encode_url() {
    local string="$1"
    local encoded=""
    local pos c o
    for ((pos=0; pos<${#string}; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) o="$c" ;;
            *) printf -v o '%%%02x' "'$c" ;;
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

ENCODED_USERNAME=$(encode_url "$USERNAME")
ENCODED_PAT=$(encode_url "$PAT")

# Configure Git global settings
git config --global user.name "$USERNAME"
git config --global user.email "$USERNAME@gmail.com" # Adjust if needed
git config --global credential.helper 'store' # Stores credentials in ~/.git-credentials

# Construct the authenticated URL
AUTH_URL=$(echo "$REPO_URL" | sed "s|https://|https://${ENCODED_USERNAME}:${ENCODED_PAT}@|")

# Clone the private repository to the specified destination folder
echo "Cloning repository into $DEST_FOLDER..."
if [ -d "$DEST_FOLDER" ]; then
    echo "Directory '$DEST_FOLDER' already exists. Skipping clone."
else
    git clone "$AUTH_URL" "$DEST_FOLDER"
fi
cd "$DEST_FOLDER"

# Example Git workflow: Add, commit, and push changes
echo "Performing example Git operations..."



# Reminder about credential storage
echo "Note: Your token is stored in ~/.git-credentials (plain text). Consider using SSH for better security."
EOF


chmod a+x gitclone.sh


./gitclone.sh   $NDPI_URL $USERNAME $NDPI_FOLDER $PAT

cd $USER_HOME_FOLDER/nDPI
./autogen.sh
./configure
make
make install 
