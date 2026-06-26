"""Sync cert-manager TLS files into Stalwart and reload mail listeners."""

import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

USING = ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"]


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def require(name: str) -> str:
    if not (value := env(name)):
        sys.exit(f"missing required environment variable: {name}")
    return value


def basic_auth() -> str:
    creds = env("STALWART_RECOVERY_ADMIN")
    if not creds:
        creds = f"{require('RECOVERY_USERNAME')}:{require('RECOVERY_PASSWORD')}"
    return "Basic " + base64.b64encode(creds.encode()).decode()


class Jmap:
    def __init__(self, base_url: str, auth: str) -> None:
        self.base = base_url.rstrip("/")
        self.auth = auth

    def call(self, method: str, params: dict, req_id: str) -> dict:
        body = json.dumps(
            {"using": USING, "methodCalls": [[method, params, req_id]]}
        ).encode()
        request = urllib.request.Request(
            f"{self.base}/jmap",
            data=body,
            headers={"Authorization": self.auth, "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.loads(response.read())
        for entry in payload.get("methodResponses", []):
            if entry[0] == "error":
                raise RuntimeError(f"JMAP error: {entry[1]}")
            result = entry[1] if len(entry) > 1 else {}
            if isinstance(result, dict) and result.get("type") == "error":
                raise RuntimeError(f"JMAP method error: {result}")
            if len(entry) >= 3 and entry[2] == req_id:
                return result
        raise RuntimeError(f"missing JMAP response for {req_id}")


def cert_paths() -> tuple[str, str]:
    mount = require("TLS_MOUNT_PATH")
    cert = os.path.join(mount, require("TLS_CERT_FILE"))
    key = os.path.join(mount, require("TLS_KEY_FILE"))
    return cert, key


def file_hash(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def cert_object(cert_path: str, key_path: str) -> dict:
    return {
        "certificate": {"@type": "File", "filePath": cert_path},
        "privateKey": {"@type": "File", "filePath": key_path},
    }


def find_cert_id(jmap: Jmap, cert_path: str, key_path: str) -> str | None:
    ids = jmap.call("x:Certificate/query", {"filter": {}}, "qCert").get("ids", [])
    if not ids:
        return None
    listing = jmap.call("x:Certificate/get", {"ids": ids}, "gCert").get("list", {})
    items = listing.values() if isinstance(listing, dict) else listing
    for item in items:
        certificate = item.get("certificate", {})
        private_key = item.get("privateKey", {})
        if (
            certificate.get("filePath") == cert_path
            and private_key.get("filePath") == key_path
        ):
            return item["id"]
    return None


def ensure_cert(jmap: Jmap, cert_path: str, key_path: str) -> str:
    obj = cert_object(cert_path, key_path)
    if cert_id := find_cert_id(jmap, cert_path, key_path):
        jmap.call("x:Certificate/set", {"update": {cert_id: obj}}, "uCert")
        return cert_id
    created = jmap.call("x:Certificate/set", {"create": {"newCert": obj}}, "cCert")
    created_ids = created.get("created", {})
    if not created_ids:
        raise RuntimeError("Certificate/create returned no id")
    return next(iter(created_ids.values()))


def configure_system(jmap: Jmap, cert_id: str, hostname: str, domain: str) -> None:
    jmap.call(
        "x:SystemSettings/set",
        {
            "update": {
                "singleton": {
                    "defaultHostname": hostname,
                    "defaultCertificateId": cert_id,
                }
            }
        },
        "sSys",
    )
    domain_ids = jmap.call(
        "x:Domain/query", {"filter": {"name": domain}}, "qDom"
    ).get("ids", [])
    if domain_ids:
        jmap.call(
            "x:Domain/set",
            {
                "update": {
                    domain_ids[0]: {"certificateManagement": {"@type": "Manual"}}
                }
            },
            "sDom",
        )


def reload_tls(jmap: Jmap) -> None:
    jmap.call(
        "x:Action/set",
        {"create": {"reload": {"@type": "ReloadTlsCertificates"}}},
        "rTls",
    )


def sync_once(
    jmap: Jmap, hostname: str, domain: str, configured: bool, last_digest: str | None
) -> tuple[bool, str | None]:
    cert_path, key_path = cert_paths()
    for path in (cert_path, key_path):
        if not os.path.isfile(path):
            return configured, last_digest

    digest = file_hash(cert_path)
    if digest == last_digest:
        return configured, last_digest

    cert_id = ensure_cert(jmap, cert_path, key_path)
    if not configured:
        configure_system(jmap, cert_id, hostname, domain)
        configured = True
    reload_tls(jmap)
    print(f"TLS synced and reloaded (cert sha256={digest[:12]}...)")
    return configured, digest


def main() -> None:
    api = require("STALWART_API_URL")
    hostname = require("TLS_HOSTNAME")
    domain = require("TLS_DOMAIN")
    interval = max(30, int(env("TLS_RELOAD_INTERVAL_SECONDS", "300")))
    jmap = Jmap(api, basic_auth())
    configured = False
    last_digest: str | None = None

    while True:
        try:
            configured, last_digest = sync_once(
                jmap, hostname, domain, configured, last_digest
            )
        except (urllib.error.URLError, OSError, RuntimeError) as exc:
            print(f"tls-sync warning: {exc}", file=sys.stderr)
        time.sleep(interval)


if __name__ == "__main__":
    main()
