import json
from pathlib import Path
from datetime import datetime
import subprocess
import sqlite3
import sys

from project_paths import (
    CURRENT_DUEL_SESSION_PATH,
    WINDBOT_DUEL_RESULT_PATH,
    POST_DUEL_VALIDATION_RESULT_PATH,
    VALIDATION_RESULT_PATH
)

TOOLS_FOLDER = Path(__file__).resolve().parent
LAUNCHER_ROOT = TOOLS_FOLDER.parent

SESSION_PATH = CURRENT_DUEL_SESSION_PATH

RESULT_PATH = WINDBOT_DUEL_RESULT_PATH

POST_RESULT_PATH = POST_DUEL_VALIDATION_RESULT_PATH

PRE_RESULT_PATH = VALIDATION_RESULT_PATH

PRE_VALIDATOR_PATH = TOOLS_FOLDER / "pre_duel_validate.py"


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)


def parse_datetime(value: str):
    if not value:
        return None

    value = value.replace("Z", "+00:00")

    try:
        dt = datetime.fromisoformat(value)
    except ValueError:
        return None

    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)

    return dt


def names_match(expected: str, actual: str) -> bool:
    expected = str(expected or "").strip()
    actual = str(actual or "").strip()

    if not expected or not actual:
        return False

    if expected == actual:
        return True

    return expected.startswith(actual) or actual.startswith(expected)


def run_pre_duel_validator_again():
    if not PRE_VALIDATOR_PATH.exists():
        return {
            "valid": False,
            "message": f"pre_duel_validate.py not found: {PRE_VALIDATOR_PATH}"
        }

    completed = subprocess.run(
        [sys.executable, str(PRE_VALIDATOR_PATH)],
        cwd=str(TOOLS_FOLDER),
        capture_output=True,
        text=True
    )

    if completed.returncode != 0:
        return {
            "valid": False,
            "message": "Post-duel deck legality check failed while running pre_duel_validate.py.",
            "stdout": completed.stdout,
            "stderr": completed.stderr
        }

    if not PRE_RESULT_PATH.exists():
        return {
            "valid": False,
            "message": f"validation_result.json not found after post-duel validation: {PRE_RESULT_PATH}"
        }

    return load_json(PRE_RESULT_PATH)


def select_outcome(session: dict, duel_result: dict):
    outcomes = session.get("outcomes", {})

    winner_side = str(duel_result.get("winner_side", "unknown")).strip().lower()

    if winner_side == "player":
        return "on_player_win", outcomes.get("on_player_win", {})
    if winner_side == "bot":
        return "on_player_loss", outcomes.get("on_player_loss", {})
    if winner_side == "draw":
        return "on_draw", outcomes.get("on_draw", {})

    return "on_unknown_or_quit", outcomes.get("on_unknown_or_quit", {})


def validate_post_duel():
    errors = []

    if not SESSION_PATH.exists():
        errors.append(f"Session file not found: {SESSION_PATH}")

    if not RESULT_PATH.exists():
        errors.append(f"WindBot duel result file not found: {RESULT_PATH}")

    if errors:
        result = {
            "loaded": True,
            "valid": False,
            "allow_reward": False,
            "advance_story": False,
            "message": "Post-duel validation failed.",
            "errors": errors
        }
        save_json(POST_RESULT_PATH, result)
        return result

    session = load_json(SESSION_PATH)
    duel_result = load_json(RESULT_PATH)

    session_started_at = parse_datetime(session.get("started_at", ""))
    result_written_at = parse_datetime(duel_result.get("written_at_utc", ""))

    if session_started_at is None:
        errors.append("current_duel_session.json is missing a valid started_at timestamp.")

    if result_written_at is None:
        errors.append("windbot_duel_result.json is missing a valid written_at_utc timestamp.")

    if session_started_at and result_written_at and result_written_at < session_started_at:
        errors.append("Duel result JSON is older than the current duel session.")

    expected_bot_name = str(session.get("windbot_join_name", "")).strip()
    actual_bot_name = str(duel_result.get("bot_name", "")).strip()

    if expected_bot_name and actual_bot_name:
        if not names_match(expected_bot_name, actual_bot_name):
            errors.append(
                f"Bot name mismatch. Expected '{expected_bot_name}', got '{actual_bot_name}'."
            )
    elif expected_bot_name:
        errors.append("Duel result JSON is missing bot_name.")

    expected_deck = str(session.get("windbot_deck", "")).strip()
    expected_deck_file = str(session.get("windbot_deck_file", "")).strip()

    if not expected_deck:
        errors.append("current_duel_session.json is missing windbot_deck.")

    if not expected_deck_file:
        errors.append("current_duel_session.json is missing windbot_deck_file.")

    deck_validation = run_pre_duel_validator_again()

    if not deck_validation.get("valid", False):
        errors.append("Player deck legality failed after duel.")

    outcome_key, outcome_payload = select_outcome(session, duel_result)

    base_valid = len(errors) == 0

    allow_reward = base_valid and bool(outcome_payload.get("allow_reward", False))
    advance_story = base_valid and bool(outcome_payload.get("advance_story", False))

    result = {
        "loaded": True,
        "valid": base_valid,
        "allow_reward": allow_reward,
        "advance_story": advance_story,
        "message": "Post-duel validation passed." if base_valid else "Post-duel validation failed.",
        "errors": errors,
        "outcome_key": outcome_key,
        "outcome": outcome_payload,
        "reward": outcome_payload.get("reward", {}),
        "story_progression": outcome_payload.get("story_progression", {}),
        "session": {
            "session_id": session.get("session_id", ""),
            "npc_id": session.get("npc_id", ""),
            "expected_bot_name": expected_bot_name,
            "expected_windbot_deck": expected_deck,
            "expected_windbot_deck_file": expected_deck_file,
            "session_started_at": session.get("started_at", "")
        },
        "duel_result": duel_result,
        "deck_validation": deck_validation
    }

    save_json(POST_RESULT_PATH, result)
    return result


if __name__ == "__main__":
    output = validate_post_duel()
    print(output.get("message", "Post-duel validation complete."))

    if not output.get("valid", False):
        sys.exit(1)