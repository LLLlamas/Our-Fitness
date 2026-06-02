#!/usr/bin/env python3
"""
build-food-db.py — regenerate the bundled offline USDA food database.

WHAT IT DOES
  Downloads the USDA FoodData Central bulk datasets (Foundation Foods + SR
  Legacy + Branded Foods), prunes them to whole/common/recognizable foods,
  extracts ONLY the fields the app uses (calories, protein, carbs, fat, fiber,
  a sensible serving size, name, and a few aliases), and writes the database the
  app queries at runtime. Default output is a SQLite/FTS5 database:

      OurFitness/Resources/usda-foods.db   (--format sqlite, the default)
      OurFitness/Resources/usda-foods.json (--format json — legacy JSON)

  The app reads the .db via Domain/SQLiteFoodDatabase.swift (queried on disk via
  FTS5, so RAM stays low at ~270k entries). NO runtime network — this is
  a build-time, offline-first pipeline. USDA FoodData Central is public domain
  (CC0): https://fdc.nal.usda.gov/download-datasets/

WHY A SCRIPT (and why the repo ships only a small seed)
  The bulk datasets are hundreds of MB (Branded is ~GB uncompressed) and cannot
  be downloaded on the dev's Windows host. The repo ships a hand-verified seed of
  real USDA values so the app compiles, runs, and tests pass today. Run THIS
  script on a Mac/CI with network to populate the full dataset before a release
  build.

DATA SOURCES (three, all USDA, all CC0)
  * Foundation Foods + SR Legacy — per-100 g `foodNutrients` arrays. Scaled to a
    friendly serving (see SERVING_RULES).
  * Branded Foods — per-SERVING `labelNutrients` (the Nutrition Facts panel). NOT
    scaled: the label values are used as-is against the product's stated serving.
    Huge (~400k+ items), so it is STREAM-parsed with ijson — never json.load'd.

USAGE
  # Default: download all three datasets, emit the SQLite/FTS5 database.
  python3 scripts/build-food-db.py

  # Emit the legacy JSON instead (or both):
  python3 scripts/build-food-db.py --format json
  python3 scripts/build-food-db.py --format both

  # Limit the row count (useful for a quick smoke test):
  python3 scripts/build-food-db.py --max 1500

  # Skip the (large) Branded download — Foundation + SR Legacy only:
  python3 scripts/build-food-db.py --no-branded

  # Point at already-downloaded dataset zips instead of fetching:
  python3 scripts/build-food-db.py \
      --foundation /path/FoodData_Central_foundation_food_json_*.zip \
      --sr-legacy  /path/FoodData_Central_sr_legacy_food_json_*.zip \
      --branded    /path/FoodData_Central_branded_food_json_*.zip

DATASET URLs (check the download page for the current dated filenames —
https://fdc.nal.usda.gov/download-datasets/):
  https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_<date>.zip
  https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_<date>.zip
  https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_branded_food_json_<date>.zip

NOTES
  * Numbers are NEVER invented — every value comes straight from USDA.
  * Per-100g USDA values are scaled to a friendly serving (see SERVING_RULES);
    Branded label values are used per-serving, unscaled.
  * Branded is filtered/deduped/per-brand-capped down to a recognizable subset
    (see select_branded) so it doesn't flood the bundle with UPC duplicates.
  * A failed Branded download is non-fatal: Foundation + SR Legacy still write.
  * Output is sorted + pretty-printed so diffs are reviewable.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sqlite3
import sys
import urllib.request
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_JSON = REPO_ROOT / "OurFitness" / "Resources" / "usda-foods.json"
OUTPUT_DB = REPO_ROOT / "OurFitness" / "Resources" / "usda-foods.db"

# USDA nutrient numbers (stable across datasets):
# Energy: prefer classic Energy (kcal, #208); Foundation Foods frequently report
# energy ONLY as Atwater (#957 general / #958 specific) — also kcal — so fall back
# to those. Without this, most Foundation rows have no #208 and get dropped → 0 foods.
ENERGY_NUMBERS_KCAL = ("208", "957", "958")
N_PROTEIN = "203"
N_CARB = "205"
N_FAT = "204"
N_FIBER = "291"

# Foods we drop by keyword — genuine noise that pollutes natural-language
# matching: supplements, infant formula, imitation/commodity reference rows.
# NOTE (2026-06): "fortified", "restaurant", "fast food", and the chain brands
# (mcdonald/burger king/taco bell) were intentionally REMOVED so SR Legacy's
# generic "Fast foods, …" / "Restaurant, Chinese, …" and fortified-cereal rows
# come through — they're real USDA whole-meal entries people search for. The
# kept terms below are the genuinely unhelpful ones.
DROP_KEYWORDS = [
    "infant formula", "baby food", "supplement", "imitation",
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

# Branded Foods tuning. The raw dataset is ~400k+ items dominated by UPC
# duplicates and obscure SKUs, so we trim it hard before merging:
#   * DEFAULT_BRANDED_CAP — total Branded rows kept (the rest of the bundle is
#     the few-thousand Foundation + SR Legacy whole foods).
#   * MAX_PER_BRAND — no single brandOwner may exceed this, so one mega-brand
#     (e.g. a store label) can't crowd out everything else.
#   * BRANDED_DESC_MAX_LEN — drop absurdly long/garbled marketing descriptions.
DEFAULT_BRANDED_CAP = 18000
MAX_PER_BRAND = 60
BRANDED_DESC_MAX_LEN = 60


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


# ---------------------------------------------------------------------------
# Branded Foods (per-serving labelNutrients, streamed with ijson)
# ---------------------------------------------------------------------------
# Branded items differ structurally from Foundation/SR: instead of a per-100 g
# `foodNutrients` array, each carries `labelNutrients` = the Nutrition Facts
# panel, PER SERVING. We use those values directly (no per-100g scaling) against
# the product's stated serving. Fields we read:
#   description, brandOwner, brandName, servingSize, servingSizeUnit,
#   householdServingFullText, brandedFoodCategory, labelNutrients{calories,
#   protein, carbohydrates, fat, fiber}{value}, fdcId.
# The top-level JSON key is "BrandedFoods" (an array of these items).

BRANDED_TOP_KEYS = ("BrandedFoods", "BrandedFoodItems", "foods")


def _label_value(label: dict, key: str) -> float | None:
    node = label.get(key)
    if isinstance(node, dict):
        v = node.get("value")
        if v is not None:
            try:
                return float(v)
            except (TypeError, ValueError):
                return None
    return None


def _clean_branded_name(brand: str, desc: str) -> str:
    """A short human label like 'Cheetos Crunchy'. Use the first description
    segment (USDA branded descriptions are often a single phrase) and prefix the
    brand if it isn't already in there."""
    core = desc.split(",")[0].strip()
    brand = (brand or "").strip()
    if brand and brand.lower() not in core.lower():
        name = f"{brand} {core}".strip()
    else:
        name = core or brand
    # Collapse SHOUTING brand strings to title-ish case without touching mixed
    # case the brand chose deliberately.
    if name.isupper():
        name = name.title()
    return name


