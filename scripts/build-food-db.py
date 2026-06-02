#!/usr/bin/env python3
"""
build-food-db.py — regenerate the bundled offline USDA food database.

WHAT IT DOES
  Downloads the USDA FoodData Central bulk datasets (Foundation Foods + SR
  Legacy), prunes them to whole/common foods, extracts ONLY the fields the app
  uses (calories, protein, carbs, fat, fiber, a sensible serving size, name, and
  a few aliases), and writes the compact JSON the app loads at runtime:

      OurFitness/Resources/usda-foods.json

  The app reads this via Domain/FoodDatabase.swift. NO runtime network — this is
  a build-time, offline-first pipeline. USDA FoodData Central is public domain
  (CC0): https://fdc.nal.usda.gov/download-datasets/

WHY A SCRIPT (and why the repo ships only a small seed)
  The bulk datasets are hundreds of MB and cannot be downloaded on the dev's
  Windows host. The repo ships a hand-verified seed of real USDA values so the
  app compiles, runs, and tests pass today. Run THIS script on a Mac/CI with
  network to populate the full dataset before a release build.

USAGE
  # Default: download both datasets, emit the resource.
  python3 scripts/build-food-db.py

  # Limit the row count (useful for a quick smoke test):
  python3 scripts/build-food-db.py --max 1500

  # Point at already-downloaded dataset zips instead of fetching:
  python3 scripts/build-food-db.py \
      --foundation /path/FoodData_Central_foundation_food_json_*.zip \
      --sr-legacy  /path/FoodData_Central_sr_legacy_food_json_*.zip

DATASET URLs (check the download page for the current dated Foundation filename —
https://fdc.nal.usda.gov/download-datasets/):
  https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_<date>.zip
  https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_<date>.zip

NOTES
  * Numbers are NEVER invented — every value comes straight from USDA.
  * Per-100g USDA values are scaled to a friendly serving (see SERVING_RULES).
  * Branded Foods is intentionally excluded (noisy, not CC0-uniform, huge).
  * Output is sorted + pretty-printed so diffs are reviewable.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "OurFitness" / "Resources" / "usda-foods.json"

# USDA nutrient numbers (stable across datasets):
# Energy: prefer classic Energy (kcal, #208); Foundation Foods frequently report
# energy ONLY as Atwater (#957 general / #958 specific) — also kcal — so fall back
# to those. Without this, most Foundation rows have no #208 and get dropped → 0 foods.
ENERGY_NUMBERS_KCAL = ("208", "957", "958")
N_PROTEIN = "203"
N_CARB = "205"
N_FAT = "204"
N_FIBER = "291"

# Foods we drop by keyword — supplements, infant formula, fast-food brands, and
# fortified/odd reference rows that pollute natural-language matching.
DROP_KEYWORDS = [
    "infant formula", "baby food", "supplement", "fortified", "imitation",
    "restaurant", "fast food", "mcdonald", "burger king", "taco bell",
    "school lunch", "usda commodity", "nfs", "babyfood", "puree, junior",
]

# A friendly serving label + gram weight per food-name keyword. USDA bulk values
# are per 100 g; we scale to one of these servings. First keyword match wins;
# the fallback is a flat 100 g serving.
SERVING_RULES: list[tuple[re.Pattern, str, float]] = [
    (re.compile(r"\b(oil|butter|margarine|lard|shortening)\b"), "1 tbsp (14 g)", 14),
    (re.compile(r"\b(mayonnaise|ketchup|mustard|honey|syrup|jam|jelly)\b"), "1 tbsp (20 g)", 20),
    (re.compile(r"\b(cheese)\b"), "1 oz (28 g)", 28),
    (re.compile(r"\b(nuts?|almonds?|walnuts?|pecans?|cashews?|pistachios?|seeds?)\b"), "1 oz (28 g)", 28),
    (re.compile(r"\b(chicken|beef|pork|turkey|fish|salmon|cod|tilapia|tuna|shrimp|lamb|steak)\b"), "4 oz cooked (113 g)", 113),
    (re.compile(r"\b(rice|pasta|quinoa|couscous|barley|oats?|oatmeal)\b"), "1 cup cooked (158 g)", 158),
    (re.compile(r"\b(bread|bagel|tortilla|roll)\b"), "1 slice/piece (40 g)", 40),
    (re.compile(r"\b(milk|juice|beverage|drink)\b"), "1 cup (240 g)", 240),
    (re.compile(r"\b(apple|banana|orange|pear|peach|plum)\b"), "1 medium (150 g)", 150),
]
DEFAULT_SERVING = ("1 cup (150 g)", 150.0)

# Up to this many aliases per food, derived from the USDA description.
MAX_ALIASES = 4


def log(msg: str) -> None:
    print(f"[build-food-db] {msg}", file=sys.stderr)


def fetch_zip(url: str) -> zipfile.ZipFile:
    log(f"downloading {url}")
    with urllib.request.urlopen(url) as resp:
        data = resp.read()
    return zipfile.ZipFile(io.BytesIO(data))


def load_zip(path: str) -> zipfile.ZipFile:
    log(f"reading {path}")
    return zipfile.ZipFile(path)


def iter_foods(zf: zipfile.ZipFile):
    """Yield raw food dicts from a FoodData Central JSON zip."""
    name = next((n for n in zf.namelist() if n.lower().endswith(".json")), None)
    if not name:
        log("  no JSON found in zip — skipping")
        return
    with zf.open(name) as fh:
        doc = json.load(fh)
    # Foundation/SR legacy bundles key the array under a dataset-specific name.
    for key in ("FoundationFoods", "SRLegacyFoods", "foods"):
        if key in doc:
            yield from doc[key]
            return
    # Some exports are a bare top-level list.
    if isinstance(doc, list):
        yield from doc


def nutrient_value(food: dict, number: str) -> float | None:
    for n in food.get("foodNutrients", []):
        meta = n.get("nutrient", {})
        if str(meta.get("number")) == number:
            amt = n.get("amount")
            if amt is not None:
                return float(amt)
    return None


def energy_kcal(food: dict) -> float | None:
    """Energy in kcal, preferring classic Energy (#208) then Atwater (#957/#958)."""
    found: dict[str, float] = {}
    for n in food.get("foodNutrients", []):
        num = str(n.get("nutrient", {}).get("number"))
        amt = n.get("amount")
        if num in ENERGY_NUMBERS_KCAL and amt is not None:
            found.setdefault(num, float(amt))
    for num in ENERGY_NUMBERS_KCAL:
        if num in found:
            return found[num]
    return None


def serving_for(name_lower: str) -> tuple[str, float]:
    for pattern, label, grams in SERVING_RULES:
        if pattern.search(name_lower):
            return label, grams
    return DEFAULT_SERVING


def make_aliases(description: str) -> tuple[str, list[str]]:
    """Return (clean display name, aliases) from a USDA description like
    'Chicken, broilers or fryers, breast, meat only, cooked, roasted'."""
    parts = [p.strip() for p in description.split(",") if p.strip()]
    display = parts[0].capitalize() if parts else description
    aliases: list[str] = []
    seen = set()
    for p in [description] + parts:
        key = p.lower()
        if key and key not in seen and len(key) > 2:
            seen.add(key)
            aliases.append(key)
        if len(aliases) >= MAX_ALIASES:
            break
    return display, aliases


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def build_entry(food: dict) -> dict | None:
    desc = food.get("description", "")
    if not desc:
        return None
    low = desc.lower()
    if any(k in low for k in DROP_KEYWORDS):
        return None

    kcal = energy_kcal(food)
    protein = nutrient_value(food, N_PROTEIN)
    carb = nutrient_value(food, N_CARB)
    fat = nutrient_value(food, N_FAT)
    fiber = nutrient_value(food, N_FIBER)
    if kcal is None or kcal <= 0:
        return None  # no usable energy → drop

    label, grams = serving_for(low)
    scale = grams / 100.0
    display, aliases = make_aliases(desc)
    fdc_id = food.get("fdcId", slugify(display))

    def g(v: float | None) -> int:
        return int(round((v or 0.0) * scale))

    return {
        "id": f"usda-{fdc_id}",
        "name": display,
        "aliases": aliases,
        "servingLabel": label,
        "calories": g(kcal),
        "proteinG": g(protein),
        "carbsG": g(carb),
        "fatG": g(fat),
        "fiberG": g(fiber),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the offline USDA food DB resource.")
    ap.add_argument("--foundation", help="Path to a Foundation Foods JSON zip (skips download).")
    ap.add_argument("--sr-legacy", help="Path to an SR Legacy JSON zip (skips download).")
    # Dataset zips live under https://fdc.nal.usda.gov/fdc-datasets/ (the host the
    # download page's own links resolve to, and the host the original run already
    # downloaded from successfully). Foundation Foods is reissued ~twice a year
    # under a new date; SR Legacy is a frozen 2018 final release. If a default 404s,
    # grab the current dated link from https://fdc.nal.usda.gov/download-datasets/
    # and pass it via --foundation-url / --sr-legacy-url.
    ap.add_argument(
        "--foundation-url",
        default="https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2024-10-31.zip",
        help="Override Foundation download URL (update the date as USDA reissues it).",
    )
    ap.add_argument(
        "--sr-legacy-url",
        default="https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip",
        help="Override SR Legacy download URL.",
    )
    ap.add_argument("--max", type=int, default=0, help="Cap the number of output rows (0 = no cap).")
    args = ap.parse_args()

    zips: list[zipfile.ZipFile] = []
    zips.append(load_zip(args.foundation) if args.foundation else fetch_zip(args.foundation_url))
    zips.append(load_zip(args.sr_legacy) if args.sr_legacy else fetch_zip(args.sr_legacy_url))

    by_id: dict[str, dict] = {}
    raw_count = 0
    datatypes_seen: dict[str, int] = {}
    for zf in zips:
        for food in iter_foods(zf):
            raw_count += 1
            # Normalize dataType (USDA uses "foundation_food"/"sr_legacy_food", but
            # casing/spacing varies and some exports omit it). Keep foods with no
            # dataType (the zips are already type-specific) and accept any
            # foundation/SR-legacy variant — a strict exact-match here was silently
            # dropping every food.
            dt = (food.get("dataType") or "").lower().replace(" ", "_")
            datatypes_seen[dt or "(none)"] = datatypes_seen.get(dt or "(none)", 0) + 1
            if dt and not any(k in dt for k in ("foundation", "sr_legacy", "srlegacy", "legacy")):
                continue
            entry = build_entry(food)
            if entry:
                by_id[entry["id"]] = entry

    all_entries = sorted(by_id.values(), key=lambda e: e["name"].lower())

    # Guard: a failed/empty download or a parse mismatch must NOT silently overwrite
    # the bundled dataset with an empty file. The real USDA Foundation + SR Legacy
    # whole-foods set is thousands of rows; a tiny count means something failed.
    # Refuse to write, and log enough to localize the cause. (Before --max capping.)
    MIN_FOODS = 100
    if len(all_entries) < MIN_FOODS:
        log(f"ERROR: only {len(all_entries)} foods kept from {raw_count} raw rows "
            f"(< {MIN_FOODS}). Refusing to overwrite {OUTPUT.relative_to(REPO_ROOT)}.")
        log(f"  dataTypes seen: {datatypes_seen}")
        if raw_count == 0:
            log("  raw_count == 0 → iter_foods found no food array. Check the JSON "
                "top-level key (expected FoundationFoods / SRLegacyFoods) or the zip URL.")
        else:
            log("  raw rows were read but almost all dropped → the dataType filter, "
                "energy lookup, or DROP_KEYWORDS removed them. Inspect a sample food's keys.")
        log("  Datasets: https://fdc.nal.usda.gov/download-datasets/ — pass current "
            "links via --foundation-url / --sr-legacy-url or local zips via "
            "--foundation / --sr-legacy if a URL 404s.")
        return 1

    entries = all_entries[: args.max] if args.max > 0 else all_entries

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    log(f"wrote {len(entries)} foods → {OUTPUT.relative_to(REPO_ROOT)}")
    log("done. Commit the regenerated resource and rebuild via XcodeGen/CI.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
