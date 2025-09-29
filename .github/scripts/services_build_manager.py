#!/usr/bin/env python3
"""
Unified Services build manager for static-php-cli CI/CD.
Handles version checking, archive creation, metadata updates for MariaDB, MySQL, PostgreSQL, Redis.
"""

import json
import argparse
import hashlib
import tarfile
import subprocess
from datetime import datetime, UTC
from pathlib import Path

# Services configuration
SERVICES_CONFIG = {
    'mariadb': ['10', '11', '12'],
    'mysql': ['8', '9'],
    'postgresql': ['14', '15', '16', '17', '18'],
    'redis': ['7', '8']
}

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


def get_archive_filename(service, full_version, os_name, timestamp):
    """Generate filename with timestamp - ONLY way to generate filename"""
    return f"{service}-{full_version}-{timestamp}-{os_name}.tar.xz"


def calculate_sha512(filepath):
    """Calculate SHA512 hash of a file."""
    hash_sha512 = hashlib.sha512()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            hash_sha512.update(chunk)
    return hash_sha512.hexdigest()


def run_check_services_script():
    """Run check-services-versions.sh and parse output."""
    result = subprocess.run(['./check-services-versions.sh'],
                          capture_output=True, text=True, cwd='.')

    if result.returncode != 0:
        print(f"Error running check-services-versions.sh: {result.stderr}")
        return {}

    # Parse the output to extract versions
    services_versions = {}
    current_service = None

    for line in result.stdout.split('\n'):
        line = line.strip()
        if line.startswith('[') and line.endswith(']'):
            # Service header like [mariadb]
            current_service = line[1:-1]
            services_versions[current_service] = {}
        elif line.startswith('v') and current_service:
            # Version line like "  v11: 11.8.3 (latest stable)"
            parts = line.split(': ')
            if len(parts) >= 2:
                major = parts[0].replace('v', '').strip()
                version = parts[1].split(' ')[0].strip()
                services_versions[current_service][major] = version

    return services_versions


def check_versions():
    """Check services versions and generate build matrix."""
    # Load existing metadata
    metadata_file = 'metadata-services.json'
    if Path(metadata_file).exists():
        metadata = load_json(metadata_file)
    else:
        metadata = {'last_sync': '', 'mariadb': {}, 'mysql': {}, 'postgresql': {}, 'redis': {}}

    # Get current versions from endoflife.date
    print("Fetching latest service versions from endoflife.date...")
    current_versions = run_check_services_script()

    all_os = ['macos-aarch64']
    os_runners = {'macos-aarch64': 'macos-latest'}

    build_matrix = []

    # Process each service
    for service_name, major_versions in SERVICES_CONFIG.items():
        if service_name not in current_versions:
            print(f"Warning: No version data found for {service_name}")
            continue

        service_current = current_versions[service_name]
        service_metadata = metadata.get(service_name, {})

        for major_version in major_versions:
            if major_version not in service_current:
                print(f"Warning: No version found for {service_name} v{major_version}")
                continue

            current_full_version = service_current[major_version]

            # Check if we need to build this version
            need_build = False

            if major_version not in service_metadata:
                need_build = True
                print(f"New version detected: {service_name} {major_version} -> {current_full_version}")
            else:
                existing_version = service_metadata[major_version].get('version', '')
                if existing_version != current_full_version:
                    need_build = True
                    print(f"Updated version detected: {service_name} {major_version} -> {current_full_version} (was: {existing_version})")

            if need_build:
                for os_name in all_os:
                    build_matrix.append({
                        'service': service_name,
                        'major-version': major_version,
                        'full-version': current_full_version,
                        'os': os_name,
                        'runs-on': os_runners[os_name]
                    })

    # Output results
    matrix_json = json.dumps({'include': build_matrix})
    should_build = 'true' if build_matrix else 'false'

    print(f"Build matrix: {len(build_matrix)} items")

    with open('github_output.txt', 'w') as f:
        f.write(f'matrix={matrix_json}\n')
        f.write(f'should-build={should_build}\n')