def _branded_dedup_key(brand: str, desc: str) -> str:
    """Normalized identity used to collapse UPC duplicates: brand + the core of
    the description, lowercased and stripped of punctuation/whitespace runs."""
    core = desc.split(",")[0].strip()
    raw = f"{(brand or '').strip()} {core}".lower()
    return re.sub(r"[^a-z0-9]+", " ", raw).strip()


def build_branded_entry(food: dict) -> tuple[dict, str, str] | None:
    """Return (entry, brandOwner, dedup_key) or None. Values come straight from
    USDA labelNutrients (per serving) — never scaled, never invented."""
    desc = (food.get("description") or "").strip()
    if not desc:
        return None
    low = desc.lower()
    if any(k in low for k in DROP_KEYWORDS):
        return None
    if len(desc) > BRANDED_DESC_MAX_LEN:
        return None  # garbled/marketing-bloat description

    label = food.get("labelNutrients") or {}
    kcal = _label_value(label, "calories")
    if kcal is None or kcal <= 0:
        return None  # require real per-serving energy

    brand_name = (food.get("brandName") or "").strip()
    brand_owner = (food.get("brandOwner") or "").strip()
    brand = brand_name or brand_owner

    serving_size = food.get("servingSize")
    serving_unit = (food.get("servingSizeUnit") or "").strip()
    household = (food.get("householdServingFullText") or "").strip()
    if household:
        label_text = household
    elif serving_size is not None:
        size_str = f"{serving_size:g}" if isinstance(serving_size, (int, float)) else str(serving_size)
        label_text = f"{size_str}{serving_unit}".strip() or "1 serving"
    else:
        label_text = "1 serving"

    name = _clean_branded_name(brand, desc)
    if not name:
        return None

    # Aliases: full description + brand words + category, deduped, capped.
    aliases: list[str] = []
    seen: set[str] = set()
    for cand in (desc, brand, food.get("brandedFoodCategory") or ""):
        key = cand.strip().lower()
        if key and key not in seen and len(key) > 2:
            seen.add(key)
            aliases.append(key)
        if len(aliases) >= MAX_ALIASES:
            break

    fdc_id = food.get("fdcId", slugify(name))

    def g(v: float | None) -> int:
        return int(round(v or 0.0))

    entry = {
        "id": f"usda-{fdc_id}",
        "name": name,
        "aliases": aliases,
        "servingLabel": label_text,
        "calories": g(kcal),
        "proteinG": g(_label_value(label, "protein")),
        "carbsG": g(_label_value(label, "carbohydrates")),
        "fatG": g(_label_value(label, "fat")),
        "fiberG": g(_label_value(label, "fiber")),
    }
    return entry, (brand_owner or brand_name), _branded_dedup_key(brand, desc)


