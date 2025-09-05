import 'package:immich_timeline_generator/immich_timeline_generator.dart';
import 'package:test/test.dart';

void main() {
  group('LocationPoint', () {
    test('converts to Google Timeline format correctly', () {
      // Use a known timestamp: January 1, 2024 00:00:00 UTC
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        1704067200000,
        isUtc: true,
      );

      final point = LocationPoint(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: timestamp,
        accuracy: 15,
      );

      final json = point.toGoogleTimelineJson();

      expect(json['latitudeE7'], equals(377749000));
      expect(json['longitudeE7'], equals(-1224194000));
      expect(json['timestamp'], equals('2024-01-01T00:00:00.000Z'));
      expect(json['accuracy'], equals(15));
    });
  });

  group('AppConfig', () {
    test('creates configuration with required parameters', () {
      final config = AppConfig(
        immichUrl: 'https://immich.example.com',
        apiKey: 'test-api-key',
        outputPath: 'test_output.json',
      );

      expect(config.immichUrl, equals('https://immich.example.com'));
      expect(config.apiKey, equals('test-api-key'));
      expect(config.outputPath, equals('test_output.json'));
      expect(config.minPhotosPerLocation, equals(3)); // default value
      expect(config.albumName, isNull);
    });

    test('creates configuration with optional parameters', () {
      final config = AppConfig(
        immichUrl: 'https://immich.example.com',
        apiKey: 'test-api-key',
        albumName: 'Test Album',
        minPhotosPerLocation: 5,
        outputPath: 'custom_output.json',
      );

      expect(config.albumName, equals('Test Album'));
      expect(config.minPhotosPerLocation, equals(5));
    });
  });

  group('ImmichClient', () {
    test('initializes with correct headers', () {
      final client = ImmichClient(
        baseUrl: 'https://immich.example.com',
        apiKey: 'test-key',
      );

      expect(client.baseUrl, equals('https://immich.example.com'));
      expect(client.apiKey, equals('test-key'));
    });
  });
}
