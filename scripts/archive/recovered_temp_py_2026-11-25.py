import json
import secrets
import sys
from urllib.parse import quote
from urllib.request import Request, ProxyHandler, build_opener
from urllib.error import HTTPError

opener = build_opener(ProxyHandler({}))
vault = "https://chat-dev-cf816eae-kv.vault.azure.net"
arm = "https://management.azure.com"


def token(resource):
    url = (
        "http://169.254.169.254/metadata/identity/oauth2/token"
        "?api-version=2018-02-01&resource=" + quote(resource, safe="")
    )
    with opener.open(Request(url, headers={"Metadata": "true"})) as response:
        return json.load(response)["access_token"]


try:
    vault_token = token("https://vault.azure.net")
    headers = {"Authorization": "Bearer " + vault_token}
    listing = vault + "/secrets?api-version=7.4"
    existing = set()

    while listing:
        with opener.open(Request(listing, headers=headers)) as response:
            page = json.load(response)
        existing.update(item["id"].rsplit("/", 1)[-1].lower() for item in page["value"])
        listing = page.get("nextLink")

    if existing.intersection({"redis-url", "better-auth-secret"}):
        sys.exit("A target secret already exists; nothing overwritten.")

    arm_token = token(arm + "/")
    redis_path = (
        "/subscriptions/cf816eae-f4d9-4db4-bfa6-bda71e2cbf68"
        "/resourceGroups/chat-dev-rg/providers/Microsoft.Cache"
        "/redisEnterprise/chat-dev-cf816eae-redis/databases/default"
        "/listKeys?api-version=2025-07-01"
    )
    request = Request(
        arm + redis_path,
        data=b"{}",
        headers={
            "Authorization": "Bearer " + arm_token,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with opener.open(request) as response:
        redis_key = json.load(response)["primaryKey"]

    redis_url = (
        "rediss://default:"
        + quote(redis_key, safe="")
        + "@chat-dev-cf816eae-redis.belgiumcentral.redis.azure.net:10000"
    )
    auth_secret = secrets.token_urlsafe(32)

    for name, value in (
        ("redis-url", redis_url),
        ("better-auth-secret", auth_secret),
    ):
        request = Request(
            vault + "/secrets/" + name + "?api-version=7.4",
            data=json.dumps({"value": value}).encode(),
            headers={**headers, "Content-Type": "application/json"},
            method="PUT",
        )
        with opener.open(request) as response:
            print(name, "stored; HTTP", response.status)
except HTTPError as error:
    sys.exit("Azure request failed with HTTP " + str(error.code))
