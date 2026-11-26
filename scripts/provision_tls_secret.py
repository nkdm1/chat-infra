"""Create namespace/chat-tls from operator-vault Cloudflare TLS secrets.

Reads certificate and key through the VM managed identity, validates their
match, validity and hostname, then sends the Kubernetes Secret JSON over stdin
to kubectl. Values are never written to a file or printed.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

from cryptography import x509
from cryptography.hazmat.primitives import serialization

from keyvault_mi import get_secret

HOSTNAME = "chat.nkdm.io"
NAMESPACE = "chat"
SECRET_NAME = "chat-tls"


class ProvisionError(RuntimeError):
    """Safe-to-log TLS provisioning error."""


def main() -> int:
    vault_name = os.environ.get("OPERATOR_KEY_VAULT_NAME", "").strip()
    kubeconfig = os.environ.get("KUBECONFIG", "").strip()
    if not vault_name or not kubeconfig or not os.path.isfile(kubeconfig):
        raise ProvisionError("Missing operator vault or temporary kubeconfig")

    cert_pem = get_secret(vault_name, "cloudflare-origin-cert").encode("utf-8")
    key_pem = get_secret(vault_name, "cloudflare-origin-key").encode("utf-8")

    try:
        cert = x509.load_pem_x509_certificate(cert_pem)
        private_key = serialization.load_pem_private_key(key_pem, password=None)
        san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
        hostnames = set(san.get_values_for_type(x509.DNSName))
        cert_public = cert.public_key().public_bytes(
            serialization.Encoding.DER,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        key_public = private_key.public_key().public_bytes(
            serialization.Encoding.DER,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    except Exception:
        raise ProvisionError("Cloudflare TLS certificate or key is not valid PEM") from None

    host_covered = HOSTNAME in hostnames or any(
        pattern.startswith("*.")
        and HOSTNAME.endswith(pattern[1:])
        and HOSTNAME.count(".") == pattern.count(".")
        for pattern in hostnames
    )
    if not host_covered:
        raise ProvisionError("Origin certificate does not cover the configured hostname")
    if cert_public != key_public:
        raise ProvisionError("Origin certificate and private key do not match")
    now = datetime.now(timezone.utc)
    if cert.not_valid_before.replace(tzinfo=timezone.utc) > now:
        raise ProvisionError("Origin certificate is not valid yet")
    if cert.not_valid_after.replace(tzinfo=timezone.utc) <= now:
        raise ProvisionError("Origin certificate has expired")

    secret_object = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": SECRET_NAME, "namespace": NAMESPACE},
        "type": "kubernetes.io/tls",
        "data": {
            "tls.crt": base64.b64encode(cert_pem).decode("ascii"),
            "tls.key": base64.b64encode(key_pem).decode("ascii"),
        },
    }
    try:
        result = subprocess.run(
            ["kubectl", "apply", "--filename", "-"],
            input=json.dumps(secret_object),
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={**os.environ, "KUBECONFIG": kubeconfig},
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        raise ProvisionError("Could not apply the TLS Secret to Kubernetes") from None
    if result.returncode != 0:
        raise ProvisionError("Could not apply the TLS Secret; check Kubernetes access")

    print("chat-tls: applied")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProvisionError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print("TLS Secret provisioning failed; inspect safe metadata and access", file=sys.stderr)
        raise SystemExit(1)
