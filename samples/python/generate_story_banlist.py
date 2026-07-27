import json
import sqlite3
from pathlib import Path

from project_paths import get_unlocked_cards_path

TOOLS_FOLDER = Path(__file__).resolve().parent
LAUNCHER_ROOT = TOOLS_FOLDER.parent

POSSIBLE_GAME_ROOTS = [
    LAUNCHER_ROOT,
    LAUNCHER_ROOT.parent,
    LAUNCHER_ROOT.parent.parent,
]

UNLOCKED_CARDS_PATH = get_unlocked_cards_path()

def find_edopro_root():
    for root in POSSIBLE_GAME_ROOTS:
        candidate = root / "EDOPro"
        if (candidate / "EDOPro.exe").exists():
            return candidate
    return None

EDOPRO_ROOT = find_edopro_root()

def find_reference_tcg_lflist():
    if EDOPRO_ROOT is None:
        return None

    candidates = [
        EDOPRO_ROOT / "repositories" / "lflists" / "0TCG.lflist.conf",
        EDOPRO_ROOT / "lflists" / "0TCG.lflist.conf",
    ]

    for candidate in candidates:
        if candidate.exists():
            return candidate

    matches = list(EDOPRO_ROOT.rglob("0TCG.lflist.conf"))

    if matches:
        return matches[0]

    return None

def load_unlocked_cards():
    if not UNLOCKED_CARDS_PATH.exists():
        raise FileNotFoundError(
            f"unlocked_cards.json not found:\n{UNLOCKED_CARDS_PATH}"
        )

    with open(UNLOCKED_CARDS_PATH, "r", encoding="utf-8") as file:
        data = json.load(file)

    unlocked = data.get("unlocked_cards")

    if not isinstance(unlocked, dict):
        raise ValueError(
            "unlocked_cards.json must contain an 'unlocked_cards' dictionary."
        )

    return unlocked

def parse_lflist(lflist_path):
    restrictions = {}

    with open(lflist_path, "r", encoding="utf-8", errors="ignore") as file:
        for raw_line in file:
            line = raw_line.strip()

            if not line:
                continue

            if line.startswith("#"):
                continue

            if line.startswith("!"):
                continue

            parts = line.split()

            if len(parts) < 2:
                continue

            card_id = parts[0].strip()
            limit_value = parts[1].strip()

            if not card_id.isdigit():
                continue

            if limit_value not in ["0", "1", "2", "3"]:
                continue

            restrictions[card_id] = limit_value

    return restrictions

def find_cdb_files():
    if EDOPRO_ROOT is None:
        return []

    return sorted(EDOPRO_ROOT.rglob("*.cdb"))

def load_all_existing_cards():
    all_cards = {}

    for cdb_path in find_cdb_files():
        try:
            conn = sqlite3.connect(cdb_path)
            cursor = conn.cursor()

            cursor.execute("SELECT id, name FROM texts")

            for card_id, name in cursor.fetchall():
                card_id = str(card_id).strip()

                if card_id:
                    all_cards[card_id] = name

            conn.close()

        except Exception:
            continue

    return all_cards

def generate_story_banlist(
    all_existing_cards,
    unlocked_cards,
    reference_restrictions
):
    lines = []

    lines.append("!StoryMode")
    lines.append("# Auto-generated Story Mode banlist")
    lines.append("# Locked cards = forbidden")
    lines.append("# Unlocked cards inherit TCG restrictions")
    lines.append("")

    locked_count = 0
    copied_tcg_count = 0

    for card_id in sorted(
        all_existing_cards.keys(),
        key=lambda item: int(item)
    ):

        # LOCKED CARD
        if card_id not in unlocked_cards:
            lines.append(card_id + " 0")
            locked_count += 1
            continue

        # UNLOCKED CARD
        if card_id in reference_restrictions:
            limit_value = reference_restrictions[card_id]

            # only write restricted cards
            if limit_value != "3":
                lines.append(card_id + " " + limit_value)
                copied_tcg_count += 1

    lines.append("")
    lines.append("# Locked cards forbidden: " + str(locked_count))
    lines.append("# TCG restrictions copied: " + str(copied_tcg_count))

    return "\n".join(lines)

def main():
    if EDOPRO_ROOT is None:
        print("ERROR: EDOPro folder not found.")
        return

    reference_lflist = find_reference_tcg_lflist()

    if reference_lflist is None:
        print("ERROR: 0TCG.lflist.conf not found.")
        return

    unlocked_cards = load_unlocked_cards()

    reference_restrictions = parse_lflist(reference_lflist)

    all_existing_cards = load_all_existing_cards()

    output_folder = EDOPRO_ROOT / "repositories" / "lflists"

    output_folder.mkdir(parents=True, exist_ok=True)

    output_path = output_folder / "StoryMode.lflist.conf"

    story_text = generate_story_banlist(
        all_existing_cards,
        unlocked_cards,
        reference_restrictions
    )

    with open(output_path, "w", encoding="utf-8") as file:
        file.write(story_text)

    print("StoryMode banlist generated.")
    print(f"EDOPro root: {EDOPRO_ROOT}")
    print(f"Reference list: {reference_lflist}")
    print(f"Output: {output_path}")
    print(f"Total existing cards: {len(all_existing_cards)}")
    print(f"Unlocked cards: {len(unlocked_cards)}")

if __name__ == "__main__":
    main()