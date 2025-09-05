import 'dart:io';
import 'package:args/args.dart';
import 'package:immich_timeline_generator/immich_timeline_generator.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'url',
      abbr: 'u',
      help: 'Immich server URL (e.g., https://immich.example.com)',
    )
    ..addOption('api-key', abbr: 'k', help: 'Immich API key')
    ..addOption('album', abbr: 'a', help: 'Album name to filter (optional)')
    ..addOption(
      'min-photos',
      abbr: 'm',
      defaultsTo: '3',
      help: 'Minimum number of photos per location (default: 3)',
    )
    ..addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'Records.json',
      help: 'Output file path (default: Records.json)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message',
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      _printUsage(parser);
      return;
    }

    // Validate required arguments
    final url = results['url'] as String?;
    final apiKey = results['api-key'] as String?;

    if (url == null || apiKey == null) {
      print('Error: Missing required arguments\n');
      _printUsage(parser);
      exit(1);
    }

    // Parse optional arguments
    final albumName = results['album'] as String?;
    final minPhotos = int.tryParse(results['min-photos'] as String) ?? 3;
    final outputPath = results['output'] as String;

    // Validate min-photos
    if (minPhotos < 1) {
      print('Error: min-photos must be at least 1');
      exit(1);
    }

    // Create configuration
    final config = AppConfig(
      immichUrl: url.endsWith('/') ? url.substring(0, url.length - 1) : url,
      apiKey: apiKey,
      albumName: albumName,
      minPhotosPerLocation: minPhotos,
      outputPath: outputPath,
    );

    // Run the application
    final app = ImmichTimelineApp(config);
    await app.run();
  } catch (e) {
    print('Error parsing arguments: $e\n');
    _printUsage(parser);
    exit(1);
  }
}

void _printUsage(ArgParser parser) {
  print('Immich Timeline Generator');
  print('Generates Google Timeline format from Immich photos with GPS data');
  print('');
  print('Usage: dart run bin/immich_timeline_generator.dart [options]');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('  # Basic usage');
  print(
    '  dart run bin/immich_timeline_generator.dart -u https://immich.example.com -k your-api-key',
  );
  print('');
  print('  # Filter by album and set minimum photos per location');
  print(
    '  dart run bin/immich_timeline_generator.dart -u https://immich.example.com -k your-api-key -a "Travel Photos" -m 5',
  );
  print('');
  print('  # Custom output file');
  print(
    '  dart run bin/immich_timeline_generator.dart -u https://immich.example.com -k your-api-key -o my_timeline.json',
  );
}
