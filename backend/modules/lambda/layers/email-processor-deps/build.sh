#!/bin/bash

# Build Lambda layer for email processor dependencies

set -e

echo "Building email processor Lambda layer..."

# Create python directory structure
mkdir -p python/lib/python3.11/site-packages

# Install dependencies
pip install -r requirements.txt -t python/lib/python3.11/site-packages/

echo "Lambda layer built successfully"
