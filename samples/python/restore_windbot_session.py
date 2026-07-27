import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from project_paths import CURRENT_DUEL_SESSION_PATH

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

def restore_session():
    if not BACKUP_FOLDER.exists():
        print("No WindBot backup folder found. Nothing to restore.")
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

    if SESSION_PATH.exists():
        session = load_json(SESSION_PATH)
        session["status"] = "restored"
        session["restored_at"] = datetime.now(timezone.utc).isoformat()
        save_json(SESSION_PATH, session)

    shutil.rmtree(BACKUP_FOLDER)

    print("WINDBOT SESSION RESTORED")
    print(f"Folder: {WINDBOT_FOLDER}")

if __name__ == "__main__":
    restore_session()