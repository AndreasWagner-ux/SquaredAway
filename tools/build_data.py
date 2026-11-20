#!/usr/bin/env python3
"""Build ItemData.lua for Squared Away from the ForeverDB.net API.

Data from ForeverDB.net (https://foreverdb.net).

The API key is NEVER stored in the addon or in git. Put it in
tools/foreverdb_key.txt (ignored by git) or in the environment variable
FOREVERDB_KEY, then run:

    python3 tools/build_data.py

ItemData.lua gets, per item: what it is (food, armor kit, agility elixir or
scroll, stat scroll), required level, and the numbers the addon needs (food
score, armor, minimum item level, stat amount, buff spell ID). Names, icons
and tooltips come from the game itself, in the client language. Item details
are cached in tools/cache/ (ignored by git), so later runs are quick.
"""

import json
import os
import re
import sys
import time
import urllib.request

API = "https://foreverdb.net/api/v1/"
USER_AGENT = "SquaredAway-build/1.0 (github.com/AndreasWagner-ux/SquaredAway)"
PAUSE = 2.2  # seconds between requests: free tier allows 30 per minute

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "ItemData.lua")



def load_key():
    key = os.environ.get("FOREVERDB_KEY")
    path = os.path.join(HERE, "foreverdb_key.txt")
    if not key and os.path.exists(path):
        key = open(path, encoding="utf-8").read().strip()
    if not key:
        sys.exit("No API key: put it in tools/foreverdb_key.txt or FOREVERDB_KEY.")
    return key


KEY = load_key()
_last = [0.0]


