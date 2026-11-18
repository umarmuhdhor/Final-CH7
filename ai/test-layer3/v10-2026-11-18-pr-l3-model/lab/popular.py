"""Popular-sites rule: a host under a Tranco top-N domain is treated like an official host (tier safe, as Shoo's isOfficialHost does).

Why: a real brand login page (amazon.co.uk sign-in) looks just like a phishing page to a text model. Shoo's own POPULAR list has
only 122 domains, so most real sites are not covered.
The list is a traffic ranking (Tranco), never built from labeled pages, so it cannot leak test labels.

Same exclusions as Shoo's isOfficialHost (ai/src/layer3/official.js): a platform where anyone can publish a page never counts
as popular, even when its domain is in the ranking:
  - SHARED_HOSTS  (ai/src/blocklist/allowlist.js): S3, CDNs, site builders, github.io, blogspot.com ...
  - USER_CONTENT  (official.js): docs.google.com, sites.google.com, forms.office.com, express.adobe.com ...
  - every subdomain of medium.com except www
Both lists are read from Shoo's code with node (read only) and cached in out/popular-exclusions.json.

Usage in code:  P = Popular(10000); P.is_popular("www.amazon.co.uk")
"""
import csv
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOP = Path.home() / "Documents/dataset/data/lists/top-1m.csv"  # rank,domain; Tranco, 1,000,000 rows
SHOO_AI = Path.home() / "Documents/Swift/Final-CH/Final-CH7/ai"
CACHE = HERE / "out" / "popular-exclusions.json"
USER_SUBDOMAINS = ["medium.com"]  # official.js: every subdomain except www is a user's own page


def exclusions():
    if CACHE.exists():
        return json.load(open(CACHE, encoding="utf-8"))
    js = (
        f"const {{ SHARED_HOSTS }} = await import('file://{SHOO_AI}/src/blocklist/allowlist.js');"
        f"const {{ USER_CONTENT }} = await import('file://{SHOO_AI}/src/layer3/official.js');"
        "console.log(JSON.stringify({ shared: [...SHARED_HOSTS], user_content: USER_CONTENT }));"
    )
    out = subprocess.run(["node", "--input-type=module", "-e", js], capture_output=True, text=True, check=True).stdout
    data = json.loads(out)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    json.dump(data, open(CACHE, "w", encoding="utf-8"), indent=1)
    return data


class Popular:
    def __init__(self, n):
        ex = exclusions()
        self.blocked = list(ex["shared"]) + list(ex["user_content"])
        self.top = set()
        with open(TOP, encoding="utf-8") as f:
            for i, row in enumerate(csv.reader(f)):
                if i >= n:
                    break
                self.top.add(row[1].strip().lower())

    def is_popular(self, host):
        host = (host or "").lower().rstrip(".")
        if not host or len(host) > 253:
            return False
        for s in self.blocked:
            if host == s or host.endswith("." + s):
                return False
        for apex in USER_SUBDOMAINS:
            if host.endswith("." + apex) and host != "www." + apex:
                return False
        labels = host.split(".")
        return any(".".join(labels[i:]) in self.top for i in range(len(labels) - 1))
