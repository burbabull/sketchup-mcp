#!/bin/bash

# SketchUp MCP Extension RBZ Packager
# This script creates an RBZ file for the SketchUp MCP Server extension

set -e  # Exit on any error

# Configuration
EXTENSION_NAME="sketchup_mcp_server"
VERSION="1.7.0"
OUTPUT_FILE="${EXTENSION_NAME}_v${VERSION}.rbz"
TEMP_DIR="temp_rbz_build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}SketchUp MCP Server RBZ Packager${NC}"
echo -e "${BLUE}=================================${NC}"

# Check if required files exist
echo -e "${YELLOW}Checking required files...${NC}"
if [ ! -f "su_mcp.rb" ]; then
    echo -e "${RED}Error: su_mcp.rb not found${NC}"
    exit 1
fi

if [ ! -f "su_mcp/main.rb" ]; then
    echo -e "${RED}Error: su_mcp/main.rb not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All required files found${NC}"

# Clean up any previous build
if [ -d "$TEMP_DIR" ]; then
    echo -e "${YELLOW}Cleaning up previous build...${NC}"
    rm -rf "$TEMP_DIR"
fi

if [ -f "$OUTPUT_FILE" ]; then
    echo -e "${YELLOW}Removing existing RBZ file...${NC}"
    rm -f "$OUTPUT_FILE"
fi

# Create temporary directory structure
echo -e "${YELLOW}Creating build directory structure...${NC}"
mkdir -p "$TEMP_DIR"
mkdir -p "$TEMP_DIR/su_mcp"
mkdir -p "$TEMP_DIR/su_mcp/helpers"
mkdir -p "$TEMP_DIR/su_mcp/tools"

# Copy files to temporary directory
echo -e "${YELLOW}Copying extension files...${NC}"
cp "su_mcp.rb" "$TEMP_DIR/"
cp "su_mcp/main.rb" "$TEMP_DIR/su_mcp/"
cp "su_mcp/server.rb" "$TEMP_DIR/su_mcp/"

# Copy helper files
echo -e "${YELLOW}Copying helper files...${NC}"
cp su_mcp/helpers/*.rb "$TEMP_DIR/su_mcp/helpers/" 2>/dev/null || true

# Copy tool files
echo -e "${YELLOW}Copying tool files...${NC}"
cp su_mcp/tools/*.rb "$TEMP_DIR/su_mcp/tools/" 2>/dev/null || true

# Copy additional files if they exist
if [ -f "README.md" ]; then
    echo -e "${YELLOW}Adding README.md...${NC}"
    cp "README.md" "$TEMP_DIR/"
fi

if [ -f "LICENSE" ] || [ -f "LICENSE.txt" ]; then
    echo -e "${YELLOW}Adding license file...${NC}"
    cp LICENSE* "$TEMP_DIR/" 2>/dev/null || true
fi

# Create the RBZ file (ZIP format)
echo -e "${YELLOW}Creating RBZ package...${NC}"
cd "$TEMP_DIR"

# Check if zip command is available
if ! command -v zip &> /dev/null; then
    echo -e "${RED}Error: 'zip' command not found. Please install zip utility.${NC}"
    echo -e "${YELLOW}On macOS: brew install zip${NC}"
    echo -e "${YELLOW}On Ubuntu/Debian: sudo apt-get install zip${NC}"
    cd ..
    rm -rf "$TEMP_DIR"
    exit 1
fi

zip -r "../$OUTPUT_FILE" . -x "*.DS_Store" "*.git*" "*~" "*.tmp"

cd ..

# Clean up temporary directory
echo -e "${YELLOW}Cleaning up build directory...${NC}"
rm -rf "$TEMP_DIR"

# Verify the RBZ file was created
if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo -e "${GREEN}✓ RBZ file created successfully!${NC}"
    echo -e "${GREEN}  File: $OUTPUT_FILE${NC}"
    echo -e "${GREEN}  Size: $FILE_SIZE${NC}"
    echo ""
    echo -e "${BLUE}Installation Instructions:${NC}"
    echo -e "${YELLOW}1. Open SketchUp${NC}"
    echo -e "${YELLOW}2. Go to Window > Extension Manager${NC}"
    echo -e "${YELLOW}3. Click 'Install Extension'${NC}"
    echo -e "${YELLOW}4. Select the file: $OUTPUT_FILE${NC}"
    echo -e "${YELLOW}5. Click 'Install'${NC}"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo -e "${YELLOW}1. After installation, go to Plugins > MCP Server${NC}"
    echo -e "${YELLOW}2. Click 'Start Server' to begin the MCP server${NC}"
    echo -e "${YELLOW}3. The server will listen on localhost:9876${NC}"
else
    echo -e "${RED}Error: Failed to create RBZ file${NC}"
    exit 1
fi

echo -e "${GREEN}RBZ packaging complete!${NC}" 