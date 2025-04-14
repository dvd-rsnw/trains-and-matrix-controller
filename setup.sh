#!/bin/bash

# Exit on error
set -e

# Function to check if we're in the right directory
check_project_dir() {
    if [ ! -f "requirements.txt" ]; then
        echo "Error: requirements.txt not found. Make sure you're in the 7th-ave-trains directory."
        echo "Current directory: $(pwd)"
        exit 1
    fi
}

# Function to check virtual environment
check_venv() {
    if [ ! -f ".venv/bin/pip" ]; then
        echo "Error: Virtual environment not properly created. Missing pip."
        echo "Current directory: $(pwd)"
        exit 1
    fi
}

echo "Setting up 7th Ave Trains Display..."

# Store the project directory
PROJECT_DIR="$PWD"
check_project_dir

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    python3-pip \
    python3-venv \
    python3-full \
    git \
    build-essential \
    python3-dev \
    python3-pillow \
    gcc \
    make \
    libgraphicsmagick++-dev \
    libwebp-dev \
    libjpeg-dev \
    libpng-dev \
    pkg-config

# Clone and build rpi-rgb-led-matrix
echo "Setting up RGB LED Matrix library..."
cd ~
if [ -d "rpi-rgb-led-matrix" ]; then
    echo "Removing existing RGB Matrix library..."
    sudo rm -rf rpi-rgb-led-matrix
fi

# Clone with regular user permissions
git clone https://github.com/hzeller/rpi-rgb-led-matrix.git
cd ~/rpi-rgb-led-matrix

# Build with optimizations for Raspberry Pi
echo "Building RGB Matrix C++ library..."
cd ~/rpi-rgb-led-matrix/lib
make clean
export CFLAGS="-O3 -fomit-frame-pointer -funroll-loops"
export CXXFLAGS="$CFLAGS"
make -j4 RGB_LIB_DISTRIBUTION=1 HARDWARE_DESC=2

# Build Python bindings
echo "Building Python bindings..."
cd ~/rpi-rgb-led-matrix/bindings/python
make clean
make build-python HARDWARE_DESC=2 PYTHON=$(which python3) CFLAGS="-O3 -fomit-frame-pointer -funroll-loops" RGB_LIB_DISTRIBUTION=1

if [ ! -f "build/lib."*"/rgbmatrix/_core."*".so" ]; then
    echo "Error: Failed to build RGB Matrix Python bindings"
    echo "Build directory contents:"
    ls -R build/
    exit 1
fi

# Setup virtual environment and install dependencies
echo "Setting up Python environment and dependencies..."
cd "$PROJECT_DIR"
check_project_dir

# Remove existing venv if it exists
if [ -d ".venv" ]; then
    echo "Removing existing virtual environment..."
    rm -rf .venv
fi

# Create new virtual environment
echo "Creating new virtual environment..."
python3 -m venv .venv

# Verify virtual environment was created
if [ ! -d ".venv" ]; then
    echo "Error: Failed to create virtual environment"
    exit 1
fi

# Make sure the virtual environment is accessible
chmod -R 755 .venv

# Configure virtual environment to show prompt
cat >> .venv/bin/activate << EOL
PS1="(.venv) \$PS1"
EOL

# Activate virtual environment and install dependencies
echo "Installing Python dependencies..."
source .venv/bin/activate
check_venv

# Ensure pip is available and upgrade it
echo "Upgrading pip and installing basic tools..."
python3 -m pip install --upgrade pip wheel setuptools

echo "Installing project dependencies..."
python3 -m pip install -r requirements.txt

# Install RGB Matrix Python module into virtual environment
echo "Installing RGB Matrix Python module into virtual environment..."
cd ~/rpi-rgb-led-matrix/bindings/python
rm -rf build dist *.egg-info  # Clean any existing build artifacts
python3 setup.py clean --all
CFLAGS="-O3 -fomit-frame-pointer -funroll-loops" python3 setup.py build
python3 setup.py install --user

# Return to project directory
cd "$PROJECT_DIR"
check_project_dir

echo "Creating run script..."
cat > run.sh << EOF
#!/bin/bash

# Check if running as root
if [ "\$(id -u)" != "0" ]; then
   echo "This script must be run as root (use sudo)" 1>&2
   exit 1
fi

# Check if we're in the right directory
if [ ! -f "requirements.txt" ]; then
    echo "Error: Must be run from the 7th-ave-trains directory"
    exit 1
fi

# Activate virtual environment with full path and preserve environment
source "\$PWD/.venv/bin/activate"

# Start the API server in the background
echo "Starting API server..."
python3 main.py &
API_PID=\$!

# Wait a moment for the API to start
sleep 2

# Start the LED controller
echo "Starting LED display controller..."
python3 led_matrix_controller.py

# When LED controller exits, kill the API server
kill \$API_PID
EOF

# Make run script executable
chmod +x run.sh

echo "Setup complete! To run the display:"
echo "  cd $PROJECT_DIR"
echo "  sudo ./run.sh"

# Show virtual environment status
echo -e "\nCurrent virtual environment status:"
which python
python -c "import sys; print(sys.prefix)" 