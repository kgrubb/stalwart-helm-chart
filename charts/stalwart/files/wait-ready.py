"""Wait until Stalwart /healthz/ready responds."""

import base64
import os
import sys
import time
import urllib.error
import urllib.request

base = os.environ["STALWART_URL"].rstrip("/")
user, password = os.environ.get("STALWART_USER", ""), os.environ.get("STALWART_PASSWORD", "")
headers = {}
if user or password:
    headers["Authorization"] = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()
url = f"{base}/healthz/ready"
deadline, delay = time.time() + 300, 2
while time.time() < deadline:
    try:
        urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=10)
        sys.exit(0)
    except (urllib.error.URLError, OSError):
        time.sleep(delay)
        delay = min(delay * 2, 30)
sys.exit(f"timed out waiting for {url}")
