# YGOStoryGame Architecture

This document explains how YGOStoryGame is structured internally. The project is a Godot JRPG prototype that uses EDOPro as the external Yu-Gi-Oh! duel engine and WindBot as the enemy duelist. Godot owns the RPG layer, while EDOPro owns the actual card-game rules.

## Core Idea

YGOStoryGame is designed like a story RPG with a Pokemon-like progression loop:

```text
Explore world -> talk to NPCs -> complete quests -> earn currency -> unlock cards
-> start story duel -> play duel in EDOPro -> return result to Godot -> continue story
```

The important architectural decision was to not recreate Yu-Gi-Oh! card rules inside Godot. Yu-Gi-Oh! has thousands of cards, complex timing rules, chains, summoning mechanics, banlists, card scripts, and engine-specific behavior. Instead, the prototype uses EDOPro as the duel simulator and builds a custom bridge so the external duel still feels connected to the Godot RPG.

## Main Components

```text
Godot launcher
  RPG world, UI, saves, NPCs, quests, shops, cutscenes, unlocks, music, SFX

GameData JSON
  Data-driven NPCs, dialogue, duel sessions, shops, packs, cutscenes, spawn pools

Python tools
  Bridge between Godot data and EDOPro/WindBot runtime files

EDOPro
  External duel engine, card scripts, decks, databases, banlists, card images

WindBot
  External AI duelist, selected deck, executor DLLs, duel result output
```

## Folder Responsibilities

```text
Launcher/ygo-story-launcher/
  Godot project source.

Launcher/ygo-story-launcher/Scripts/
  Godot gameplay systems and autoload managers.

Launcher/ygo-story-launcher/GameData/configs/
  Hand-authored JSON content for NPCs, dialogue, duels, shops, packs, cutscenes,
  quests, spawn pools, maps, music, and SFX.

Launcher/ygo-story-launcher/GameData/generated/
  Generated card pack data and card cache data created from EDOPro databases.

Launcher/ygo-story-launcher/GameData/save_templates/
  Default new-game save data.

Launcher/ygo-story-launcher/GameData/saves/
  Active save slots used by the prototype.

Launcher/ygo-story-launcher/GameData/runtime/
  Temporary runtime handoff files such as active slot, duel session, validation
  result, post-duel result, and WindBot duel result.

Launcher/ygo-story-launcher/Tools/
  Python helper scripts used for pack generation, deck validation, WindBot
  session setup, duel-result validation, rewards, and banlist generation.

EDOPro/
  Modified EDOPro runtime used by the game.

EDOPro/WindBot/
  Modified WindBot runtime used as the enemy duelist.
```

## Godot Autoload Managers

The Godot project uses autoload managers to keep RPG state and systems available globally.

### ConfigManager

`Scripts/config_manager.gd` is the general JSON loader. It points at:

```text
res://GameData/configs
```

It provides helper methods such as:

```text
get_npc(npc_id)
get_dialogue(dialogue_id)
get_duel_session(duel_session_id)
get_pack_config(pack_id)
get_shop(shop_id)
get_quest(quest_id)
```

The intended pattern is that gameplay scripts ask for content by ID instead of hardcoding all NPCs, quests, shops, or duels directly into scenes.

### SaveManager

`Scripts/save_manager.gd` owns the active save slot and the player's RPG state. It tracks:

- active save slot
- player name
- currency
- inventory
- unlocked cards
- unlocked packs
- story flags
- active and completed quests
- completed quest steps
- dialogue/event progress
- relationships
- ranks
- faction reputation
- current area, spawn point, and player position
- calendar/time state
- reward history

It also creates saves from templates, rotates backups, blocks saving during active duels, and captures the current world state before saving.

### ConditionManager

`Scripts/condition_manager.gd` is the rule checker for data-driven content. JSON entries can include conditions such as:

```json
{
  "required_flags": ["won_intro_duel"],
  "blocked_flags": ["quest_finished"],
  "required_items": [{"item_id": "abandoned_house_1_key", "amount": 1}],
  "required_completed_quests": ["first_steps_duel_academy"],
  "required_relationship_levels": {"axelscorch": 2},
  "time": {
    "enabled": true,
    "allowed_time_of_day": ["night"]
  }
}
```

Dialogue options, NPC duel rules, spawn pools, and other systems use this same condition format so story progression is controlled by save data.

### DialogueManager

`Scripts/dialogue_manager.gd` loads dialogue profiles from:

