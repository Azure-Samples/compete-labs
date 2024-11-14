#!/bin/bash

# Function to prompt user for confirmation
confirm() {
    while true; do
        read -p "Proceed with $1? (y): " choice
        case "$choice" in 
            y|Y ) echo "Proceeding with $1..."; return 0;;
            * ) echo "Invalid input. Please type 'y' to proceed.";;
        esac
    done
}

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
