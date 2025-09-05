# Changelog

## [1.0.0] - 2024-09-05

### Added
- **Immich Integration**: Connect to Immich server using API key authentication
- **GPS Data Extraction**: Extract GPS coordinates from photo EXIF data
- **Google Timeline Export**: Generate Records.json format compatible with Reitti and other timeline services
- **Album Filtering**: Filter photos by specific album/folder name
- **Location Filtering**: Configurable minimum number of photos per location to filter out random GPS coordinates
- **Progress Tracking**: Real-time progress display for large photo libraries
- **Command Line Interface**: Full CLI with help, examples, and argument validation
- **Error Handling**: Comprehensive error handling with informative messages
- **Unit Tests**: Test coverage for core functionality

### Features
- Support for large photo libraries with efficient processing
- Case-insensitive album name matching
- Configurable output file path
- Compatible with Google Timeline format specifications
- UTC timestamp handling for accurate timeline generation
- Robust API error handling and retry logic

### Technical Details
- Built with Dart 3.9.0+
- Uses HTTP client for Immich API communication
- JSON parsing and generation for timeline data
- Command-line argument parsing with validation
- Comprehensive documentation and examples
