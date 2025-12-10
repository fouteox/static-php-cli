#!/usr/bin/env python3
"""
Unified PHP build manager for static-php-cli CI/CD.
Handles version checking, archive creation, metadata updates, and EOL cleanup.
"""

import json
import argparse
import tarfile
import subprocess
from pathlib import Path

METADATA_FILE = 'metadata-php.json'

def load_json(filepath):
    """Load JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)


def save_json(data, filepath):
    """Save JSON file with pretty formatting."""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)


def get_archive_filename(full_version):
    """Generate filename without timestamp."""
    return f"php-{full_version}.tar.gz"


def fetch_version_details(version):
    """Fetch detailed version info from PHP.net API."""
    url = f"https://www.php.net/releases/index.php?json&version={version}"
    result = subprocess.run(['curl', '-fsSL', url], capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    return None


def check_versions():
    """Check PHP versions and generate build matrix."""
    metadata = load_json(METADATA_FILE)
    api_data = load_json('api_response.json')

    all_os = ['macos-aarch64']
    os_runners = {'macos-aarch64': 'macos-latest'}

    build_matrix = []
    eol_versions = []

    supported_versions = []
    if "8" in api_data:
        supported_versions = api_data["8"].get("supported_versions", [])

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

    for full_version, version_details in version_details_cache.items():
        version_parts = full_version.split('.')
        if len(version_parts) >= 2:
            major_minor = f"{version_parts[0]}.{version_parts[1]}"
        else:
            major_minor = full_version

        need_build = False

        if major_minor not in metadata:
            need_build = True
            print(f"New version detected: {full_version} (metadata key: {major_minor})")
        else:
            api_release = version_details.get('date', '')
            metadata_release = metadata[major_minor].get('releaseDate', '')
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

    for version_name in metadata:
        version_parts = version_name.split('.')
        if len(version_parts) >= 2:
            major_minor = f"{version_parts[0]}.{version_parts[1]}"
            if major_minor not in supported_versions:
                eol_versions.append(version_name)
                print(f"EOL version detected: {version_name}")
    matrix_json = json.dumps({'include': build_matrix})
    eol_json = json.dumps(eol_versions)
    should_build = 'true' if build_matrix else 'false'

    print(f"Build matrix: {len(build_matrix)} items")
    print(f"EOL versions: {len(eol_versions)} items")

    with open('github_output.txt', 'w') as f:
        f.write(f'matrix={matrix_json}\n')
        f.write(f'eol={eol_json}\n')
        f.write(f'should-build={should_build}\n')


def create_archive(php_version):
    """Create tar.gz archive containing CLI, FPM binaries and shared extensions."""
    archive_name = get_archive_filename(php_version)

    with tarfile.open(archive_name, 'w:gz') as tar:
        tar.add('buildroot/bin/php', arcname='php-cli')
        tar.add('buildroot/bin/php-fpm', arcname='php-fpm')

        # Include shared extensions (.so files) if they exist
        buildroot = Path('buildroot')
        for so_file in buildroot.rglob('*.so'):
            arcname = f'extensions/{so_file.name}'
            tar.add(str(so_file), arcname=arcname)
            print(f"Included {so_file.name} in archive")

    with open('archive_info.txt', 'w') as f:
        f.write(f'ARCHIVE_NAME={archive_name}\n')

    print(f"Created {archive_name}")


def update_metadata(build_matrix_json, archive_checksums):
    """Update metadata-php.json with build results."""
    metadata = load_json(METADATA_FILE) if Path(METADATA_FILE).exists() else {}
    build_matrix = json.loads(build_matrix_json)

    checksums_map = {}
    for line in archive_checksums.strip().split('\n'):
        if line:
            parts = line.split(',')
            if len(parts) != 3:
                raise ValueError(f"Invalid checksum format - expected version,sha256,filename: {line}")

            version, sha256, filename = parts
            checksums_map[version] = {
                'sha256': sha256,
                'filename': filename
            }

    for build in build_matrix.get('include', []):
        major_minor = build['php-version']
        full_version = build['full-version']

        if full_version not in checksums_map:
            raise ValueError(f"No checksum found for {full_version}")

        release_date = build.get('releaseDate', '')
        checksum_data = checksums_map[full_version]

        metadata[major_minor] = {
            'latest': full_version,
            'releaseDate': release_date,
            'filename': checksum_data['filename'],
            'sha256': checksum_data['sha256']
        }

        print(f"Updated {major_minor} -> {full_version}")

    save_json(metadata, METADATA_FILE)
    print(f"Updated metadata for {len(metadata)} PHP versions")


def cleanup_eol(eol_versions_json):
    """Remove EOL versions from metadata."""
    eol_versions = json.loads(eol_versions_json)
    metadata = load_json(METADATA_FILE)

    removed_count = 0
    for version in eol_versions:
        if version in metadata:
            del metadata[version]
            print(f"Removed {version} from metadata")
            removed_count += 1

    save_json(metadata, METADATA_FILE)
    print(f"Removed {removed_count} EOL versions from metadata")


def main():
    parser = argparse.ArgumentParser(description='PHP build manager')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    subparsers.add_parser('check-versions', help='Check PHP versions and generate build matrix')

    archive_parser = subparsers.add_parser('create-archive', help='Create tar.gz archive with CLI and FPM')
    archive_parser.add_argument('--php-version', required=True, help='PHP version')

    metadata_parser = subparsers.add_parser('update-metadata', help='Update metadata-php.json with build results')
    metadata_parser.add_argument('--build-matrix', required=True, help='JSON build matrix')
    metadata_parser.add_argument('--archive-checksums', required=True, help='Archive checksums (version,sha256,filename format)')

    cleanup_parser = subparsers.add_parser('cleanup-eol', help='Remove EOL versions from metadata')
    cleanup_parser.add_argument('--eol-versions', required=True, help='JSON array of EOL versions')

    args = parser.parse_args()

    if args.command == 'check-versions':
        check_versions()
    elif args.command == 'create-archive':
        create_archive(args.php_version)
    elif args.command == 'update-metadata':
        update_metadata(args.build_matrix, args.archive_checksums)
    elif args.command == 'cleanup-eol':
        cleanup_eol(args.eol_versions)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
