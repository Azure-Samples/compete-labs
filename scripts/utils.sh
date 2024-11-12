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