def iter_branded(zf: zipfile.ZipFile):
    """Yield raw Branded food dicts by STREAM-parsing the zip's JSON with ijson.
    The dataset is ~GB uncompressed and ~400k+ items, so it is NEVER json.load'd.
    ijson reads incrementally from the still-compressed zip entry's file object."""
    try:
        import ijson  # local import: only required when Branded is enabled
    except ImportError:
        log("  ijson not installed — cannot stream Branded Foods. "
            "Run `pip install ijson`. Skipping Branded.")
        return

    name = next((n for n in zf.namelist() if n.lower().endswith(".json")), None)
    if not name:
        log("  no JSON found in Branded zip — skipping")
        return

    # Try each known top-level array key until one yields items. zf.open returns
    # a streaming file object; ijson.items consumes it without buffering the doc.
    for key in BRANDED_TOP_KEYS:
        with zf.open(name) as fh:
            try:
                produced = False
                for item in ijson.items(fh, f"{key}.item"):
                    produced = True
                    yield item
                if produced:
                    return
            except Exception as exc:  # noqa: BLE001 — log and try the next key
                log(f"  ijson parse under key '{key}' failed: {exc}")
    log("  no Branded array found under any known top-level key "
        f"({', '.join(BRANDED_TOP_KEYS)}).")


