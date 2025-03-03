#!/bin/bash
# This script deletes all files ending with .ok in the current directory and its subdirectories.

echo "Deleting all *.ok files from $(pwd)..."
find . -type f -name "*.ok" -delete
echo "Deletion complete."
