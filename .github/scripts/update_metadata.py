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
    args = parser.parse_args()

    # Load current metadata
    with open('metadata.json', 'r') as f:
        metadata = json.load(f)

    # Update last_sync timestamp
    metadata['last_sync'] = datetime.now(UTC).isoformat().replace('+00:00', 'Z')

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
        metadata['versions'][version_name]['builds'][os] = {
            'last_build': datetime.now(UTC).isoformat().replace('+00:00', 'Z'),
            'sha256': 'placeholder-sha256'  # TODO: Calculate actual SHA256
        }

    # Save updated metadata
    with open('metadata.json', 'w') as f:
        json.dump(metadata, f, indent=2)

    print(f"Updated metadata for {len(metadata['versions'])} PHP versions")

if __name__ == '__main__':
    main()