def create_archive(service, full_version, os_name, timestamp):
    """Create tar.xz archive containing service binaries with timestamp."""
    # STRICT: timestamp is REQUIRED - no legacy support
    if not timestamp:
        raise ValueError("Timestamp is required - no legacy support")

    archive_name = get_archive_filename(service, full_version, os_name, timestamp)

    # Map service to their package directory structure
    service_package_dirs = {
        'mariadb': f'mariadb-package',
        'mysql': f'mysql-package',
        'postgresql': f'postgresql-package',
        'redis': f'redis-package'
    }

    package_dir = service_package_dirs.get(service)
    if not package_dir:
        raise ValueError(f"Unknown service: {service}")

    if not Path(package_dir).exists():
        raise ValueError(f"Package directory not found: {package_dir}")

    # Create tar.xz archive from the package directory
    with tarfile.open(archive_name, 'w:xz') as tar:
        tar.add(package_dir, arcname='.')

    # Calculate SHA512
    sha512_hash = calculate_sha512(archive_name)

    # Save hash to environment for workflow
    with open('archive_info.txt', 'w') as f:
        f.write(f'ARCHIVE_NAME={archive_name}\n')
        f.write(f'ARCHIVE_SHA512={sha512_hash}\n')

    print(f"Created {archive_name}")
    print(f"SHA512: {sha512_hash}")


def update_metadata(build_matrix_json, archive_checksums):
    """Update metadata-services.json with build results - STRICT format validation."""
    metadata_file = 'metadata-services.json'

    if Path(metadata_file).exists():
        metadata = load_json(metadata_file)
    else:
        metadata = {'last_sync': '', 'mariadb': {}, 'mysql': {}, 'postgresql': {}, 'redis': {}}

    build_matrix = json.loads(build_matrix_json)

    # Parse archive checksums (STRICT format: full_version,os,sha512,filename)
    checksums_map = {}
    for line in archive_checksums.strip().split('\n'):
        if line:
            parts = line.split(',')
            if len(parts) != 4:  # STRICT: Must have all 4 fields
                raise ValueError(f"Invalid checksum format - expected full_version,os,sha512,filename: {line}")

            full_version, os_name, sha512, filename = parts
            checksums_map[f"{full_version}-{os_name}"] = {
                'sha512': sha512,
                'filename': filename
            }

    # Update timestamp
    metadata['last_sync'] = datetime.now(UTC).isoformat().replace('+00:00', 'Z')

    # Process each build
    for build in build_matrix.get('include', []):
        service = build['service']
        major_version = build['major-version']
        full_version = build['full-version']
        os_name = build['os']
        checksum_key = f"{full_version}-{os_name}"

        if checksum_key not in checksums_map:
            raise ValueError(f"No checksum found for {checksum_key} - build incomplete")

        # Initialize service if not exists
        if service not in metadata:
            metadata[service] = {}

        # Get checksum data
        checksum_data = checksums_map[checksum_key]

        # Update service version info
        metadata[service][major_version] = {
            'version': full_version,
            'sha512': checksum_data['sha512'],
            'filename': checksum_data['filename'],
            'last_build': datetime.now(UTC).isoformat().replace('+00:00', 'Z')
        }

    save_json(metadata, metadata_file)
    print(f"Updated metadata for {len([build for build in build_matrix.get('include', [])])} service builds")


def cleanup_eol(eol_versions_json):
    """Remove EOL versions from metadata (placeholder - not implemented yet)."""
    eol_versions = json.loads(eol_versions_json)
    print(f"EOL cleanup requested for {len(eol_versions)} versions (not implemented yet)")


def main():
    parser = argparse.ArgumentParser(description='Services build manager')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # check-versions subcommand
    subparsers.add_parser('check-versions', help='Check service versions and generate build matrix')

    # create-archive subcommand
    archive_parser = subparsers.add_parser('create-archive', help='Create tar.xz archive for service')
    archive_parser.add_argument('--service', required=True, help='Service name (mariadb, mysql, postgresql, redis)')
    archive_parser.add_argument('--full-version', required=True, help='Full version (e.g., 11.8.3)')
    archive_parser.add_argument('--os', required=True, help='OS name')
    archive_parser.add_argument('--timestamp', required=True, help='Build timestamp (REQUIRED)')

    # update-metadata subcommand
    metadata_parser = subparsers.add_parser('update-metadata', help='Update metadata-services.json with build results')
    metadata_parser.add_argument('--build-matrix', required=True, help='JSON build matrix')
    metadata_parser.add_argument('--archive-checksums', required=True, help='Archive checksums (full_version,os,sha512,filename format)')

    # cleanup-eol subcommand
    cleanup_parser = subparsers.add_parser('cleanup-eol', help='Remove EOL versions from metadata')
    cleanup_parser.add_argument('--eol-versions', required=True, help='JSON array of EOL versions')

    args = parser.parse_args()

    if args.command == 'check-versions':
        check_versions()
    elif args.command == 'create-archive':
        create_archive(args.service, args.full_version, args.os, args.timestamp)
    elif args.command == 'update-metadata':
        update_metadata(args.build_matrix, args.archive_checksums)
    elif args.command == 'cleanup-eol':
        cleanup_eol(args.eol_versions)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()