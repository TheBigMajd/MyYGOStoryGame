import json
import subprocess
import time
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
WINDBOT_EXE = WINDBOT_FOLDER / "WindBot.exe"
LOG_PATH = WINDBOT_FOLDER / "windbot_launch_log.txt"

def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)

def main():
    if not SESSION_PATH.exists():
        raise FileNotFoundError(f"Session file not found: {SESSION_PATH}")
    if not WINDBOT_EXE.exists():
        raise FileNotFoundError(f"WindBot.exe not found: {WINDBOT_EXE}")

    session = load_json(SESSION_PATH)

    deck = str(session.get("windbot_deck", "")).strip()
    join_name = str(session.get("windbot_join_name", "[AI] WindBot")).strip()
    port = str(session.get("port", 7911)).strip()
    version = str(session.get("version", 720937)).strip()

    if not deck:
        raise ValueError("current_duel_session.json missing windbot_deck")

    args = [
        str(WINDBOT_EXE),
        "HostInfo=",
        f"Deck={deck}",
        f"Port={port}",
        f"Version={version}",
        f"name={join_name}",
        "Chat=true",
        "Hand=0",
        f"AssetPath={WINDBOT_FOLDER.as_posix()}",
    ]

    with open(LOG_PATH, "w", encoding="utf-8") as log:
        log.write("Launching WindBot:\n")
        log.write(" ".join(args) + "\n\n")
        log.flush()

        subprocess.Popen(
            args,
            cwd=str(WINDBOT_FOLDER),
            stdout=log,
            stderr=log,
            shell=False,
        )

    print("WindBot launched.")
    print(f"Log: {LOG_PATH}")

if __name__ == "__main__":
    time.sleep(2)
    main()