#!/bin/bash

echo "TrainTime Garmin App Setup Script"
echo "================================="
echo ""

# Check if SDK is already installed
if [ -d "$HOME/garmin-sdk" ]; then
    echo "Garmin SDK already installed at $HOME/garmin-sdk"
else
    echo "Downloading Garmin Connect IQ SDK..."
    mkdir -p ~/garmin-sdk
    cd ~/garmin-sdk
    
    # Download SDK (you'll need to accept Garmin's license)
    echo "Please download the SDK manually from:"
    echo "https://developer.garmin.com/connect-iq/sdk/"
    echo "Extract it to: $HOME/garmin-sdk"
    echo ""
    echo "Press Enter when done..."
    read
fi

# Set up environment variables
echo ""
echo "Setting up environment variables..."
echo 'export PATH="$HOME/garmin-sdk/bin:$PATH"' >> ~/.bashrc
echo 'export GARMIN_SDK="$HOME/garmin-sdk"' >> ~/.bashrc

# Create developer key
echo ""
echo "Creating developer key (if not exists)..."
mkdir -p ~/.Garmin
if [ ! -f ~/.Garmin/developer_key.der ]; then
    echo "Generating developer key..."
    openssl genrsa -out ~/.Garmin/developer_key.pem 4096
    openssl pkcs8 -topk8 -inform PEM -outform DER -in ~/.Garmin/developer_key.pem -out ~/.Garmin/developer_key.der -nocrypt
    echo "Developer key created at ~/.Garmin/developer_key.der"
else
    echo "Developer key already exists"
fi

echo ""
echo "Setup complete! Please:"
echo "1. Source your bashrc: source ~/.bashrc"
echo "2. Make sure you have downloaded and extracted the SDK to ~/garmin-sdk"
echo "3. Your developer key is at ~/.Garmin/developer_key.der"