def select_branded(zf: zipfile.ZipFile, cap: int) -> list[dict]:
    """Stream the Branded dataset and return a trimmed, deduped, per-brand-capped
    list of entries (<= cap). Selection strategy:
      1. Build a valid entry (real labelNutrients.calories, sane description,
         passes DROP_KEYWORDS) — invalid items are skipped.
      2. Dedup by normalized (brand + core description) → collapses UPC dupes to
         the first occurrence.
      3. Cap each brandOwner at MAX_PER_BRAND so no brand floods the bundle.
      4. Stop once `cap` unique entries are kept. (Streaming order is the
         dataset's own order; we prefer concise non-empty-brand items implicitly
         by skipping garbled/long descriptions in build_branded_entry.)
    Returns the kept entries; logs how many were scanned / kept / dropped."""
    kept: list[dict] = []
    seen_keys: set[str] = set()
    per_brand: dict[str, int] = {}
    scanned = 0
    dup_dropped = 0
    brand_capped = 0
    invalid = 0

    for food in iter_branded(zf):
        scanned += 1
        built = build_branded_entry(food)
        if built is None:
            invalid += 1
            continue
        entry, brand_owner, dedup_key = built
        if dedup_key in seen_keys:
            dup_dropped += 1
            continue
        bkey = (brand_owner or "").lower()
        if bkey and per_brand.get(bkey, 0) >= MAX_PER_BRAND:
            brand_capped += 1
            continue
        seen_keys.add(dedup_key)
        if bkey:
            per_brand[bkey] = per_brand.get(bkey, 0) + 1
        kept.append(entry)
        if len(kept) >= cap:
            log(f"  Branded cap of {cap} reached — stopping scan early.")
            break

    log(f"  Branded scanned={scanned} kept={len(kept)} "
        f"(invalid/dropped={invalid}, upc-dups={dup_dropped}, brand-capped={brand_capped})")
    return kept


# Guard: a failed/empty download or a parse mismatch must NOT silently overwrite
# the bundled dataset with an empty file. The real USDA Foundation + SR Legacy
# whole-foods set is thousands of rows; a tiny count means something failed.
MIN_FOODS = 100


