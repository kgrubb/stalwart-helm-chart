"""Idempotent Stalwart OIDC bootstrap via JMAP."""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

USING = ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"]
OIDC_FIELDS = (
    "description",
    "issuerUrl",
    "requireAudience",
    "requireScopes",
    "claimUsername",
    "usernameDomain",
    "claimName",
    "claimGroups",
)
EMPTY = (None, "", [])


def require(name: str) -> str:
    if not (value := os.environ.get(name, "").strip()):
        sys.exit(f"missing required environment variable: {name}")
    return value


def basic_auth() -> str:
    creds = os.environ.get("STALWART_RECOVERY_ADMIN", "").strip()
    if not creds:
        creds = f"{require('RECOVERY_USERNAME')}:{require('RECOVERY_PASSWORD')}"
    return "Basic " + base64.b64encode(creds.encode()).decode()


class Jmap:
    def __init__(self, base_url: str, auth: str) -> None:
        self.base = base_url.rstrip("/")
        self.auth = auth

    def wait_ready(self, timeout: int = 300) -> None:
        url = f"{self.base}/healthz/ready"
        deadline, delay = time.time() + timeout, 2
        while time.time() < deadline:
            try:
                urllib.request.urlopen(
                    urllib.request.Request(url, headers={"Authorization": self.auth}),
                    timeout=10,
                )
                return
            except (urllib.error.URLError, OSError):
                time.sleep(delay)
                delay = min(delay * 2, 30)
        raise TimeoutError(f"timed out waiting for {url}")

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

    def first(self, method: str, filt: dict, req_id: str) -> str | None:
        ids = self.call(method, {"filter": filt}, req_id).get("ids", [])
        return ids[0] if ids else None

    def create(self, method: str, obj: dict, req_id: str) -> str:
        created = self.call(method, {"create": {req_id: obj}}, req_id).get(
            "created", {}
        )
        if not created:
            raise RuntimeError(f"{method} create failed")
        return next(iter(created.values()))

    def ensure(self, query_m: str, set_m: str, filt: dict, obj: dict, tag: str) -> str:
        if found := self.first(query_m, filt, f"q{tag}"):
            return found
        return self.create(set_m, obj, f"c{tag}")


def oidc_directory(cfg: dict) -> dict:
    directory = {
        "@type": "Oidc",
        **{k: cfg[k] for k in OIDC_FIELDS if cfg.get(k) not in EMPTY},
    }
    if not directory.get("issuerUrl"):
        raise RuntimeError("issuerUrl is required in BOOTSTRAP_OIDC")
    directory.setdefault("description", "External OIDC")
    return directory


def reconcile(jmap: Jmap, domain: str, accounts: list, oidc_cfg: dict) -> None:
    domain_id = jmap.ensure(
        "x:Domain/query",
        "x:Domain/set",
        {"name": domain},
        {"name": domain},
        "Domain",
    )

    for account in accounts:
        if not (name := account.get("name")):
            continue
        user = {"@type": "User", "name": name, "domainId": domain_id}
        if roles := account.get("roles"):
            user["roles"] = roles
        jmap.ensure(
            "x:Account/query",
            "x:Account/set",
            {"name": name, "domainId": domain_id},
            user,
            f"Acct_{name}",
        )

    directory = oidc_directory(oidc_cfg)
    issuer = directory["issuerUrl"]
    dir_ids = jmap.call("x:Directory/query", {"filter": {}}, "qDir").get("ids", [])
    listings = (
        jmap.call("x:Directory/get", {"ids": dir_ids}, "gDir").get("list", {})
        if dir_ids
        else {}
    )
    dir_id = next(
        (
            dir_id
            for dir_id, entry in listings.items()
            if entry.get("@type") == "Oidc" and entry.get("issuerUrl") == issuer
        ),
        None,
    )
    if dir_id:
        jmap.call("x:Directory/set", {"update": {dir_id: directory}}, "uDir")
    else:
        dir_id = jmap.create("x:Directory/set", directory, "cDir")

    auth = jmap.call("x:Authentication/get", {"ids": ["singleton"]}, "gAuth")
    if auth.get("list", {}).get("singleton", {}).get("directoryId") != dir_id:
        jmap.call(
            "x:Authentication/set",
            {"update": {"singleton": {"directoryId": dir_id}}},
            "sAuth",
        )


def main() -> None:
    jmap = Jmap(require("STALWART_API_URL"), basic_auth())
    jmap.wait_ready()
    reconcile(
        jmap,
        require("BOOTSTRAP_DOMAIN"),
        json.loads(require("BOOTSTRAP_ACCOUNTS")),
        json.loads(require("BOOTSTRAP_OIDC")),
    )


if __name__ == "__main__":
    main()