```text
GameData/configs/dialogue
```

Dialogue JSON can define:

- greetings
- priority-based greeting selection
- talk menu options
- random conversation pools
- dialogue nodes
- choices
- conditions
- effects that happen when text is shown, entered, or selected

For example, a dialogue choice can set story flags, start a quest, remove an item, unlock dialogue, or close the menu. This means the dialogue system is not just text. It is also one of the main story progression systems.

### RewardManager

`Scripts/reward_manager.gd` applies reward bundles to the player save. Rewards can add:

- currency
- items
- cards
- packs
- flags
- quests
- quest steps
- dialogue unlocks
- events
- relationship points
- rank points
- faction reputation
- storyline progress

This same reward shape is reused by dialogue, cutscenes, shops, and duel results.

### UnlockManager

`Scripts/unlock_manager.gd` manages unlocked cards. It updates the active save's `unlocked_cards.json`, unlocks all same-name non-Rush variants of reward cards, and calls the Python banlist generator so EDOPro can reflect the player's unlocked card pool.

The important job of this manager is synchronization: when Godot says the player unlocked cards, the EDOPro side needs to enforce that same progression.

### CutsceneManager

`Scripts/CutsceneManager.gd` loads cutscene JSON from:

```text
GameData/configs/cutscenes
```

A cutscene config can be a PNG slideshow, video cutscene, or in-game cutscene. It can also define:

- `play_once_event` so the cutscene only plays once
- slides with full images
- dialogue slides with speaker names and portraits
- `on_finished` effects that update the save

Example flow:

```text
NPC interaction -> pre_interaction_cutscene -> CutsceneManager
-> PNGCutscenePlayer or VideoCutscenePlayer
-> on_finished flags/effects -> SaveManager.save_game()
```

### MusicManager and SfxManager

`Scripts/MusicManager.gd` reads area-to-music mappings from:

```text
GameData/configs/music/area_music_config.json
```

When `World.gd` loads an area scene, it notifies `MusicManager`, which maps the area scene to a music zone and plays the correct track.

`Scripts/SfxManager.gd` reads sound-effect IDs from:

```text
GameData/configs/SFX/sfx_config.json
```

UI and shop scripts can then play effects by ID, such as `ui_confirm` or `success`.

### NpcSpawnManager

`Scripts/NpcSpawnManager.gd` reads spawn pool configs from:

```text
GameData/configs/spawn_pools
```

Spawn pools can be condition-based, weighted, daily, or flag-driven. They decide which NPCs appear in which areas and at which coordinates. The selected NPC location is saved in `SaveManager` under `npc_locations`, so NPC placement can persist across area loads.

`Scripts/World/AreaNpcSpawner.gd` asks `NpcSpawnManager` for the spawn entries for the current area, loads the NPC scenes, places them at configured coordinates, and sets their facing direction.

## JSON Content Architecture

Most content is data-driven. The Godot scripts provide generic behavior, while JSON files define the actual game content.

### NPC Configs

NPC configs live in:

```text
GameData/configs/npcs
```

An NPC config can define:

- `npc_id`
- display name
- portrait paths
- default facing direction
- interaction options such as Talk, Trade, Duel
- shop scene path
- duel rules
- pre-interaction cutscene
- spawn pool ID

The NPC script loads its config ID, then uses that JSON to decide what the NPC can do. For example, `ash.json` defines Talk and Duel options and contains `duel_rules` that choose between a first duel and a rematch depending on story flags.

### Dialogue Configs

Dialogue configs live in:

```text
GameData/configs/dialogue
```

The dialogue profile links to an NPC through `dialogue_profile_id`. It can define several greeting entries with priorities and conditions. The highest-priority valid greeting is shown first.

Dialogue nodes support choices. Choices can point to another node, return to the talk menu, close the menu, trigger a duel, teleport the player, or apply effects to the save.

### Condition Blocks

Several config types use the same condition format:

- dialogue greetings
- dialogue options
- dialogue choices
- NPC duel rules
- NPC spawn pools
- cutscene triggers
- shop/pack unlock logic

This is one of the main design strengths of the project. Story state is centralized in the save file, and JSON content reacts to that state using reusable conditions.

### Shop Configs

Shop configs live in:

```text
GameData/configs/shop_configs
```

A shop config defines:

- shop ID
- shop display name
- UI art paths
- currency icon
- locked icon
- list of pack IDs sold by the shop

