#!/usr/bin/env python3
"""
Unified PHP build manager for static-php-cli CI/CD.
Handles version checking, archive creation, metadata updates, and EOL cleanup.
"""

import json
import argparse
import hashlib
import tarfile
import subprocess
from datetime import datetime, UTC
from pathlib import Path

def load_json(filepath):
    """Load JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)


def save_json(data, filepath):
    """Save JSON file with pretty formatting."""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)


def generate_build_timestamp():
    """Generate unique build timestamp - SINGLE source of truth for timestamps"""
    return datetime.now(UTC).strftime("%Y%m%d%H%M%S")


def get_archive_filename(full_version, os_name, timestamp):
    """Generate filename with timestamp - ONLY way to generate filename"""
    return f"php-{full_version}-{timestamp}-{os_name}.tar.xz"


def calculate_sha512(filepath):
    """Calculate SHA512 hash of a file."""
    hash_sha512 = hashlib.sha512()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            hash_sha512.update(chunk)
    return hash_sha512.hexdigest()


def fetch_version_details(version):
    """Fetch detailed version info from PHP.net API."""
    url = f"https://www.php.net/releases/index.php?json&version={version}"
    result = subprocess.run(['curl', '-fsSL', url], capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    return None


def check_versions():
    """Check PHP versions and generate build matrix."""
    metadata = load_json('metadata.json')
    api_data = load_json('api_response.json')

    all_os = ['macos-aarch64']
    os_runners = {'macos-aarch64': 'macos-latest'}

    build_matrix = []
    eol_versions = []

    # Get supported versions from the latest PHP branch (usually "8")
    supported_versions = []
    if "8" in api_data:
        supported_versions = api_data["8"].get("supported_versions", [])

    # Cache all version details with single API calls
    version_details_cache = {}
    print("Fetching version details for all supported versions...")
    for version_branch in supported_versions:
        version_details = fetch_version_details(version_branch)
        if version_details:
            version_name = version_details.get('version')
            if version_name:
                version_details_cache[version_name] = version_details
                print(f"Cached details for {version_name}")
        else:
            print(f"Failed to fetch details for {version_branch}")

    # Process each cached version
    for full_version, version_details in version_details_cache.items():
        # Extract major.minor version (e.g., "8.4" from "8.4.13")
        version_parts = full_version.split('.')
        if len(version_parts) >= 2:
            major_minor = f"{version_parts[0]}.{version_parts[1]}"
        else:
            major_minor = full_version

        # Check if we need to build this version
        need_build = False

        if major_minor not in metadata['versions']:
            need_build = True
            print(f"New version detected: {full_version} (metadata key: {major_minor})")
        else:
            api_release = version_details.get('date', '')
            metadata_release = metadata['versions'][major_minor].get('releaseDate', '')
            if api_release != metadata_release:
                need_build = True
                print(f"Updated version detected: {full_version} (metadata key: {major_minor})")

        if need_build:
            for os_name in all_os:
                build_matrix.append({
                    'php-version': major_minor,
                    'full-version': full_version,
                    'os': os_name,
                    'runs-on': os_runners[os_name],
                    'releaseDate': version_details.get('date', '')
                })

    # Check for EOL versions in metadata
    for version_name in metadata['versions']:
        # Extract major.minor from version (e.g., "8.3" from "8.3.26")
        version_parts = version_name.split('.')
        if len(version_parts) >= 2:
            major_minor = f"{version_parts[0]}.{version_parts[1]}"
            if major_minor not in supported_versions:
                eol_versions.append(version_name)
                print(f"EOL version detected: {version_name}")

    # Output results
    matrix_json = json.dumps({'include': build_matrix})
    eol_json = json.dumps(eol_versions)
    should_build = 'true' if build_matrix else 'false'

    print(f"Build matrix: {len(build_matrix)} items")
    print(f"EOL versions: {len(eol_versions)} items")

    with open('github_output.txt', 'w') as f:
        f.write(f'matrix={matrix_json}\n')
        f.write(f'eol={eol_json}\n')
        f.write(f'should-build={should_build}\n')


def create_archive(php_version, os_name, timestamp):
    """Create tar.xz archive containing both CLI and FPM binaries with timestamp."""
    # STRICT: timestamp is REQUIRED - no legacy support
    if not timestamp:
        raise ValueError("Timestamp is required - no legacy support")

    archive_name = get_archive_filename(php_version, os_name, timestamp)

    # Create tar.xz archive
    with tarfile.open(archive_name, 'w:xz') as tar:
        # Add CLI binary as 'php-cli'
        tar.add('buildroot/bin/php', arcname='php-cli')
        # Add FPM binary as 'php-fpm'
        tar.add('buildroot/bin/php-fpm', arcname='php-fpm')

    # Calculate SHA512
    sha512_hash = calculate_sha512(archive_name)

    # Save hash to environment for workflow
    with open('archive_info.txt', 'w') as f:
        f.write(f'ARCHIVE_NAME={archive_name}\n')
        f.write(f'ARCHIVE_SHA512={sha512_hash}\n')

    print(f"Created {archive_name}")
    print(f"SHA512: {sha512_hash}")


def update_metadata(build_matrix_json, archive_checksums):
    """Update metadata.json with build results - STRICT format validation."""
    metadata = load_json('metadata.json') if Path('metadata.json').exists() else {'last_sync': '', 'versions': {}}
    build_matrix = json.loads(build_matrix_json)

    # Parse archive checksums (STRICT format: version,os,sha512,filename)
    checksums_map = {}
    for line in archive_checksums.strip().split('\n'):
        if line:
            parts = line.split(',')
            if len(parts) != 4:  # STRICT: Must have all 4 fields
                raise ValueError(f"Invalid checksum format - expected version,os,sha512,filename: {line}")

            version, os_name, sha512, filename = parts
            checksums_map[f"{version}-{os_name}"] = {
                'sha512': sha512,
                'filename': filename
            }

    # Update timestamp
    metadata['last_sync'] = datetime.now(UTC).isoformat().replace('+00:00', 'Z')

    # Process each build
    for build in build_matrix.get('include', []):
        major_minor = build['php-version']  # Format X.Y (e.g., "8.4")
        full_version = build['full-version']  # Format X.Y.Z (e.g., "8.4.13")
        os_name = build['os']
        checksum_key = f"{full_version}-{os_name}"

        if checksum_key not in checksums_map:
            raise ValueError(f"No checksum found for {checksum_key} - build incomplete")

        # Get release date from build matrix (no API calls needed)
        release_date = build.get('releaseDate', '')

        # Initialize version if not exists (using major.minor as key)
        if major_minor not in metadata['versions']:
            metadata['versions'][major_minor] = {
                'releaseDate': release_date,
                'builds': {}
            }
        else:
            metadata['versions'][major_minor]['releaseDate'] = release_date
            # Ensure builds is a dict
            if 'builds' not in metadata['versions'][major_minor]:
                metadata['versions'][major_minor]['builds'] = {}

        # Update build info by creating new dict
        version_data = metadata['versions'][major_minor]

        # Get existing builds or create empty dict
        existing_builds = version_data.get('builds', {})
        if not isinstance(existing_builds, dict):
            existing_builds = {}

        # Create new build entry - ALWAYS include filename
        checksum_data = checksums_map[checksum_key]
        new_build_entry = {
            'filename': checksum_data['filename'],
            'sha512': checksum_data['sha512'],
            'last_build': datetime.now(UTC).isoformat().replace('+00:00', 'Z')
        }

        # Update builds dict by reconstruction
        updated_builds = {**existing_builds, os_name: new_build_entry}
        version_data['builds'] = updated_builds

    save_json(metadata, 'metadata.json')
    print(f"Updated metadata for {len(metadata['versions'])} PHP versions")


def cleanup_eol(eol_versions_json):
    """Remove EOL versions from metadata."""
    eol_versions = json.loads(eol_versions_json)
    metadata = load_json('metadata.json')

    removed_count = 0
    for version in eol_versions:
        if version in metadata['versions']:
            del metadata['versions'][version]
            print(f"Removed {version} from metadata")
            removed_count += 1

    save_json(metadata, 'metadata.json')
    print(f"Removed {removed_count} EOL versions from metadata")


def main():
    parser = argparse.ArgumentParser(description='PHP build manager')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # check-versions subcommand
    subparsers.add_parser('check-versions', help='Check PHP versions and generate build matrix')

    # create-archive subcommand
    archive_parser = subparsers.add_parser('create-archive', help='Create tar.xz archive with CLI and FPM')
    archive_parser.add_argument('--php-version', required=True, help='PHP version')
    archive_parser.add_argument('--os', required=True, help='OS name')
    archive_parser.add_argument('--timestamp', required=True, help='Build timestamp (REQUIRED)')

    # update-metadata subcommand
    metadata_parser = subparsers.add_parser('update-metadata', help='Update metadata.json with build results')
    metadata_parser.add_argument('--build-matrix', required=True, help='JSON build matrix')
    metadata_parser.add_argument('--archive-checksums', required=True, help='Archive checksums (version,os,sha512 format)')

    # cleanup-eol subcommand
    cleanup_parser = subparsers.add_parser('cleanup-eol', help='Remove EOL versions from metadata')
    cleanup_parser.add_argument('--eol-versions', required=True, help='JSON array of EOL versions')

    args = parser.parse_args()

    if args.command == 'check-versions':
        check_versions()
    elif args.command == 'create-archive':
        create_archive(args.php_version, args.os, args.timestamp)  # STRICT: timestamp required
    elif args.command == 'update-metadata':
        update_metadata(args.build_matrix, args.archive_checksums)
    elif args.command == 'cleanup-eol':
        cleanup_eol(args.eol_versions)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
