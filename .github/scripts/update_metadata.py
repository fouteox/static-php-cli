#!/usr/bin/env python3
"""
Update metadata.json with build results from build matrix.
"""

import json
import argparse
from datetime import datetime, UTC

def main():
    parser = argparse.ArgumentParser(description='Update metadata.json with build results')
    parser.add_argument('--build-matrix', required=True, help='JSON build matrix from check-and-sync')
    parser.add_argument('--checksums-file', required=True, help='JSON file containing checksums from build jobs')
    args = parser.parse_args()

    # Load current metadata
    with open('metadata.json', 'r') as f:
        metadata = json.load(f)

    # Update last_sync timestamp
    metadata['last_sync'] = datetime.now(UTC).isoformat().replace('+00:00', 'Z')

    # Load checksums (required)
    checksums_map = {}
    with open(args.checksums_file, 'r') as f:
        raw_content = f.read()

        # Try to parse the JSON, handle double-encoding from GitHub Actions
        try:
            checksums_data = json.loads(raw_content)
        except json.JSONDecodeError:
            # If it fails, it might be double-encoded (a JSON string containing JSON)
            checksums_data = json.loads(json.loads(raw_content))

        # Handle different formats
        if isinstance(checksums_data, str):
            # It's still a string, parse again
            checksums_data = json.loads(checksums_data)

        # Handle both single checksum and array of checksums
        if isinstance(checksums_data, list):
            for checksum in checksums_data:
                if checksum:  # Skip null/empty entries
                    # Handle case where each item might be a string
                    if isinstance(checksum, str):
                        checksum = json.loads(checksum)
                    key = f"{checksum['php-version']}-{checksum['os']}"
                    checksums_map[key] = checksum
        elif checksums_data:  # Single checksum object
            key = f"{checksums_data['php-version']}-{checksums_data['os']}"
            checksums_map[key] = checksums_data

    # Update versions with API data based on build matrix
    build_matrix = json.loads(args.build_matrix or '{"include": []}')

    for build in build_matrix.get('include', []):
        version_name = build['php-version']
        os = build['os']

        # Initialize version in metadata if not exists
        if version_name not in metadata['versions']:
            metadata['versions'][version_name] = {
                'versionId': build['versionId'],
                'releaseDate': build['releaseDate'],
                'activeSupportEndDate': build['activeSupportEndDate'],
                'eolDate': build['eolDate'],
                'isEOLVersion': build['isEOLVersion'],
                'isSecureVersion': build['isSecureVersion'],
                'isLatestVersion': build['isLatestVersion'],
                'isFutureVersion': build['isFutureVersion'],
                'isNextVersion': build['isNextVersion'],
                'builds': {}
            }
        else:
            # Update version info from API
            metadata['versions'][version_name].update({
                'versionId': build['versionId'],
                'releaseDate': build['releaseDate'],
                'activeSupportEndDate': build['activeSupportEndDate'],
                'eolDate': build['eolDate'],
                'isEOLVersion': build['isEOLVersion'],
                'isSecureVersion': build['isSecureVersion'],
                'isLatestVersion': build['isLatestVersion'],
                'isFutureVersion': build['isFutureVersion'],
                'isNextVersion': build['isNextVersion']
            })

        # Update build info for this OS
        checksum_key = f"{version_name}-{os}"
        checksum_data = checksums_map[checksum_key]

        metadata['versions'][version_name]['builds'][os] = {
            'last_build': datetime.now(UTC).isoformat().replace('+00:00', 'Z'),
            'cli_sha512': checksum_data['cli_sha512'],
            'fpm_sha512': checksum_data['fpm_sha512']
        }

    # Save updated metadata
    with open('metadata.json', 'w') as f:
        json.dump(metadata, f, indent=2)

    print(f"Updated metadata for {len(metadata['versions'])} PHP versions")

if __name__ == '__main__':
    main()