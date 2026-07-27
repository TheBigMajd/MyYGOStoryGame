import json
import sqlite3
from pathlib import Path

TOOLS_FOLDER = Path(__file__).resolve().parent
LAUNCHER_ROOT = TOOLS_FOLDER.parent

POSSIBLE_GAME_ROOTS = [
    LAUNCHER_ROOT,
    LAUNCHER_ROOT.parent,
    LAUNCHER_ROOT.parent.parent,
]

from project_paths import (
    get_unlocked_cards_path,
    VALIDATION_RESULT_PATH
)

UNLOCKED_CARDS_PATH = get_unlocked_cards_path()

RESULT_PATH = VALIDATION_RESULT_PATH

def find_edopro_root():
    for root in POSSIBLE_GAME_ROOTS:
        candidate = root / "EDOPro"
        if (candidate / "EDOPro.exe").exists():
            return candidate
    return None

EDOPRO_ROOT = find_edopro_root()
DECK_FOLDER = EDOPRO_ROOT / "deck" if EDOPRO_ROOT else None

def write_result(valid, message, illegal_decks=None, cdb_files=None):
    RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)

    data = {
        "valid": valid,
        "message": message,
        "illegal_decks": illegal_decks or {},
        "cdb_files_scanned": cdb_files or [],
        "launcher_root": str(LAUNCHER_ROOT),
        "edopro_root": str(EDOPRO_ROOT) if EDOPRO_ROOT else "",
        "deck_folder": str(DECK_FOLDER) if DECK_FOLDER else ""
    }

    with open(RESULT_PATH, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)

def load_unlocked_cards():
    if not UNLOCKED_CARDS_PATH.exists():
        raise FileNotFoundError(f"unlocked_cards.json not found:\n{UNLOCKED_CARDS_PATH}")

    with open(UNLOCKED_CARDS_PATH, "r", encoding="utf-8") as file:
        data = json.load(file)

    unlocked = data.get("unlocked_cards")

    if not isinstance(unlocked, dict):
        raise ValueError("unlocked_cards.json must contain an 'unlocked_cards' dictionary.")

    return unlocked

def find_cdb_files():
    if EDOPRO_ROOT is None:
        return []
    return sorted(EDOPRO_ROOT.rglob("*.cdb"))

def load_existing_cards_from_cdb():
    existing_cards = {}
    scanned_files = []

    for cdb_path in find_cdb_files():
        try:
            conn = sqlite3.connect(cdb_path)
            cursor = conn.cursor()
            cursor.execute("SELECT id, name FROM texts")

            for card_id, name in cursor.fetchall():
                card_id = str(card_id).strip()
                name = str(name).strip()

                if card_id and card_id not in existing_cards:
                    existing_cards[card_id] = name

            conn.close()
            scanned_files.append(str(cdb_path))

        except Exception:
            continue

    return existing_cards, scanned_files

def read_ydk_card_ids(deck_path):
    card_ids = []

    with open(deck_path, "r", encoding="utf-8", errors="ignore") as file:
        for raw_line in file:
            line = raw_line.strip()

            if not line:
                continue

            if line.startswith("#") or line.startswith("!"):
                continue

            if line.isdigit():
                card_ids.append(line)

    return card_ids

def unique_card_entries(card_entries):
    seen = set()
    unique = []

    for card in card_entries:
        card_id = card["id"]

        if card_id not in seen:
            seen.add(card_id)
            unique.append(card)

    return unique

def validate_decks(existing_cards, unlocked_cards):
    if DECK_FOLDER is None:
        return False, "EDOPro folder not found.", {}

    if not DECK_FOLDER.exists():
        return False, f"Deck folder not found:\n{DECK_FOLDER}", {}

    ydk_files = sorted(DECK_FOLDER.glob("*.ydk"))

    if not ydk_files:
        return False, f"No .ydk decks found:\n{DECK_FOLDER}", {}

    illegal_decks = {}

    for deck_path in ydk_files:
        locked_cards = []
        missing_from_cdb = []

        card_ids = read_ydk_card_ids(deck_path)

        for card_id in card_ids:
            if card_id not in existing_cards:
                missing_from_cdb.append({
                    "id": card_id,
                    "name": "Unknown / missing from CDB"
                })
                continue

            if card_id not in unlocked_cards:
                locked_cards.append({
                    "id": card_id,
                    "name": existing_cards.get(card_id, "Unknown")
                })

        locked_cards = unique_card_entries(locked_cards)
        missing_from_cdb = unique_card_entries(missing_from_cdb)

        if locked_cards or missing_from_cdb:
            illegal_decks[deck_path.name] = {
                "locked_cards": locked_cards,
                "missing_from_cdb": missing_from_cdb
            }

    if illegal_decks:
        return False, "Pre-duel validation failed.", illegal_decks

    return True, f"Validation passed.\nChecked {len(ydk_files)} deck(s).", {}

def main():
    try:
        if EDOPRO_ROOT is None:
            write_result(False, "EDOPro folder not found.", {}, [])
            return

        unlocked_cards = load_unlocked_cards()
        existing_cards, scanned_files = load_existing_cards_from_cdb()

        if not existing_cards:
            write_result(False, "No cards found in CDB files.", {}, scanned_files)
            return

        valid, message, illegal_decks = validate_decks(existing_cards, unlocked_cards)
        write_result(valid, message, illegal_decks, scanned_files)

    except Exception as error:
        write_result(False, f"Validation tool error:\n{error}", {}, [])

if __name__ == "__main__":
    main()