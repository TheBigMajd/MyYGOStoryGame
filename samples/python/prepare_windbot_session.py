import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

from project_paths import CURRENT_DUEL_SESSION_PATH, DUEL_SESSION_CONFIGS

TOOLS_FOLDER = Path(__file__).resolve().parent
LAUNCHER_ROOT = TOOLS_FOLDER.parent

POSSIBLE_GAME_ROOTS = [
    LAUNCHER_ROOT,
    LAUNCHER_ROOT.parent,
    LAUNCHER_ROOT.parent.parent,
]


def find_game_root() -> Path:
    for root in POSSIBLE_GAME_ROOTS:
        if (root / "EDOPro" / "EDOPro.exe").exists():
            return root
    return LAUNCHER_ROOT.parent


GAME_ROOT = find_game_root()

SESSION_PATH = CURRENT_DUEL_SESSION_PATH
DUEL_CONFIGS_FOLDER = DUEL_SESSION_CONFIGS

WINDBOT_FOLDER = GAME_ROOT / "EDOPro" / "WindBot"
BOTS_JSON = WINDBOT_FOLDER / "bots.json"
DECKS_FOLDER = WINDBOT_FOLDER / "Decks"

BACKUP_FOLDER = WINDBOT_FOLDER / "_storygame_backup"
BOTS_BACKUP = BACKUP_FOLDER / "bots.json"
DECKS_BACKUP = BACKUP_FOLDER / "Decks"


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)


def clean_folder(path: Path):
    path.mkdir(parents=True, exist_ok=True)
    for item in path.iterdir():
        if item.is_dir():
            shutil.rmtree(item)
        else:
            item.unlink()


def restore_existing_backup_if_needed():
    if not BACKUP_FOLDER.exists():
        return

    if not BOTS_BACKUP.exists():
        raise FileNotFoundError(f"bots.json backup not found: {BOTS_BACKUP}")
    if not DECKS_BACKUP.exists():
        raise FileNotFoundError(f"Decks backup not found: {DECKS_BACKUP}")

    shutil.copy2(BOTS_BACKUP, BOTS_JSON)
    clean_folder(DECKS_FOLDER)

    for item in DECKS_BACKUP.iterdir():
        target = DECKS_FOLDER / item.name
        if item.is_dir():
            shutil.copytree(item, target)
        else:
            shutil.copy2(item, target)

    shutil.rmtree(BACKUP_FOLDER)


def backup_originals():
    if BACKUP_FOLDER.exists():
        raise RuntimeError(f"Backup folder still exists: {BACKUP_FOLDER}")

    BACKUP_FOLDER.mkdir(parents=True, exist_ok=True)
    shutil.copy2(BOTS_JSON, BOTS_BACKUP)
    shutil.copytree(DECKS_FOLDER, DECKS_BACKUP)


def load_duel_config_from_id(duel_session_id: str) -> dict:
    duel_session_id = str(duel_session_id).strip()

    if not duel_session_id:
        raise ValueError("Missing duel_session_id.")

    config_path = DUEL_CONFIGS_FOLDER / f"{duel_session_id}.json"

    if not config_path.exists():
        raise FileNotFoundError(f"Duel session config not found: {config_path}")

    config = load_json(config_path)

    config_session_id = str(config.get("session_id", "")).strip()

    if config_session_id and config_session_id != duel_session_id:
        raise ValueError(
            f"Duel config session_id mismatch. File requested '{duel_session_id}', "
            f"but config contains '{config_session_id}'."
        )

    config["session_id"] = duel_session_id
    config["status"] = "loaded_from_config"
    config["loaded_from_config_path"] = str(config_path)

    return config


def write_current_session_from_config(duel_session_id: str) -> dict:
    session = load_duel_config_from_id(duel_session_id)

    session["started_at"] = ""
    session["prepared_at"] = ""
    session["restored_at"] = ""

    save_json(SESSION_PATH, session)
    return session


def prepare_session():
    if len(sys.argv) >= 2:
        duel_session_id = sys.argv[1]
        write_current_session_from_config(duel_session_id)

    if not SESSION_PATH.exists():
        raise FileNotFoundError(f"Session file not found: {SESSION_PATH}")
    if not BOTS_JSON.exists():
        raise FileNotFoundError(f"bots.json not found: {BOTS_JSON}")
    if not DECKS_FOLDER.exists():
        raise FileNotFoundError(f"Decks folder not found: {DECKS_FOLDER}")

    restore_existing_backup_if_needed()

    session = load_json(SESSION_PATH)

    windbot_name = str(session.get("windbot_name", "")).strip()
    windbot_deck = str(session.get("windbot_deck", "")).strip()
    windbot_deck_file = str(session.get("windbot_deck_file", "")).strip()

    if not windbot_name:
        raise ValueError("current_duel_session.json missing windbot_name")
    if not windbot_deck:
        raise ValueError("current_duel_session.json missing windbot_deck")
    if not windbot_deck_file:
        windbot_deck_file = windbot_deck + ".ydk"

    source_deck = DECKS_FOLDER / windbot_deck_file
    if not source_deck.exists():
        raise FileNotFoundError(f"Selected WindBot deck not found: {source_deck}")

    backup_originals()

    backup_source_deck = DECKS_BACKUP / windbot_deck_file
    if not backup_source_deck.exists():
        raise FileNotFoundError(f"Selected deck missing from backup: {backup_source_deck}")

    clean_folder(DECKS_FOLDER)
    shutil.copy2(backup_source_deck, DECKS_FOLDER / windbot_deck_file)

    temp_bots = [{
        "name": windbot_name,
        "deck": windbot_deck,
        "difficulty": int(session.get("difficulty", 3)),
        "masterRules": session.get("masterRules", [5])
    }]

    save_json(BOTS_JSON, temp_bots)

    session["started_at"] = datetime.now(timezone.utc).isoformat()
    session["prepared_at"] = datetime.now(timezone.utc).isoformat()
    session["status"] = "prepared"
    save_json(SESSION_PATH, session)

    print("WINDBOT SESSION PREPARED")
    print(f"Session ID: {session.get('session_id', '')}")
    print(f"NPC ID: {session.get('npc_id', '')}")
    print(f"Folder: {WINDBOT_FOLDER}")
    print(f"Bot: {windbot_name}")
    print(f"Deck: {windbot_deck_file}")


if __name__ == "__main__":
    prepare_session()