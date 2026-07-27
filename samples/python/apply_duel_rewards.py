import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from project_paths import (
    POST_DUEL_VALIDATION_RESULT_PATH,
    get_player_save_path
)

POST_RESULT_PATH = POST_DUEL_VALIDATION_RESULT_PATH
PLAYER_SAVE_PATH = get_player_save_path()


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)

    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)


def ensure_dict(data, key):
    if key not in data or not isinstance(data[key], dict):
        data[key] = {}

    return data[key]


def load_player_save():
    if not PLAYER_SAVE_PATH.exists():
        return {
            "currency": 0,
            "opened_packs": {},
            "story_flags": {},
            "unlocked_packs": {},
            "inventory": {},
            "unlocked_cards": {},
            "active_quests": {},
            "completed_quests": {},
            "quest_steps_completed": {},
            "unlocked_dialogues": {},
            "triggered_events": {},
            "relationships": {},
            "rank_points": 0,
            "player_rank": "",
            "ranks": {},
            "faction_reputation": {},
            "storyline_progress": {},
            "reward_history": []
        }

    data = load_json(PLAYER_SAVE_PATH)

    data.setdefault("currency", 0)
    data.setdefault("opened_packs", {})
    data.setdefault("story_flags", {})
    data.setdefault("unlocked_packs", {})
    data.setdefault("inventory", {})
    data.setdefault("unlocked_cards", {})
    data.setdefault("active_quests", {})
    data.setdefault("completed_quests", {})
    data.setdefault("quest_steps_completed", {})
    data.setdefault("unlocked_dialogues", {})
    data.setdefault("triggered_events", {})
    data.setdefault("relationships", {})
    data.setdefault("rank_points", 0)
    data.setdefault("player_rank", "")
    data.setdefault("ranks", {})
    data.setdefault("faction_reputation", {})
    data.setdefault("storyline_progress", {})
    data.setdefault("reward_history", [])

    return data


def add_items(player_save, items, applied):
    inventory = ensure_dict(player_save, "inventory")

    for item in items:
        if isinstance(item, dict):
            item_id = str(item.get("item_id", "")).strip()
            amount = int(item.get("amount", 1))
        else:
            item_id = str(item).strip()
            amount = 1

        if not item_id:
            continue

        inventory[item_id] = int(inventory.get(item_id, 0)) + amount
        applied["items_added"][item_id] = applied["items_added"].get(item_id, 0) + amount


def unlock_cards(player_save, cards, applied):
    unlocked_cards = ensure_dict(player_save, "unlocked_cards")

    for card in cards:
        if isinstance(card, dict):
            card_id = str(card.get("card_id", card.get("id", ""))).strip()
            card_name = str(card.get("name", "Unknown Card")).strip()
        else:
            card_id = str(card).strip()
            card_name = "Unknown Card"

        if not card_id:
            continue

        unlocked_cards[card_id] = card_name
        applied["cards_unlocked"][card_id] = card_name


def unlock_packs(player_save, pack_ids, applied):
    unlocked_packs = ensure_dict(player_save, "unlocked_packs")

    for pack_id in pack_ids:
        pack_id = str(pack_id).strip()

        if not pack_id:
            continue

        unlocked_packs[pack_id] = True
        applied["packs_unlocked"].append(pack_id)


def set_flags(player_save, flags, applied):
    story_flags = ensure_dict(player_save, "story_flags")

    for flag in flags:
        flag = str(flag).strip()

        if not flag:
            continue

        story_flags[flag] = True
        applied["flags_set"][flag] = True


def remove_flags(player_save, flags, applied):
    story_flags = ensure_dict(player_save, "story_flags")

    for flag in flags:
        flag = str(flag).strip()

        if not flag:
            continue

        if flag in story_flags:
            del story_flags[flag]

        applied["flags_removed"].append(flag)


def start_quests(player_save, quest_ids, applied):
    active_quests = ensure_dict(player_save, "active_quests")

    for quest_id in quest_ids:
        quest_id = str(quest_id).strip()

        if not quest_id:
            continue

        active_quests[quest_id] = {
            "status": "active",
            "started_at_utc": datetime.now(timezone.utc).isoformat()
        }

        applied["quests_started"].append(quest_id)


