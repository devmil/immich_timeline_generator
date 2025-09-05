#!/bin/bash

# Example usage script for Immich Timeline Generator
# Copy this file and modify the variables below for your setup

# Configuration
IMMICH_URL="https://your-immich-server.com"
API_KEY="your-api-key-here"

# Optional settings
ALBUM_NAME=""  # Leave empty for all photos, or set to specific album name
MIN_PHOTOS=3   # Minimum photos per location
OUTPUT_FILE="Records.json"

echo "Immich Timeline Generator - Example Usage"
echo "========================================"

# Basic usage (all photos)
echo "Example 1: Generate timeline from all photos"
echo "Command: dart run bin/immich_timeline_generator.dart -u \"$IMMICH_URL\" -k \"$API_KEY\" -m $MIN_PHOTOS -o \"$OUTPUT_FILE\""
echo ""

# Album-filtered usage
echo "Example 2: Generate timeline from specific album"
echo "Command: dart run bin/immich_timeline_generator.dart -u \"$IMMICH_URL\" -k \"$API_KEY\" -a \"Travel Photos\" -m 5 -o \"travel_timeline.json\""
echo ""

# Minimal filtering
echo "Example 3: Include all locations (minimal filtering)"
echo "Command: dart run bin/immich_timeline_generator.dart -u \"$IMMICH_URL\" -k \"$API_KEY\" -m 1 -o \"complete_timeline.json\""
echo ""

echo "To run any of these examples:"
echo "1. Update the IMMICH_URL and API_KEY variables above"
echo "2. Copy and paste the command you want to use"
echo "3. Or uncomment one of the lines below and run this script"

# Uncomment one of these lines to run automatically:
# dart run bin/immich_timeline_generator.dart -u "$IMMICH_URL" -k "$API_KEY" -m $MIN_PHOTOS -o "$OUTPUT_FILE"
# dart run bin/immich_timeline_generator.dart -u "$IMMICH_URL" -k "$API_KEY" -a "Travel Photos" -m 5 -o "travel_timeline.json"
# dart run bin/immich_timeline_generator.dart -u "$IMMICH_URL" -k "$API_KEY" -m 1 -o "complete_timeline.json"
