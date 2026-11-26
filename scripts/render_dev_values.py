#!/usr/bin/env python3
"""Render current non-secret dev Helm values from Terraform outputs.

The checked-in values file supplies immutable image digests and stable app
settings. Recreated Azure IDs/endpoints are injected from non-secret
Terragrunt outputs and the authenticated Azure account; generated YAML goes to
stdout so the caller can keep it in a protected temporary path.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


UPDATES = {
    "workloadClientId": "WORKLOAD_CLIENT_ID",
    "tenantId": "AZURE_TENANT_ID",
    "keyVaultName": "APP_KEY_VAULT_NAME",
    "gatewayPublicIpName": "GATEWAY_PUBLIC_IP_NAME",
    "gatewayPublicIpResourceGroup": "DEV_RESOURCE_GROUP",
    "cosmosEndpoint": "COSMOS_ENDPOINT",
    "blobEndpoint": "BLOB_ENDPOINT",
    "webPubSubEndpoint": "WEB_PUBSUB_ENDPOINT",
    "acsEndpoint": "ACS_ENDPOINT",
    "acsSenderAddress": "ACS_SENDER_ADDRESS",
}


def main() -> int:
    source = Path(__file__).resolve().parent.parent / "deploy/environments/dev/chat-values.yaml"
    text = source.read_text(encoding="utf-8")

    for key, env_name in UPDATES.items():
        value = os.environ.get(env_name, "").strip()
        if not value or "\n" in value or "\r" in value:
            raise ValueError(f"Missing or invalid non-secret input: {env_name}")
        pattern = re.compile(rf"^(\s*{re.escape(key)}:\s*).*$", re.MULTILINE)
        text, count = pattern.subn(lambda match: match.group(1) + json.dumps(value), text)
        if count != 1:
            raise ValueError(f"Expected exactly one {key} value in the dev Helm values")

    for image_key in ("image", "migrationImage"):
        match = re.search(rf"^{image_key}:\s*['\"]([^'\"]+)['\"]\s*$", text, re.MULTILINE)
        if not match or "@sha256:" not in match.group(1):
            raise ValueError(f"{image_key} must be pinned by immutable digest")

    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