def write_json(entries: list[dict]) -> None:
    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(
        json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    log(f"wrote {len(entries)} foods → {OUTPUT_JSON.relative_to(REPO_ROOT)}")


def write_sqlite(entries: list[dict]) -> None:
    """Emit the SQLite/FTS5 database the app queries on disk. Schema mirrors
    Domain/SQLiteFoodDatabase.swift: a `foods` content table + an external-content
    `foods_fts` FTS5 index (no text duplication → ~30% smaller). Aliases are stored
    pipe-joined in one column. Rebuilt + VACUUMed for a compact, reviewable file."""
    OUTPUT_DB.parent.mkdir(parents=True, exist_ok=True)
    # Start clean so re-runs don't append onto a stale db.
    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()

    conn = sqlite3.connect(OUTPUT_DB)
    try:
        cur = conn.cursor()
        cur.execute("PRAGMA journal_mode = DELETE;")
        cur.execute("PRAGMA page_size = 4096;")
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS foods (
                id TEXT NOT NULL,
                name TEXT NOT NULL,
                aliases TEXT NOT NULL,
                serving_label TEXT NOT NULL,
                calories INTEGER NOT NULL,
                protein_g INTEGER NOT NULL,
                carbs_g INTEGER NOT NULL,
                fat_g INTEGER NOT NULL,
                fiber_g INTEGER NOT NULL
            );
            """
        )
        cur.execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS foods_fts USING fts5(
                name,
                aliases,
                content=foods,
                content_rowid=rowid
            );
            """
        )
        cur.executemany(
            """
            INSERT INTO foods
                (id, name, aliases, serving_label,
                 calories, protein_g, carbs_g, fat_g, fiber_g)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    e["id"],
                    e["name"],
                    "|".join(e["aliases"]),
                    e["servingLabel"],
                    e["calories"],
                    e["proteinG"],
                    e["carbsG"],
                    e["fatG"],
                    e["fiberG"],
                )
                for e in entries
            ],
        )
        # Build the FTS5 index from the content table, then compact the file.
        cur.execute("INSERT INTO foods_fts(foods_fts) VALUES('rebuild');")
        conn.commit()
        cur.execute("VACUUM;")
        conn.commit()
    finally:
        conn.close()
    log(f"wrote {len(entries)} foods → {OUTPUT_DB.relative_to(REPO_ROOT)}")


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
    # Branded Foods is reissued ~monthly under a new date — UPDATE this when the
    # default 404s (grab the current link from the download-datasets page). The
    # date below is a best-effort current value and MUST be verified on the first
    # real run; a 404 here is non-fatal (Foundation + SR still write).
    ap.add_argument(
        "--branded-url",
        default="https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_branded_food_json_2026-04.zip",
        help="Override Branded Foods download URL (update the date — reissued ~monthly).",
    )
    ap.add_argument("--branded", help="Path to a Branded Foods JSON zip (skips download).")
    ap.add_argument("--no-branded", action="store_true", help="Skip the Branded Foods dataset entirely.")
    ap.add_argument(
        "--branded-cap", type=int, default=DEFAULT_BRANDED_CAP,
        help=f"Max Branded rows to keep after dedup/per-brand cap (default {DEFAULT_BRANDED_CAP}).",
    )
    ap.add_argument("--max", type=int, default=0, help="Cap the number of output rows (0 = no cap).")
    ap.add_argument(
        "--format", choices=("json", "sqlite", "both"), default="sqlite",
        help="Output format. 'sqlite' (default) emits usda-foods.db (FTS5); 'json' "
             "emits usda-foods.json; 'both' emits both.",
    )
    args = ap.parse_args()

    # Foundation + SR Legacy (per-100 g foodNutrients). These are required.
    base_zips: list[zipfile.ZipFile] = []
    base_zips.append(load_zip(args.foundation) if args.foundation else fetch_zip(args.foundation_url))
    base_zips.append(load_zip(args.sr_legacy) if args.sr_legacy else fetch_zip(args.sr_legacy_url))

    by_id: dict[str, dict] = {}
    raw_count = 0
    datatypes_seen: dict[str, int] = {}
    foundation_sr_kept = 0
    for zf in base_zips:
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
                if entry["id"] not in by_id:
                    foundation_sr_kept += 1
                by_id[entry["id"]] = entry

    # Branded Foods (per-serving labelNutrients, streamed). A download/parse
    # failure here is NON-FATAL — log and continue so a Branded 404 never wipes
    # out a successful Foundation + SR run. The <100 guard below still protects
    # against an overall-empty result.
    branded_kept = 0
    if args.no_branded:
        log("Branded Foods skipped (--no-branded).")
    else:
        try:
            branded_zip = load_zip(args.branded) if args.branded else fetch_zip(args.branded_url)
        except Exception as exc:  # noqa: BLE001 — download/open failure is non-fatal
            log(f"WARNING: Branded Foods download/open failed ({exc}). "
                "Continuing with Foundation + SR Legacy only. "
                "If this is a 404, grab the current dated link from "
                "https://fdc.nal.usda.gov/download-datasets/ and pass --branded-url.")
            branded_zip = None
        if branded_zip is not None:
            try:
                for entry in select_branded(branded_zip, args.branded_cap):
                    if entry["id"] not in by_id:
                        branded_kept += 1
                    by_id[entry["id"]] = entry
            except Exception as exc:  # noqa: BLE001 — parse failure is non-fatal
                log(f"WARNING: Branded Foods parse failed ({exc}). "
                    "Continuing with Foundation + SR Legacy only.")

    log(f"per-source kept: foundation+sr={foundation_sr_kept}, branded={branded_kept}, "
        f"total-unique={len(by_id)}")

    all_entries = sorted(by_id.values(), key=lambda e: e["name"].lower())

    # Guard: a failed/empty download or a parse mismatch must NOT silently overwrite
    # the bundled dataset with an empty file. The real USDA Foundation + SR Legacy
    # whole-foods set is thousands of rows; a tiny count means something failed.
    # Refuse to write, and log enough to localize the cause. (Before --max capping.)
    if len(all_entries) < MIN_FOODS:
        log(f"ERROR: only {len(all_entries)} foods kept from {raw_count} raw rows "
            f"(< {MIN_FOODS}). Refusing to write the food database.")
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

    if args.format in ("sqlite", "both"):
        write_sqlite(entries)
    if args.format in ("json", "both"):
        write_json(entries)
    log("done. Commit the regenerated resource and rebuild via XcodeGen/CI.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
