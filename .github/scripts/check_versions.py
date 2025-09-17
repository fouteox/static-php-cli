#!/usr/bin/env python3
"""
Check PHP versions from PHP.watch API against current metadata and generate build matrix.
"""

import json

def main():
    # Load data
    with open('metadata.json', 'r') as f:
        metadata = json.load(f)

    with open('api_response.json', 'r') as f:
        api_data = json.load(f)

    # Define all supported OS
    all_os = ['macos-aarch64']

    build_matrix = []
    eol_versions = []

    # Define OS to runner mapping
    os_runners = {
        'macos-aarch64': 'macos-latest'
    }

    # Check each non-EOL version from API
    for version_id, version_data in api_data['data'].items():
        version_name = version_data['name']

        if not version_data['isEOLVersion'] and not version_data['isFutureVersion']:
            # Check if version needs building/rebuilding
            need_build = False

            if version_name not in metadata['versions']:
                # New version - build all OS
                need_build = True
                print(f"New version detected: {version_name}")
            else:
                # Check if releaseDate is newer
                api_release = version_data['releaseDate']
                metadata_release = metadata['versions'][version_name].get('releaseDate', '')
                if api_release > metadata_release:
                    need_build = True
                    print(f"Updated version detected: {version_name} ({api_release} > {metadata_release})")

            if need_build:
                for os in all_os:
                    build_matrix.append({
                        'php-version': version_name,
                        'os': os,
                        'runs-on': os_runners[os],
                        'versionId': version_data['versionId'],
                        'releaseDate': version_data['releaseDate'],
                        'activeSupportEndDate': version_data['activeSupportEndDate'],
                        'eolDate': version_data['eolDate'],
                        'isEOLVersion': version_data['isEOLVersion'],
                        'isSecureVersion': version_data['isSecureVersion'],
                        'isLatestVersion': version_data['isLatestVersion'],
                        'isFutureVersion': version_data['isFutureVersion'],
                        'isNextVersion': version_data['isNextVersion']
                    })

    # Check for versions that became EOL
    for version_name in metadata['versions']:
        if version_name in [v['name'] for v in api_data['data'].values()]:
            version_data = next(v for v in api_data['data'].values() if v['name'] == version_name)
            if version_data['isEOLVersion']:
                eol_versions.append(version_name)
                print(f"EOL version detected: {version_name}")

    # Output results
    matrix_json = json.dumps({'include': build_matrix})
    eol_json = json.dumps(eol_versions)
    should_build = 'true' if build_matrix else 'false'

    print(f"Build matrix: {len(build_matrix)} items")
    print(f"EOL versions: {len(eol_versions)} items")

    # Write outputs to GitHub Actions
    with open('github_output.txt', 'w') as f:
        f.write(f'matrix={matrix_json}\n')
        f.write(f'eol={eol_json}\n')
        f.write(f'should-build={should_build}\n')

if __name__ == '__main__':
    main()