`Scripts/card_shop.gd` loads a shop config, then loads each generated pack JSON listed in the shop. The shop UI previews pack art, cost, description, locked message, and purchase state.

### Pack Configs and Generated Packs

Pack source configs live in:

```text
GameData/configs/pack_configs
```

Generated pack outputs live in:

```text
GameData/generated/packs
```

The source pack config is the design-time file. It defines:

- pack ID
- display name
- description
- cost
- cards per opening
- pack art
- unlock flag
- target setcodes
- manually included card names or IDs
- reward-only cards
- excluded names
- excluded source keywords such as Rush or Skill cards
- card weights

The Python pack generation scripts read EDOPro card databases and produce generated pack JSON with a concrete `card_pool`. The Godot shop opens the generated pack, not the source config.

Pack-opening flow:

```text
CardShop scene
  -> load shop config
  -> load generated pack JSON
  -> player buys pack with currency
  -> weighted card pull
  -> UnlockManager.unlock_reward_cards()
  -> update unlocked_cards.json
  -> regenerate StoryMode banlist
  -> SaveManager.save_game()
```

### Cutscene Configs

Cutscene configs live in:

```text
GameData/configs/cutscenes
```

They support slide-based image scenes, dialogue slides, and finish effects. A cutscene can set flags such as `orichalcos_mission_1_intro_seen` or unlock the next duel flag when it finishes.

### Duel Session Configs

Duel session configs live in:

```text
GameData/configs/duel_sessions
```

An NPC does not directly launch a hardcoded deck. Instead:

```text
NPC config -> duel_rules -> duel_session_id -> duel session JSON
```

A duel session config is intended to define:

- session ID
- NPC ID
- display name
- WindBot name/deck/deck file
- port/version settings
- player deck source
- outcome behavior for win/loss/draw/quit
- reward and story effects

Prototype note: some duel-session files show an earlier `rewards` schema, while later Python tools read an `outcomes` schema. That mismatch is one of the release-cleanup items and part of why the current project is documented as unfinished.

## World and Area Flow

The world scene uses `Scripts/World/World.gd`.

Startup flow:

```text
Main menu
  -> SaveManager chooses active or most recent save slot
  -> World.gd loads the saved area scene if one exists
  -> otherwise it loads the configured starting area
  -> player is placed at saved position or named spawn point
  -> MusicManager plays music for the loaded area
  -> SaveManager stores current area, spawn, and position
```

The player uses `Scripts/Player/PlayerController.gd` for movement. It handles walking, sprinting, and animation direction.

Area transitions are handled by area/door scripts. When a new area is loaded, the player is reparented into the new area's `YSortObjects` node so depth sorting works correctly.

## NPC Interaction Flow

Typical NPC interaction:

```text
Player presses interact near NPC
  -> NPC loads its config
  -> optional pre-interaction cutscene plays
  -> NPCInteractionMenu opens
  -> DialogueManager loads dialogue profile
  -> ConditionManager filters valid options
  -> player chooses Talk, Trade, or Duel
```

Talk:

```text
NPCInteractionMenu
  -> DialogueManager.get_talk_options()
  -> DialogueManager.get_dialogue_node()
  -> choice effects update SaveManager state
```

Trade:

```text
NPC config shop option
  -> loads shop scene
  -> CardShop loads shop config
  -> player buys generated packs
```

Duel:

```text
NPC config duel_rules
  -> highest-priority valid rule selected
  -> duel_session_id passed to duel prompt
```

## Duel Integration Flow

The duel flow is the most complex part of the prototype because it crosses from Godot into Python, EDOPro, and WindBot.

### 1. NPC Chooses Duel Session

An NPC config contains `duel_rules`. Each rule has conditions and a priority. The NPC script chooses the highest-priority valid rule and returns the `duel_session_id`.

Example:

```text
ash.json
  -> ash_first_duel if required flags are met and won_ash_first_duel is not set
  -> ash_rematch_duel after won_ash_first_duel is set
```

### 2. Godot Opens Duel Prompt

`Scripts/duel_prompt_prototype.gd` receives the duel session ID and pauses the game. If the player accepts the duel, it starts the bridge pipeline.

### 3. Python Prepares WindBot

`Tools/prepare_windbot_session.py`:

