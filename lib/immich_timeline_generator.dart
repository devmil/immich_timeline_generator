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

  LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.address,
    this.accuracy = 10,
  });

  Map<String, dynamic> toGoogleTimelineJson() {
    return {
      'latitudeE7': (latitude * 10000000).round(),
      'longitudeE7': (longitude * 10000000).round(),
      'timestampMs': timestamp.millisecondsSinceEpoch.toString(),
      'accuracy': accuracy,
    };
  }
}

/// Main timeline generator class
class TimelineGenerator {
  final ImmichClient client;
  final int minPhotosPerLocation;

  TimelineGenerator({required this.client, this.minPhotosPerLocation = 3});

  /// Generate timeline from Immich photos
  Future<List<LocationPoint>> generateTimeline({String? albumId}) async {
    print('Fetching assets from Immich...');
    final assets = await client.fetchAssets(albumId: albumId);
    print('Found ${assets.length} assets');

    final locationPoints = <LocationPoint>[];
    final locationCounts = <String, int>{};
    int processedCount = 0;
    int skippedCount = 0;

    for (int i = 0; i < assets.length; i++) {
      final asset = assets[i];
      final assetId = asset['id'];

      // Show progress
      if (i % 50 == 0 || i == assets.length - 1) {
        final progress = ((i + 1) / assets.length * 100).toStringAsFixed(1);
        stdout.write(
          '\rProcessing assets: $progress% (${i + 1}/${assets.length}) | Found: $processedCount | Skipped: $skippedCount',
        );
      }

      try {
        final details = await client.fetchAssetDetails(assetId);
        if (details == null) {
          skippedCount++;
          continue;
        }

        final exifInfo = details['exifInfo'];
        if (exifInfo == null) {
          skippedCount++;
          continue;
        }

        final latitude = exifInfo['latitude'];
        final longitude = exifInfo['longitude'];

        if (latitude == null || longitude == null) {
          skippedCount++;
          continue;
        }

        final dateTimeOriginal =
            details['fileCreatedAt'] ?? details['fileModifiedAt'];
        if (dateTimeOriginal == null) {
          skippedCount++;
          continue;
        }

        final timestamp = DateTime.parse(dateTimeOriginal);

        // Create location key for counting
        final locationKey =
            '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';
        locationCounts[locationKey] = (locationCounts[locationKey] ?? 0) + 1;

        final locationPoint = LocationPoint(
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
          timestamp: timestamp,
        );

        locationPoints.add(locationPoint);
        processedCount++;

        // Add small delay to avoid overwhelming the server
        if (i % 50 == 0 && i > 0) {
          await Future.delayed(Duration(milliseconds: 100));
        }
      } catch (e) {
        skippedCount++;
        if (i % 100 == 0) {
          print('\nWarning: Error processing asset $assetId: $e');
        }
      }
    }

    print('\nFiltering locations with minimum $minPhotosPerLocation photos...');

    // Filter locations based on minimum photo count
    final filteredPoints = locationPoints.where((point) {
      final locationKey =
          '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
      return (locationCounts[locationKey] ?? 0) >= minPhotosPerLocation;
    }).toList();

    // Sort by timestamp
    filteredPoints.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    print(
      'Filtered ${locationPoints.length} points to ${filteredPoints.length} points',
    );
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
  final String outputPath;

  AppConfig({
    required this.immichUrl,
    required this.apiKey,
    this.albumName,
    this.minPhotosPerLocation = 3,
    required this.outputPath,
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
      final timeline = await generator.generateTimeline(albumId: albumId);

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
