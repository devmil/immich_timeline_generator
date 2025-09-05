import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Immich API client for fetching photo metadata
class ImmichClient {
  final String baseUrl;
  final String apiKey;
  late final Map<String, String> _headers;

  ImmichClient({required this.baseUrl, required this.apiKey}) {
    _headers = {'Content-Type': 'application/json', 'x-api-key': apiKey};
  }

  /// Fetch all assets from Immich using pagination
  Future<List<Map<String, dynamic>>> fetchAssets({String? albumId}) async {
    final url = '$baseUrl/api/search/metadata';
    final allAssets = <Map<String, dynamic>>[];
    const pageSize = 1000; // Maximum allowed by Immich
    int currentPage = 1;
    bool hasMorePages = true;

    while (hasMorePages) {
      final body = {'size': pageSize, 'page': currentPage, 'type': 'IMAGE'};

      if (albumId != null) {
        body['albumIds'] = [albumId];
      }

      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assets = List<Map<String, dynamic>>.from(
          data['assets']['items'] ?? [],
        );

        allAssets.addAll(assets);

        // Check if we have more pages - if we got fewer assets than the page size, we're done
        hasMorePages = assets.length == pageSize;

        if (hasMorePages) {
          currentPage++;
          print(
            'Fetched ${allAssets.length} assets so far (page $currentPage)...',
          );
        } else {
          print('Fetched all ${allAssets.length} assets');
        }
      } else {
        throw Exception(
          'Failed to fetch assets: ${response.statusCode} ${response.body}',
        );
      }
    }

    return allAssets;
  }

  /// Fetch detailed asset information including EXIF data
  Future<Map<String, dynamic>?> fetchAssetDetails(String assetId) async {
    final url = '$baseUrl/api/assets/$assetId';

    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print(
        'Warning: Failed to fetch asset details for $assetId: ${response.statusCode}',
      );
      return null;
    }
  }

  /// Fetch albums to allow folder filtering
  Future<List<Map<String, dynamic>>> fetchAlbums() async {
    final url = '$baseUrl/api/albums';

    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to fetch albums: ${response.statusCode}');
    }
  }
}

/// Represents a location with GPS coordinates and metadata
class LocationPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? address;
  final int accuracy;
  final String? cameraMake;
  final String? cameraModel;

  LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.address,
    this.accuracy = 10,
    this.cameraMake,
    this.cameraModel,
  });

  String get cameraInfo {
    if (cameraMake != null && cameraModel != null) {
      return '$cameraMake $cameraModel';
    } else if (cameraModel != null) {
      return cameraModel!;
    } else if (cameraMake != null) {
      return cameraMake!;
    } else {
      return 'Unknown Camera';
    }
  }

  Map<String, dynamic> toGoogleTimelineJson() {
    return {
      'latitudeE7': (latitude * 10000000).round(),
      'longitudeE7': (longitude * 10000000).round(),
      'timestamp': timestamp.toIso8601String(),
      'accuracy': accuracy,
    };
  }
}

/// Main timeline generator class
class TimelineGenerator {
  final ImmichClient client;
  final int minPhotosPerLocation;
  final int concurrentRequests;

  TimelineGenerator({
    required this.client,
    this.minPhotosPerLocation = 3,
    this.concurrentRequests = 20, // Number of concurrent API requests
  });

