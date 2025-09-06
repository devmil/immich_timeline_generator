# Release Instructions

This repository includes automated GitHub Actions workflows for building and releasing the Immich Timeline Generator across multiple platforms.

## Workflows

### 1. CI Workflow (`.github/workflows/ci.yml`)
- **Triggers**: Every push to `main` branch and all pull requests
- **Purpose**: Runs tests, formatting checks, and build verification
- **Platforms**: Ubuntu, macOS, Windows
- **Actions**: 
  - Format checking with `dart format`
  - Static analysis with `dart analyze`
  - Unit tests with `dart test`
  - Build verification

### 2. Release Workflow (`.github/workflows/release.yml`)
- **Triggers**: When you push a version tag (e.g., `v1.0.0`, `v2.1.3`)
- **Purpose**: Creates cross-platform binaries and GitHub releases
- **Platforms**: 
  - Linux (x64, ARM64)
  - macOS (x64, ARM64)
  - Windows (x64)

## Creating a Release

### Step 1: Update Version
First, update the version in `pubspec.yaml`:

```yaml
name: immich_timeline_generator
description: A console application to generate Google Timeline from Immich photos.
version: 1.2.0  # Update this version number
```

### Step 2: Commit Changes
```bash
git add .
git commit -m "Release v1.2.0"
git push origin main
```

### Step 3: Create and Push Tag
```bash
# Create a version tag
git tag v1.2.0

# Push the tag to trigger the release workflow
git push origin v1.2.0
```

### Step 4: Monitor Workflow
1. Go to your GitHub repository
2. Click on the "Actions" tab
3. Watch the "Build and Release" workflow execute
4. Once complete, check the "Releases" section for your new release

## What Gets Built

The workflow will create the following binaries:

| Platform | Architecture | Filename |
|----------|-------------|----------|
| Linux | x64 (Intel/AMD) | `immich_timeline_generator-linux-x64` |
| Linux | ARM64 (Pi, etc.) | `immich_timeline_generator-linux-arm64` |
| macOS | x64 (Intel Macs) | `immich_timeline_generator-macos-x64` |
| Windows | x64 | `immich_timeline_generator-windows-x64.exe` |

**Note**: 
- Each binary is compiled on its native platform to ensure compatibility
- Linux ARM64 is cross-compiled on Ubuntu runners (supported by Dart)
- **Apple Silicon Mac users**: Use Rosetta 2 to run the Intel binary, or build from source
- **No universal macOS binary**: Dart doesn't support creating universal binaries directly

## Download and Usage

Users can download the appropriate binary from the GitHub Releases page:

```bash
# Linux/macOS: Make executable
chmod +x immich_timeline_generator-*

# Run the tool
./immich_timeline_generator-linux-x64 --help
./immich_timeline_generator-macos-x64 --help
```

```powershell
# Windows: Run directly
immich_timeline_generator-windows-x64.exe --help
```

## Troubleshooting

### Common Issues

1. **Workflow fails to trigger**: Ensure the tag follows the pattern `v*.*.*` (e.g., `v1.0.0`)
2. **Build fails**: Check that all tests pass locally with `dart test`
3. **Permission errors**: The workflow needs `contents: write` permission to create releases

### Testing Locally

Before creating a release, test the build process locally:

```bash
# Install dependencies
dart pub get

# Run tests
dart test

# Test compilation
dart compile exe bin/immich_timeline_generator.dart -o test-build

# Clean up
rm test-build
```

## Security Notes

- The workflow uses `GITHUB_TOKEN` which is automatically provided by GitHub
- No additional secrets are required for the basic workflow
- All builds are performed in GitHub's secure runners
- Artifacts are temporarily stored and then attached to releases

## Workflow Permissions

The release workflow requires:
- `contents: write` - To create releases and upload assets
- Standard repository access for checking out code and running builds

These permissions are automatically granted when the workflow is triggered by tag pushes.