def complete_quests(player_save, quest_ids, applied):
    active_quests = ensure_dict(player_save, "active_quests")
    completed_quests = ensure_dict(player_save, "completed_quests")

    for quest_id in quest_ids:
        quest_id = str(quest_id).strip()

        if not quest_id:
            continue

        completed_quests[quest_id] = {
            "status": "completed",
            "completed_at_utc": datetime.now(timezone.utc).isoformat()
        }

        if quest_id in active_quests:
            del active_quests[quest_id]

        applied["quests_completed"].append(quest_id)


def complete_quest_steps(player_save, quest_steps, applied):
    quest_steps_completed = ensure_dict(player_save, "quest_steps_completed")

    for entry in quest_steps:
        entry = str(entry).strip()

        if not entry:
            continue

        quest_steps_completed[entry] = True
        applied["quest_steps_completed"].append(entry)


def unlock_dialogues(player_save, dialogue_ids, applied):
    unlocked_dialogues = ensure_dict(player_save, "unlocked_dialogues")

    for dialogue_id in dialogue_ids:
        dialogue_id = str(dialogue_id).strip()

        if not dialogue_id:
            continue

        unlocked_dialogues[dialogue_id] = True
        applied["dialogues_unlocked"].append(dialogue_id)


def trigger_events(player_save, event_ids, applied):
    triggered_events = ensure_dict(player_save, "triggered_events")

    for event_id in event_ids:
        event_id = str(event_id).strip()

        if not event_id:
            continue

        triggered_events[event_id] = {
            "triggered": True,
            "triggered_at_utc": datetime.now(timezone.utc).isoformat()
        }

        applied["events_triggered"].append(event_id)


def add_relationship_points(player_save, relationship_points, applied):
    relationships = ensure_dict(player_save, "relationships")

    if not isinstance(relationship_points, dict):
        return

    for npc_id, points in relationship_points.items():
        npc_id = str(npc_id).strip()

        if not npc_id:
            continue

        points = int(points)

        if npc_id not in relationships or not isinstance(relationships[npc_id], dict):
            relationships[npc_id] = {
                "points": 0,
                "level": 0
            }

        relationships[npc_id]["points"] = int(relationships[npc_id].get("points", 0)) + points
        applied["relationship_points_added"][npc_id] = (
            applied["relationship_points_added"].get(npc_id, 0) + points
        )


def apply_rank_reward(player_save, reward, applied):
    rank_points = int(reward.get("rank_points", 0))

    if rank_points > 0:
        player_save["rank_points"] = int(player_save.get("rank_points", 0)) + rank_points
        applied["rank_points_added"] = rank_points

    new_rank = str(reward.get("set_player_rank", "")).strip()

    if new_rank:
        player_save["player_rank"] = new_rank
        applied["player_rank_set"] = new_rank

    ranks = ensure_dict(player_save, "ranks")
    rank_updates = reward.get("set_ranks", {})

    if isinstance(rank_updates, dict):
        for rank_group, rank_value in rank_updates.items():
            rank_group = str(rank_group).strip()
            rank_value = str(rank_value).strip()

            if not rank_group or not rank_value:
                continue

            ranks[rank_group] = rank_value
            applied["ranks_set"][rank_group] = rank_value


def apply_faction_reward(player_save, reward, applied):
    faction_reputation = ensure_dict(player_save, "faction_reputation")
    faction_updates = reward.get("faction_reputation", {})

    if not isinstance(faction_updates, dict):
        return

    for faction_id, points in faction_updates.items():
        faction_id = str(faction_id).strip()

        if not faction_id:
            continue

        points = int(points)
        faction_reputation[faction_id] = int(faction_reputation.get(faction_id, 0)) + points
        applied["faction_reputation_added"][faction_id] = (
            applied["faction_reputation_added"].get(faction_id, 0) + points
        )


def apply_storyline_progress(player_save, outcome, applied):
    storyline_progress = ensure_dict(player_save, "storyline_progress")
    updates = outcome.get("storyline_progress", {})

    if not isinstance(updates, dict):
        return

    for storyline_id, value in updates.items():
        storyline_id = str(storyline_id).strip()

        if not storyline_id:
            continue

        storyline_progress[storyline_id] = value
        applied["storyline_progress_set"][storyline_id] = value


def apply_legacy_story_progression(player_save, story_progression, applied):
    if not isinstance(story_progression, dict):
        return

    completed_node = str(story_progression.get("completed_node", "")).strip()
    next_node = str(story_progression.get("next_node", "")).strip()
    chapter_id = str(story_progression.get("chapter_id", "")).strip()

    legacy_flags = []

    if chapter_id:
        legacy_flags.append(f"chapter.{chapter_id}.started")

    if completed_node:
        legacy_flags.append(f"story.node.{completed_node}.completed")

    if next_node:
        legacy_flags.append(f"story.node.{next_node}.unlocked")

    set_flags(player_save, legacy_flags, applied)