def get(path):
    wait = PAUSE - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    req = urllib.request.Request(API + path, headers={
        "X-API-Key": KEY, "User-Agent": USER_AGENT, "Accept": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                _last[0] = time.time()
                return json.load(r)
        except urllib.error.HTTPError as e:
            _last[0] = time.time()
            if e.code == 429 and attempt < 2:
                time.sleep(30)
                continue
            raise


def clean(text):
    # drop invisible characters, keep the words
    return re.sub(r"[​-‏⁠-⁤﻿]", "", text or "").lower()


CACHE = os.path.join(HERE, "cache")  # ignored by git


def details(item_id):
    """Item details, cached on disk so a second run is quick."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "%d.json" % item_id)
    if os.path.exists(path):
        return json.load(open(path, encoding="utf-8"))
    d = get("items/%d" % item_id)["data"]
    json.dump(d, open(path, "w", encoding="utf-8"))
    return d


def effects(item_id):
    d = details(item_id)
    return [(clean(e.get("text")), e.get("spellId")) for e in d.get("effects") or []
            if e.get("trigger") == "use"]


def num(pattern, text):
    m = re.search(pattern, text)
    return int(m.group(1)) if m else None


# Food score for a hunter, same weights as the addon used to read from tooltips.
FOOD_SCORES = ((3, ("agility", "attack power")), (2, ("stamina", "critical")),
               (1, ("intellect", "armor")))


def food_score(buff):
    score = 0
    for value, words in FOOD_SCORES:
        if any(w in buff for w in words):
            score = max(score, value)
    return score


def main():
    # 1. every consumable, page by page
    items, offset, build = [], 0, None
    while True:
        page = get("items?class=0&limit=100&offset=%d" % offset)
        build = page["meta"].get("build", build)
        items += page["data"]
        print("listed", len(items), "of", page["meta"]["total"])
        if not page["meta"].get("next"):
            break
        offset += 100
    items = [i for i in items if not i.get("speculation")]

    out = {}  # id -> (item, fields)

    for i in items:
        sub, name, iid = i["subclass"], i["name"], i["id"]
        base = {"lvl": i.get("requiredLevel") or 0, "ilvl": i.get("itemLevel") or 0}

        # stat and agility scrolls
        if sub == "Scrolls":
            m = re.match(r"Scroll of (Agility|Stamina|Strength|Protection|Intellect)( [IVX]+)?$", name)
            if not m:
                continue
            text, spell = (effects(iid) or [("", None)])[0]
            f = dict(base, amount=num(r"by (\d+)", text), spell=spell)
            if m.group(1) == "Agility":
                f.update(kind="boost", sub="scroll")
            else:
                f.update(kind="scroll", stat={"Protection": "armor"}.get(m.group(1), m.group(1).lower()))
            out[iid] = (i, f)

        # armor kits
        elif sub == "Permanent" and "Armor Kit" in name:
            text = " ".join(t for t, _ in effects(iid))
            if "chest, legs, hands" not in text:
                continue
            f = dict(base, kind="kit",
                     armor=num(r"armor value by (\d+)", text) or 0,
                     minIlvl=num(r"items level (\d+) and above", text) or 0,
                     caster=any(w in text for w in ("spell power", "spell damage", "healing")))
            out[iid] = (i, f)

        # agility elixirs
        elif sub == "Elixirs":
            eff = effects(iid)
            text = " ".join(t for t, _ in eff)
            if "agility" not in text:
                continue
            amount = (num(r"agility(?: and \w+)? by (\d+)", text) or num(r"(\d+) agility", text)
                      or num(r"by (\d+)", text))
            out[iid] = (i, dict(base, kind="boost", sub="elixir", amount=amount, spell=eff[0][1] if eff else None))

        # Well Fed food with a stat a hunter can use
        elif sub == "Food & Drink":
            text = " ".join(t for t, _ in effects(iid))
            if "well fed" not in text:
                continue
            score = food_score(text.split("well fed", 1)[1])
            if score > 0:
                out[iid] = (i, dict(base, kind="food", score=score))

    # 6. arrows and bullets (class 6 = Projectile); damage comes from the game
    offset = 0
    while True:
        page = get("items?class=6&limit=100&offset=%d" % offset)
        for i in page["data"]:
            if i.get("speculation") or i["name"].startswith("Depricated"):
                continue
            sub = {"Arrow": "arrow", "Bullet": "bullet"}.get(i["subclass"])
            if sub:
                out[i["id"]] = (i, {"kind": "ammo", "sub": sub,
                                    "lvl": i.get("requiredLevel") or 0, "ilvl": i.get("itemLevel") or 0})
        if not page["meta"].get("next"):
            break
        offset += 100

    write(build, out)
    counts = {}
    for _, f in out.values():
        counts[f["kind"]] = counts.get(f["kind"], 0) + 1
    print(counts, "build", build)


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    return '"%s"' % v


ORDER = ("kind", "sub", "stat", "lvl", "ilvl", "score", "amount", "armor", "minIlvl", "caster", "spell")
KIND_ORDER = {"food": 0, "kit": 1, "boost": 2, "scroll": 3, "ammo": 4}


def write(build, out):
    parts = [
        "-- Squared Away: item data, generated by tools/build_data.py. Do not edit.",
        "-- Data from ForeverDB.net (https://foreverdb.net), game build %s." % build,
        "-- Names, icons and tooltips come from the game in your client language;",
        "-- this file only says what each item is, so no tooltip words are needed.",
        "",
        "local ADDON, ns = ...",
        "",
        'ns.DATA_BUILD = "%s"' % build,
        'ns.DATA_SOURCE = "Data from ForeverDB.net (https://foreverdb.net)"',
        "",
        "ns.ITEMS = {",
    ]
    rows = sorted(out.items(), key=lambda kv: (KIND_ORDER[kv[1][1]["kind"]], kv[1][1]["lvl"], kv[1][0]["name"]))
    kind = None
    for iid, (item, f) in rows:
        if f["kind"] != kind:
            kind = f["kind"]
            parts.append("    -- %s" % kind)
        fields = ", ".join("%s = %s" % (k, lua_value(f[k])) for k in ORDER if f.get(k) is not None)
        parts.append("    [%d] = { %s }, -- %s" % (iid, fields, item["name"]))
    parts += ["}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(parts))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