- loads the duel session JSON
- writes `GameData/runtime/current_duel_session.json`
- finds the EDOPro/WindBot folder
- backs up `EDOPro/WindBot/bots.json`
- backs up the full `EDOPro/WindBot/Decks` folder
- clears the live WindBot deck folder
- copies in only the selected enemy deck
- rewrites `bots.json` so WindBot exposes the selected story opponent
- records session timestamps and status

This made WindBot behave like it had a story-specific opponent selected from Godot.

### 4. Python Validates Player Decks

`Tools/pre_duel_validate.py`:

- reads the active save's `unlocked_cards.json`
- scans EDOPro `.cdb` card databases with SQLite
- reads all player `.ydk` decks from `EDOPro/deck`
- checks every card ID in the decks
- blocks the duel if the deck contains locked cards
- blocks the duel if the card is missing from the EDOPro databases
- writes `GameData/runtime/validation_result.json`

This is the key progression bridge: Godot card unlocks control whether the player's EDOPro deck is legal.

### 5. Godot Launches EDOPro

After validation passes, Godot starts:

```text
EDOPro/EDOPro.exe
```

The player then hosts a LAN room in EDOPro. The Godot prompt watches port `7911` until the room is detected.

### 6. Python Launches WindBot

`Tools/launch_windbot_from_session.py` starts:

```text
EDOPro/WindBot/WindBot.exe
```

It passes WindBot arguments such as:

- selected deck
- port
- EDOPro version
- bot display name
- asset path

WindBot then joins the hosted room as the enemy duelist.

### 7. Godot Waits For EDOPro To Close

Godot monitors the EDOPro process. When the duel window closes, the post-duel pipeline starts.

### 8. Python Validates Duel Result

`Tools/post_duel_validate.py`:

- reads `current_duel_session.json`
- reads `windbot_duel_result.json`
- checks that the result belongs to the current session
- checks timestamps
- checks expected bot name and deck data
- runs deck validation again
- selects the matching outcome for player win, player loss, draw, or unknown result
- writes `post_duel_validation_result.json`

### 9. Python Applies Rewards

`Tools/apply_duel_rewards.py`:

- reads `post_duel_validation_result.json`
- refuses rewards if validation failed
- opens the active `player_save.json`
- adds currency, items, cards, packs, flags, quests, dialogue unlocks, events, relationship points, ranks, faction reputation, and story progress
- records the result in reward history
- writes the save back to disk

### 10. Python Restores WindBot

`Tools/restore_windbot_session.py` restores:

- original `bots.json`
- original `Decks` folder
- session status

This protects the modified WindBot folder from being permanently overwritten by a single story duel setup.

## Card Unlock and Banlist Flow

The game has two related card-progression systems:

1. Godot save data tracks which cards the player has unlocked.
2. EDOPro needs a way to prevent locked cards from being used.

The prototype handles this with validation and generated banlists.

`Tools/extract_cdb_cards.py` scans EDOPro `.cdb` files and creates:

```text
GameData/generated/card_cache.json
GameData/save_templates/default_new_game/unlocked_cards.json
```

`Tools/generate_pack_from_config.py` uses `card_cache.json` and pack configs to build generated pack JSON.

`Tools/generate_story_banlist.py`:

- reads the active save's unlocked cards
- scans all EDOPro card databases
- reads a reference TCG lflist
- creates `StoryMode.lflist.conf`
- marks locked cards as forbidden
- keeps official restrictions for unlocked cards

This is how RPG progression is translated into duel-engine restrictions.

## Runtime Handoff Files

Important files used to communicate between systems:

```text
GameData/runtime/active_save_slot.json
  Current save slot, such as slot_1, slot_2, or slot_3.

GameData/runtime/current_duel_session.json
  The active duel session selected by Godot and prepared by Python.

GameData/runtime/validation_result.json
  Pre-duel deck legality result.

GameData/runtime/windbot_duel_result.json
  Duel result written by modified WindBot.

GameData/runtime/post_duel_validation_result.json
  Final checked result used before rewards are applied.
```

## Why WindBot AI Became The Blocker

The Godot RPG systems and EDOPro bridge were possible, but enemy AI quality became the stopping point.

WindBot can use deck-specific executor DLLs. These executors are C#/.NET AI modules that tell the bot how to play a deck: which cards to activate, when to combo, what to summon, what to prioritize, and how to respond to the board. For a story RPG with many opponents and many archetypes, each enemy deck would need its own reliable executor to feel good.

A generic AI was not strong enough, and writing custom executors for every deck was too slow for a solo prototype. This is why the project was paused even though the broader integration architecture had been built.
