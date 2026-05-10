# Dirgantara

> *"Fly together. Light the sky."*

A cooperative sky-world exploration game on Roblox. Players become Children of the Sky — luminous beings who fly through voxel realms, collect light, free lost spirits, and form bonds with other players. Inspired by *Sky: Children of the Light*, rebuilt ground-up for Roblox with a voxel/block art aesthetic.

**Genre:** Social Exploration / Adventure  
**Engine:** Roblox  
**Art Style:** Voxel / Block Art  
**Target Audience:** Ages 10–24, casual to social gamers  
**Developer:** [404 Not Found Indonesia](mailto:iqbaleff214@gmail.com)

---

## Table of Contents

- [Overview](#overview)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Architecture](#architecture)
  - [Server Services](#server-services)
  - [Client Controllers](#client-controllers)
  - [Shared Modules](#shared-modules)
- [Core Systems](#core-systems)
- [Realms](#realms)
- [Economy & Currencies](#economy--currencies)
- [Localization](#localization)
- [Implementation Progress](#implementation-progress)
- [License](#license)

---

## Overview

Dirgantara's core loop:

```
Fly → Collect Cahaya → Find Spirits → Unlock Rewards → Bond with Players → Reach Sky's Peak
```

There is no combat. Tension comes from **Kegelapan** (darkness zones) that drain light and force cooperation. The endgame — **Puncak Langit (Sky's Peak)** — consumes all Cahaya but yields powerful rewards and resets the journey without resetting cosmetics.

**Four Design Pillars:**

| Pillar | Description |
|---|---|
| **Exploration** | Hand-crafted voxel worlds with secrets, puzzles, and vertical space |
| **Social** | Cooperation is rewarded — helping others gives light |
| **Progression** | Wings grow stronger; cosmetics unlock; bonds deepen |
| **Mastery** | Skilled fliers reach hidden areas; endgame is repeatable and meaningful |

---

## Tech Stack

| Tool | Purpose |
|---|---|
| **Roblox Studio** | Game engine and editor |
| **Luau** (`--!strict`) | Scripting language (all files are strict-typed) |
| **Rojo** | File-system sync to Roblox Studio via `default.project.json` |
| **Wally** | Package manager (`wally.toml`) |
| **Selene** | Luau static analysis linter (`selene.toml`) |
| **TestEZ** | Unit test framework |

**Wally dependencies:**

| Package | Version | Use |
|---|---|---|
| `evaera/promise` | 4.0.0 | Async operations |
| `sleitnick/signal` | 2.0.3 | Custom events |
| `sleitnick/component` | 2.4.8 | Component pattern for game objects |
| `flamenco687/maid` | 3.2.2 | Cleanup / lifecycle management |
| `osyrisrblx/t` | 3.1.1 | Runtime type checking |
| `roblox/testez` | 0.4.1 | Unit testing |

---

## Project Structure

```
dirgantara/
├── default.project.json     # Rojo project config
├── wally.toml               # Package manifest
├── selene.toml              # Linter config
├── GDD.md                   # Game Design Document
├── PRD.md                   # Product Requirements Document
├── TASKS.md                 # Technical task breakdown (122/144 complete)
├── Packages/                # Wally client-side packages
├── ServerPackages/          # Wally server-side packages
└── src/
    ├── server/
    │   ├── init.server.luau         # Bootstrap: service init + player lifecycle
    │   ├── Services/                # All server-side game systems
    │   └── NPC/                     # Naga Gelap AI scripts
    ├── client/
    │   ├── init.client.luau         # Bootstrap: controller start
    │   ├── Controllers/             # Client-side game controllers
    │   └── UI/                      # UI panels and components
    └── shared/
        ├── Types.luau               # All exported Luau types
        ├── Constants.luau           # All tuning constants
        ├── Remotes.luau             # Remote event/function declarations
        └── *Defs.luau               # Static data tables (realms, spirits, wings, etc.)
```

**Rojo mapping:**

| Source path | Roblox location |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |
| `Packages/` | `ReplicatedStorage.Packages` |
| `ServerPackages/` | `ServerScriptService.ServerPackages` |
| `src/assets/` | `ReplicatedStorage.Assets` |

---

## Getting Started

**Prerequisites:** Roblox Studio, [Rojo](https://rojo.space), [Wally](https://wally.run)

```bash
# 1. Clone the repository
git clone <repo-url>
cd dirgantara

# 2. Install Wally packages
wally install

# 3. Start Rojo server
rojo serve default.project.json

# 4. In Roblox Studio, connect via the Rojo plugin
```

**Linting:**
```bash
selene src/
```

**Tests** run inside Roblox Studio using TestEZ. Test files live in `src/server/Services/__tests__/` and `src/shared/__tests__/`.

---

## Architecture

All server/client communication goes through typed remote events declared in `shared/Remotes.luau`. No service reads from another service's internal state — cross-service calls go through each service's public API. Circular dependencies are broken with lazy-require:

```lua
local _DataService: any = nil
local function getDS(): any
    if not _DataService then
        _DataService = require(script.Parent.DataService)
    end
    return _DataService
end
```

### Server Services

| Service | Responsibility |
|---|---|
| `DataService` | Player data load/save, DataStore retries, daily reset, auto-save loop, safe teleport |
| `CahayaService` | Orb collection, daily cap, Cahaya sync, Roblox Premium bonus |
| `WingService` | Wing level upgrades, Awan XP/rank, realm entry gate, join sync |
| `FlightService` | Server-authoritative wing charge state, boost validation |
| `KegelapanService` | Darkness zone drain, extinguish/revive, Naga Gelap trigger |
| `IkatanService` | Bond offer/accept/decline, teleport, cross-server presence (MemoryStore), cosmetic gifting |
| `SpiritService` | Ancestor/Season/Daily spirit freeing, fragment collection, Galeri Roh |
| `DailyTaskService` | Daily task generation, progress tracking, milestone rewards, login streak |
| `SeasonService` | Active season config, season pass gating, Koin Musim shop, season quest chain |
| `SkysPeakService` | Sky's Peak run lifecycle, Cahaya sacrifice, wing cycle reward |
| `InstrumentService` | Instrument play broadcast to nearby clients, Harmoni aura |
| `EmoteService` | Emote validation, sync emote handshake, Awan XP award |
| `CosmeticService` | Item grant/equip/unequip, loadout persistence, fragment combine |
| `MonetizationService` | ProcessReceipt, pending grants for offline purchases, Roblox Premium flag |
| `LocalizationService` | Server-side LocalizationTable setup in ReplicatedStorage |

### Client Controllers

| Controller | Responsibility |
|---|---|
| `FlightController` | Client-side flight input, charge bar UI, boost visual feedback |
| `CameraController` | Third-person orbit, auto-follow, mobile swipe-look |
| `InputController` | Unified input abstraction across PC / mobile / console |
| `UIController` | UI scale, translate(), RTL layout helpers (applyLayout, flipAnchorX) |
| `EmoteController` | Emote wheel input, sync emote state machine |
| `InstrumentController` | Instrument mode UI, note input, strum detection |
| `CosmeticController` | Loadout apply to character, wing skin, trail/aura attachment |
| `CompanionController` | Season spirit companion follow behavior |
| `NagaController` | Client-side Naga Gelap visual reactions (not AI — server owns AI) |
| `AudioController` | Adaptive ambient music, spatial instrument audio, realm transitions |

### Shared Modules

| Module | Contents |
|---|---|
| `Types.luau` | All Luau type exports (`PlayerData`, `WingDef`, `SpiritDef`, etc.) |
| `Constants.luau` | All numeric/string constants and tuning values |
| `Remotes.luau` | All `RemoteEvent` / `RemoteFunction` declarations |
| `WingDefs.luau` | Wing level definitions (cost, charge segments, unlock gates) |
| `RealmDefs.luau` | Realm configs (placeId, minWingLevel, kegelapan zone count) |
| `SpiritDefs.luau` | Ancestor, Season, and Daily spirit definitions |
| `CosmeticDefs.luau` | All cosmetic item definitions (rarity, category, source) |
| `DailyTaskDefs.luau` | Task pool definitions (Easy / Medium / Hard) |
| `SeasonDefs.luau` | Season config (dates, spirits, quest chain, Musim shop) |
| `LocalizationData.luau` | All localized string entries for the LocalizationTable |
| `RetryAsync.luau` | DataStore retry wrapper with configurable attempts and delay |
| `Format.luau` | Locale-aware number and countdown formatters |
| `Fonts.luau` | Font asset IDs by locale (Latin / CJK / Arabic) |
| `Assets.luau` | Central asset ID registry (sounds, particles, models) |

---

## Core Systems

### Flight

Wings are the primary locomotion. All players fly. The **charge bar** (3–5 segments by wing level) is consumed per boost and refills by walking, standing near higher-level players, or collecting Cahaya orbs. Wing Level 4+ players can carry one other player (2× charge cost). Server validates wing charge state — clients cannot self-grant boosts.

### Cahaya (Light)

Dual role: resource and health. Collected from world orbs (150/day cap), freed spirits, and social actions. **Kegelapan zones** drain ~1 Cahaya per 3 seconds. Reaching 0 extinguishes the player (dims cape, disables flight). Any nearby player can revive by pressing interact (costs the rescuer 1 Cahaya).

### Ikatan (Bond)

Core social mechanic. Two players in proximity exchange a hand-offer. On accept: bidirectional bond recorded, +2 Cahaya Hati awarded each. Benefits: minimap glow, cross-server teleport (30-min cooldown), shared Harmoni aura radius, cosmetic gifting. Max 30 bonds. Presence tracked via MemoryStore (TTL 60s, refresh every 45s); cross-server departure detected within one TTL window.

### Kegelapan & Naga Gelap

Server defines darkness zones via Region3. **Naga Gelap** (AI): patrols zone, detects nearby high-Cahaya players, transitions to chase. No combat — stealth only (extinguish your light to hide). Server owns all AI state; client receives visual cues via remotes.

### Sky's Peak

Endgame prestige loop. Requires Wing Level 5+. At the summit, player sacrifices all Cahaya → wing cycle count increments → **Sayap Lencana** cosmetic awarded. Cosmetics are never reset. Each cycle earns +3 Cahaya Hati.

### Daily Tasks

5 tasks per day (3 Easy, 1 Medium, 1 Hard), generated server-side from a pool at first login after UTC+7 midnight. Milestone rewards at 1/2/3/4/5 completions. Weekly (5/7 Full Clears) and Monthly (3/4 weeks) milestones on top. Separate daily login streak with 1-day grace per 30 consecutive days (max 3 grace days banked).

### Seasons

~10-week seasons. Each adds a seasonal realm extension, 5–7 Season Spirits with story vignettes, a Season Quest chain, and a Musim Pass (499 R$) / Musim Pass+ (899 R$). Free players earn Koin Musim from daily tasks to buy seasonal cosmetics from the Musim Shop.

---

## Realms

| # | Realm | Minimum Wing Level |
|---|---|---|
| 1 | Isle of Dawn *(Pulau Fajar)* | 1 (starting area) |
| 2 | Grassland of Whispers *(Padang Bisikan)* | 1 |
| 3 | Forest of Echoes *(Hutan Gaung)* | 2 |
| 4 | Valley of Triumph *(Lembah Kejayaan)* | 4 |
| 5 | Wasteland of Bone *(Tanah Tandus)* | 6 |
| 6 | Vault of Knowledge *(Kubah Pengetahuan)* | 8 |
| 7 | Sky's Peak *(Puncak Langit)* | 10 |

Each realm is a separate Roblox Place. `DataService.safeTeleport` saves player data (3s timeout) before any inter-realm teleport. Under-leveled players arriving at a realm are detected in `WingService.init` and bounced back to Hub.

---

## Economy & Currencies

| Currency | Earn | Spend | Robux? |
|---|---|---|---|
| **Cahaya** | World orbs, tasks, spirits | (converted to Cahaya Hati via social) | No |
| **Cahaya Hati** | Social actions, tasks, Sky's Peak | Wing level upgrades | No |
| **Koin Musim** | Daily tasks, season quests | Musim Shop seasonal items | No |
| **Bintang Hati** | Ikatan milestones | Gift to Ikatan partners | No |
| **Robux** | Real money | Musim Pass, cosmetic bundles, Starter Pack | — |

No pay-to-win. Cahaya, wing levels, and realm access cannot be purchased with Robux.

**Roblox Premium perks:** +10% orb Cahaya, +10 Cahaya daily login bonus, exclusive monthly cosmetic frame.

---

## Localization

Strings go through `LocalizationService` → `LocalizationTable` in `ReplicatedStorage`. All player-facing text uses `UIController.translate(key, params)` — no hardcoded strings in UI or scripts.

**Tier 1 (launch):** English (`en`), Indonesian (`id`), Japanese (`ja`), Arabic (`ar`), Chinese Simplified (`zh-cn`)  
**Tier 2 (Season 1):** Traditional Chinese, Korean, Portuguese (Brazil), Spanish, French, German

Key format: `CATEGORY_SUBCATEGORY_KEY` with named parameters: `"Reach Wing Level {level} to enter this realm."`

Arabic (`ar`) requires full RTL layout. `UIController.applyLayout(layout)` flips `HorizontalAlignment`; `UIController.flipAnchorX(element)` mirrors `AnchorPoint.X`. A `LayoutDirection` value in `ReplicatedStorage` drives all UI components.

---

## Implementation Progress

| Phase | Tasks | Done |
|---|---|---|
| Phase 0 — Foundation | T-001 → T-013 | 0 / 15 |
| Phase 1 — Data Layer | T-014 → T-018 | 0 / 5 |
| Phase 2 — Flight | T-019 → T-025 | 0 / 7 |
| Phase 3 — Cahaya | T-026 → T-031 | 0 / 6 |
| Phase 4 — Wings | T-032 → T-035 | 0 / 4 |
| Phase 5 — Kegelapan | T-036 → T-040 | 5 / 5 |
| Phase 6 — Naga Gelap AI | T-041 → T-045 | 5 / 5 |
| Phase 7 — Ikatan | T-046 → T-050 | 5 / 5 |
| Phase 8 — Spirits | T-051 → T-057 | 7 / 7 |
| Phase 9 — Daily Tasks | T-058 → T-063 | 6 / 6 |
| Phase 10 — Seasons | T-064 → T-069 | 6 / 6 |
| Phase 11 — Instruments | T-070 → T-074 | 5 / 5 |
| Phase 12 — Emotes | T-075 → T-079 | 5 / 5 |
| Phase 13 — Cosmetics | T-080 → T-085 | 6 / 6 |
| Phase 14 — Sky's Peak | T-086 → T-089 | 4 / 4 |
| Phase 15 — UI Layer | T-090 → T-101 | 12 / 12 |
| Phase 16 — Input | T-102 → T-104 | 3 / 3 |
| Phase 17 — Audio | T-105 → T-106 | 2 / 2 |
| Phase 18 — Localization | T-107 → T-112 | 6 / 6 |
| Phase 19 — Monetization | T-113 → T-118 | 6 / 6 |
| Phase 20 — Multi-Place | T-119 → T-121 | 3 / 3 |
| Phase 21 — Security | T-122 → T-125 | 0 / 4 |
| Phase 22 — Performance | T-126 → T-128 | 0 / 3 |
| Phase 23 — Error Handling | T-129 → T-132 | 0 / 4 |
| Phase 24 — Testing | T-133 → T-142 | 0 / 10 |
| **TOTAL** | | **122 / 144** |

See [TASKS.md](TASKS.md) for full task specifications.

---

## License

Copyright © 2026 404 Not Found Indonesia. All rights reserved.

This software is licensed under a proprietary single-device license. You may not sell, distribute, copy, reverse-engineer, or create derivative works without explicit written permission. See [LICENSE](LICENSE) for full terms.

Contact: [iqbaleff214@gmail.com](mailto:iqbaleff214@gmail.com)