  /// Process a single asset and return LocationPoint if valid
  Future<LocationPoint?> _processAsset(Map<String, dynamic> asset) async {
    final assetId = asset['id'];

    try {
      final details = await client.fetchAssetDetails(assetId);
      if (details == null) return null;

      final exifInfo = details['exifInfo'];
      if (exifInfo == null) return null;

      final latitude = exifInfo['latitude'];
      final longitude = exifInfo['longitude'];

      if (latitude == null || longitude == null) return null;

      final dateTimeOriginal =
          details['fileCreatedAt'] ?? details['fileModifiedAt'];
      if (dateTimeOriginal == null) return null;

      final timestamp = DateTime.parse(dateTimeOriginal);

      // Extract camera information
      final cameraMake = exifInfo['make']?.toString().trim();
      final cameraModel = exifInfo['model']?.toString().trim();

      return LocationPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        timestamp: timestamp,
        cameraMake: cameraMake?.isEmpty == true ? null : cameraMake,
        cameraModel: cameraModel?.isEmpty == true ? null : cameraModel,
      );
    } catch (e) {
      // Silently skip assets with errors
      return null;
    }
  }

  /// Process assets in parallel batches
  Future<List<LocationPoint>> _processAssetsInParallel(
    List<Map<String, dynamic>> assets,
  ) async {
    final allPoints = <LocationPoint>[];
    final totalAssets = assets.length;
    int processedAssets = 0;

    // Process assets in batches to avoid overwhelming the server
    for (int i = 0; i < assets.length; i += concurrentRequests) {
      final batchEnd = (i + concurrentRequests < assets.length)
          ? i + concurrentRequests
          : assets.length;
      final batch = assets.sublist(i, batchEnd);

      // Process this batch in parallel
      final futures = batch.map((asset) => _processAsset(asset)).toList();
      final results = await Future.wait(futures);

      // Filter out null results and add to collection
      final validPoints = results.whereType<LocationPoint>().toList();
      allPoints.addAll(validPoints);

      processedAssets += batch.length;
      final progress = (processedAssets / totalAssets * 100).toStringAsFixed(1);
      final foundCount = allPoints.length;
      final skippedCount = processedAssets - foundCount;

      stdout.write(
        '\rProcessing assets: $progress% ($processedAssets/$totalAssets) | Found: $foundCount | Skipped: $skippedCount',
      );

      // Small delay between batches to be nice to the server
      if (i + concurrentRequests < assets.length) {
        await Future.delayed(Duration(milliseconds: 50));
      }
    }

    print(''); // New line after progress
    return allPoints;
  }

  /// Analyze cameras used and get user selection with paginated UI
  Future<Set<String>> _selectCameras(List<LocationPoint> allPoints) async {
    // Count photos per camera
    final cameraStats = <String, int>{};
    for (final point in allPoints) {
      final cameraInfo = point.cameraInfo;
      cameraStats[cameraInfo] = (cameraStats[cameraInfo] ?? 0) + 1;
    }

    // Sort cameras by photo count (most used first)
    final sortedCameras = cameraStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    print('\nDetected ${sortedCameras.length} camera(s):');
    print('=' * 60);

    final selectedCameras = <String>{};
    const int itemsPerPage = 8; // Show 8 cameras per page + navigation options
    int currentPage = 0;
    final int totalPages = ((sortedCameras.length - 1) ~/ itemsPerPage) + 1;

    while (true) {
      // Clear screen and show current page
      print('\n' * 2); // Add some space
      print('Camera Selection - Page ${currentPage + 1} of $totalPages');
      print('=' * 60);

      // Calculate page bounds
      final startIndex = currentPage * itemsPerPage;
      final endIndex = (startIndex + itemsPerPage).clamp(
        0,
        sortedCameras.length,
      );

      // Show "All cameras" option on first page
      if (currentPage == 0) {
        final allSelected = selectedCameras.length == sortedCameras.length;
        print(
          '0. [${allSelected ? '✓' : ' '}] All cameras (${allPoints.length} total photos)',
        );
      }

      // Show cameras for current page
      for (int i = startIndex; i < endIndex; i++) {
        final camera = sortedCameras[i];
        final percentage = (camera.value / allPoints.length * 100)
            .toStringAsFixed(1);
        final isSelected = selectedCameras.contains(camera.key);
        final displayIndex = (i - startIndex) + 1;

        print(
          '$displayIndex. [${isSelected ? '✓' : ' '}] ${camera.key.padRight(35)} ${camera.value.toString().padLeft(5)} photos (${percentage}%)',
        );
      }

      print('');
      print('Commands:');
      print('  1-$itemsPerPage : Toggle camera selection');
      if (currentPage == 0) print('  0       : Toggle all cameras');
      if (currentPage > 0) print('  p       : Previous page');
      if (currentPage < totalPages - 1) print('  n       : Next page');
      print('  done    : Finish selection');
      print('  help    : Show this help');
      print('');
      print(
        'Selected: ${selectedCameras.length}/${sortedCameras.length} cameras',
      );

      stdout.write('Enter command: ');
      final input = stdin.readLineSync()?.trim().toLowerCase();

      if (input == null || input.isEmpty) continue;

      if (input == 'done') {
        if (selectedCameras.isEmpty) {
          print('No cameras selected! Selecting all cameras by default.');
          selectedCameras.addAll(sortedCameras.map((e) => e.key));
        }
        break;
      } else if (input == 'help') {
        continue; // Will redisplay the page with help
      } else if (input == 'n' && currentPage < totalPages - 1) {
        currentPage++;
      } else if (input == 'p' && currentPage > 0) {
        currentPage--;
      } else if (input == '0' && currentPage == 0) {
        // Toggle all cameras
        if (selectedCameras.length == sortedCameras.length) {
          selectedCameras.clear();
        } else {
          selectedCameras.clear();
          selectedCameras.addAll(sortedCameras.map((e) => e.key));
        }
      } else {
        // Try to parse as camera selection number
        final number = int.tryParse(input);
        if (number != null && number >= 1 && number <= itemsPerPage) {
          final actualIndex = startIndex + number - 1;
          if (actualIndex < sortedCameras.length) {
            final camera = sortedCameras[actualIndex];
            if (selectedCameras.contains(camera.key)) {
              selectedCameras.remove(camera.key);
            } else {
              selectedCameras.add(camera.key);
            }
          }
        } else {
          print('Invalid command. Type "help" for available commands.');
          await Future.delayed(Duration(seconds: 1));
        }
      }
    }

    print('\nFinal selection:');
    if (selectedCameras.length == sortedCameras.length) {
      print('Selected: All cameras');
    } else {
      print('Selected cameras: ${selectedCameras.join(', ')}');
    }

    // Show stats for selected cameras
    final totalSelectedPhotos = selectedCameras
        .map((camera) => cameraStats[camera] ?? 0)
        .fold(0, (a, b) => a + b);
    print('Total photos from selected cameras: $totalSelectedPhotos');

    return selectedCameras;
  }

  Future<List<LocationPoint>> generateTimeline({
    String? albumId,
    bool skipCameraSelection = false,
  }) async {
    print('Fetching assets from Immich...');
    final assets = await client.fetchAssets(albumId: albumId);
    print('Found ${assets.length} assets');
    print('Processing with $concurrentRequests concurrent requests...');

    // Process all assets in parallel
    final locationPoints = await _processAssetsInParallel(assets);

    print('Found ${locationPoints.length} assets with GPS coordinates');

    List<LocationPoint> cameraFilteredPoints;

    if (skipCameraSelection) {
      print('Skipping camera selection - using all photos');
      cameraFilteredPoints = locationPoints;
    } else {
      // Camera selection
      final selectedCameras = await _selectCameras(locationPoints);

      // Filter by selected cameras
      cameraFilteredPoints = locationPoints.where((point) {
        return selectedCameras.contains(point.cameraInfo);
      }).toList();

      print('After camera filtering: ${cameraFilteredPoints.length} points');
    }

    // Count locations for filtering
    final locationCounts = <String, int>{};
    for (final point in cameraFilteredPoints) {
      final locationKey =
          '${point.latitude.toStringAsFixed(2)},${point.longitude.toStringAsFixed(2)}';
      locationCounts[locationKey] = (locationCounts[locationKey] ?? 0) + 1;
    }

    print('Filtering locations with minimum $minPhotosPerLocation photos...');

    // Filter locations based on minimum photo count
    final filteredPoints = cameraFilteredPoints.where((point) {
      final locationKey =
          '${point.latitude.toStringAsFixed(2)},${point.longitude.toStringAsFixed(2)}';
      return (locationCounts[locationKey] ?? 0) >= minPhotosPerLocation;
    }).toList();

    // Sort by timestamp
    filteredPoints.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    print('Final result: ${filteredPoints.length} points after all filtering');
    return filteredPoints;
  }

  /// Export timeline to Google Records.json format
  Future<void> exportToGoogleFormat(
    List<LocationPoint> points,
    String outputPath,
  ) async {
    print('Exporting to Google Timeline format...');

    final locations = points
        .map((point) => point.toGoogleTimelineJson())
        .toList();

    final recordsData = {'locations': locations};

    final file = File(outputPath);
    await file.writeAsString(jsonEncode(recordsData));

    print('Timeline exported to: $outputPath');
    print('Total locations: ${locations.length}');
  }
}