def reward_once_already_claimed(player_save, post_result):
    story_flags = ensure_dict(player_save, "story_flags")
    session_data = post_result.get("session", {})

    if not isinstance(session_data, dict):
        return False

    repeat_rules = session_data.get("repeat_rules", {})

    if not isinstance(repeat_rules, dict):
        return False

    reward_once_flags = repeat_rules.get("reward_once_flags", [])

    if not isinstance(reward_once_flags, list):
        return False

    for flag in reward_once_flags:
        flag = str(flag).strip()

        if not flag:
            continue

        if bool(story_flags.get(flag, False)):
            return True

    return False


def apply_duel_rewards():
    if not POST_RESULT_PATH.exists():
        raise FileNotFoundError(
            f"Missing post-duel validation result: {POST_RESULT_PATH}"
        )

    post_result = load_json(POST_RESULT_PATH)

    if not post_result.get("valid", False):
        raise RuntimeError("Post-duel validation failed. Reward blocked.")

    player_save = load_player_save()

    reward = post_result.get("reward", {})
    outcome = post_result.get("outcome", {})
    story_progression = post_result.get("story_progression", {})

    if not isinstance(reward, dict):
        reward = {}

    if not isinstance(outcome, dict):
        outcome = {}

    reward_already_claimed = reward_once_already_claimed(player_save, post_result)

    applied = {
        "currency_added": 0,
        "items_added": {},
        "cards_unlocked": {},
        "packs_unlocked": [],
        "flags_set": {},
        "flags_removed": [],
        "quests_started": [],
        "quests_completed": [],
        "quest_steps_completed": [],
        "dialogues_unlocked": [],
        "events_triggered": [],
        "relationship_points_added": {},
        "rank_points_added": 0,
        "player_rank_set": "",
        "ranks_set": {},
        "faction_reputation_added": {},
        "storyline_progress_set": {},
        "reward_once_already_claimed": reward_already_claimed
    }

    if post_result.get("allow_reward", False) and not reward_already_claimed:
        currency = int(reward.get("currency", 0))

        if currency > 0:
            player_save["currency"] = int(player_save.get("currency", 0)) + currency
            applied["currency_added"] = currency

        add_items(player_save, reward.get("items", []), applied)
        unlock_cards(player_save, reward.get("cards", []), applied)
        unlock_packs(player_save, reward.get("unlock_packs", []), applied)
        add_relationship_points(player_save, reward.get("relationship_points", {}), applied)
        apply_rank_reward(player_save, reward, applied)
        apply_faction_reward(player_save, reward, applied)

    set_flags(player_save, outcome.get("set_flags", []), applied)
    remove_flags(player_save, outcome.get("remove_flags", []), applied)
    start_quests(player_save, outcome.get("start_quests", []), applied)
    complete_quests(player_save, outcome.get("complete_quests", []), applied)
    complete_quest_steps(player_save, outcome.get("complete_quest_steps", []), applied)
    unlock_dialogues(player_save, outcome.get("unlock_dialogue_ids", []), applied)
    trigger_events(player_save, outcome.get("trigger_event_ids", []), applied)
    apply_storyline_progress(player_save, outcome, applied)

    if post_result.get("advance_story", False):
        apply_legacy_story_progression(player_save, story_progression, applied)

    player_save["reward_history"].append({
        "applied_at_utc": datetime.now(timezone.utc).isoformat(),
        "session_id": post_result.get("session", {}).get("session_id", ""),
        "npc_id": post_result.get("session", {}).get("npc_id", ""),
        "outcome_key": post_result.get("outcome_key", ""),
        "allow_reward": post_result.get("allow_reward", False),
        "advance_story": post_result.get("advance_story", False),
        "reward_once_already_claimed": reward_already_claimed,
        "applied": applied
    })

    save_json(PLAYER_SAVE_PATH, player_save)

    print(json.dumps({
        "valid": True,
        "message": "Duel reward application complete.",
        "new_currency_total": player_save["currency"],
        "applied": applied
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        apply_duel_rewards()

    except Exception as error:
        print(f"apply_duel_rewards.py failed: {error}")
        sys.exit(1)