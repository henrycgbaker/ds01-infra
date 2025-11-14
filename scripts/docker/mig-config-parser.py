#!/usr/bin/env python3
"""Parse MIG configuration from resource-limits.yaml"""

import yaml
import sys
import json

def main():
    if len(sys.argv) < 2:
        print("Usage: mig-config-parser.py <config-file>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]

    try:
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)

        mig_config = config.get('gpu_allocation', {}).get('mig_gpus', {})

        # Convert to list format for easier bash processing
        result = []
        for gpu_id, settings in mig_config.items():
            result.append({
                'gpu_id': int(gpu_id),
                'enable': settings.get('enable', False),
                'profile': settings.get('profile'),
                'instances': settings.get('instances', 0)
            })

        print(json.dumps(result, indent=2))

    except Exception as e:
        print(f"Error parsing config: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
