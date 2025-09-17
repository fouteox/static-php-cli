#!/usr/bin/env python3
"""
Remove EOL versions from metadata.json.
"""

import json
import argparse

def main():
    parser = argparse.ArgumentParser(description='Remove EOL versions from metadata.json')
    parser.add_argument('--eol-versions', required=True, help='JSON array of EOL versions to remove')
    args = parser.parse_args()

    # Load metadata
    with open('metadata.json', 'r') as f:
        metadata = json.load(f)

    # Remove EOL versions
    eol_versions = json.loads(args.eol_versions)
    removed_count = 0

    for version in eol_versions:
        if version in metadata['versions']:
            del metadata['versions'][version]
            print(f"Removed {version} from metadata")
            removed_count += 1

    # Save updated metadata
    with open('metadata.json', 'w') as f:
        json.dump(metadata, f, indent=2)

    print(f"Removed {removed_count} EOL versions from metadata")

if __name__ == '__main__':
    main()