/// Configuration class for the application
class AppConfig {
  final String immichUrl;
  final String apiKey;
  final String? albumName;
  final int minPhotosPerLocation;
  final int concurrentRequests;
  final String outputPath;
  final bool skipCameraSelection;

  AppConfig({
    required this.immichUrl,
    required this.apiKey,
    this.albumName,
    this.minPhotosPerLocation = 3,
    this.concurrentRequests = 20,
    required this.outputPath,
    this.skipCameraSelection = false,
  });
}

/// Main application runner
class ImmichTimelineApp {
  final AppConfig config;
  late final ImmichClient client;
  late final TimelineGenerator generator;

  ImmichTimelineApp(this.config) {
    client = ImmichClient(baseUrl: config.immichUrl, apiKey: config.apiKey);
    generator = TimelineGenerator(
      client: client,
      minPhotosPerLocation: config.minPhotosPerLocation,
      concurrentRequests: config.concurrentRequests,
    );
  }

  Future<void> run() async {
    try {
      print('Immich Timeline Generator');
      print('========================');
      print('Immich URL: ${config.immichUrl}');
      print('Min photos per location: ${config.minPhotosPerLocation}');
      if (config.albumName != null) {
        print('Album filter: ${config.albumName}');
      }
      print('Output: ${config.outputPath}');
      print('');

      String? albumId;

      // If album name is specified, find the album ID
      if (config.albumName != null) {
        print('Finding album: ${config.albumName}');
        final albums = await client.fetchAlbums();
        final album = albums.firstWhere(
          (album) =>
              album['albumName'].toString().toLowerCase() ==
              config.albumName!.toLowerCase(),
          orElse: () =>
              throw Exception('Album "${config.albumName}" not found'),
        );
        albumId = album['id'];
        print('Found album ID: $albumId');
      }

      // Generate timeline
      final timeline = await generator.generateTimeline(
        albumId: albumId,
        skipCameraSelection: config.skipCameraSelection,
      );

      if (timeline.isEmpty) {
        print('No location data found matching the criteria.');
        return;
      }

      // Export to Google format
      await generator.exportToGoogleFormat(timeline, config.outputPath);

      print('\nSuccess! Timeline generated successfully.');
      print(
        'Date range: ${DateFormat('yyyy-MM-dd').format(timeline.first.timestamp)} to ${DateFormat('yyyy-MM-dd').format(timeline.last.timestamp)}',
      );
    } catch (e) {
      print('Error: $e');
      exit(1);
    }
  }
}
