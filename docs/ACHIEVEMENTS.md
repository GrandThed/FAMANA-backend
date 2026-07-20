# Achievements + Leaderboards

> Design + status doc for two features built together: persistent
> achievements with gold rewards, and global leaderboards. Both build on
> the bestiary work (`docs/BESTIARY.md`) — achievements reuse
> `bestiary_kills` directly for kill-based entries, and the "kills"
> leaderboard sums that same column.
>
> Status: SHIPPED (first pass). The achievement catalog and gold amounts
> are a starting point — tune `shared/Achievements.lua`'s `LIST`, not the
> call sites.

## 1. Achievements

### 1.1 How it works

`shared/Achievements.lua` is a flat catalog: each entry has a `metric`
(what kind of stat it tracks), an optional `target` (which specific
instance — e.g. `metric = "kills", target = "goblin"`), an `amount`
(progress needed), and a `reward` (gold, for now).

`AchievementsService` (server) hooks into every event that could move an
achievement forward — the same decoupled-hook pattern `QuestService`/
`BestiaryService` already use:

| Event | Hook | Bumps |
| --- | --- | --- |
| Enemy killed | `EnemyService.onKilled` | (nothing new — reads `bestiary_kills`, owned by `BestiaryService`) |
| Resource gathered | `GatheringService.onGathered` | `stats.gathered[itemId]` |
| Item crafted | `CraftingService.onCrafted` (new hook) | `stats.crafted` |
| Quest completed | `QuestService.onCompleted` (new hook) | `stats.questsCompleted` |
| Level up | `PlayerService.registerLevelUpHandler` | (nothing new — reads `MaxClassLevel`, derived from `classLevels`) |

After each bump it re-checks the whole `Achievements.LIST` against
`PlayerService.getAchievementStats(player)` and unlocks (+ grants gold for)
anything newly complete. `PlayerService.unlockAchievement` is idempotent —
safe to call every time, only returns `true` (triggering the reward) the
first time.

### 1.2 Persistence

Two new JSONB columns on `players`, saved/loaded exactly like
`bestiary_kills`:

- `stats` — a generic counter bag: `{ gathered: { [itemId]: count },
  crafted: count, questsCompleted: count }`. Kill counts intentionally
  live in `bestiary_kills` instead of being duplicated here.
- `achievements_unlocked` — `{ [achievementId]: true }`.

### 1.3 Client

`AchievementsClient.lua` mirrors three attributes the server publishes
(`PlayerStats`, `AchievementsUnlocked`, `MaxClassLevel`) plus reads
`BestiaryClient.allKills()` for kill-based metrics — no remote round-trip,
same approach `BestiaryClient`/`BestiaryUI` established. `AchievementsUI`
(top-right button / **L**) renders every catalog entry with a progress bar,
using the exact same `Achievements.progress(...)` function the server uses
to decide unlocks, so the bar and the actual unlock condition can never
disagree.

### 1.4 Adding a new achievement

1. Add an entry to `Achievements.LIST` with a `metric` from the table in
   §1.1's hook list (or a new one — see `Achievements.progress`'s branches).
2. If it needs a metric that doesn't exist yet, add the branch in
   `Achievements.progress` and, if it needs a new counter, a `bump*`
   helper in `PlayerService.lua` (follow `bumpGathered`/`bumpCrafted`) fed
   by a hook into whichever service owns that event.

## 2. Leaderboards

### 2.1 How it works

`GET /leaderboards?type=level|gold|kills&limit=20` (backend, X-Api-Key
gated like the rest of the game API) — one aggregate SQL query per metric,
ordered server-side in Postgres rather than pulling every row into Node.
The `kills` metric sums `bestiary_kills`' JSONB values with
`jsonb_each_text` — a global ranking needs one query across all players,
which is why this can't be client-side like Bestiary/Achievements.

`LeaderboardService` (Roblox server) proxies that endpoint through a
`GetLeaderboard` RemoteFunction, with a 15-second per-metric cache so
several players opening the panel at once don't each trigger a fresh
backend query. `LeaderboardUI` (top-right button / **T**) has one tab per
metric.

### 2.2 Adding a new metric

Add an entry to `METRICS` in `backend/src/routes/leaderboards.js` (a
`select`/`orderBy` SQL fragment) and a matching tab in `LeaderboardUI.TABS`.

## 3. Open questions / future work

- Achievement rewards are gold-only; items/titles/cosmetics would need
  `reward.items`/`reward.title` handling in `AchievementsService`.
- Leaderboards are global-only; per-guild rankings would need a `guildId`
  filter on the same query (see `docs/CAMP_TIERS.md`-style guild follow-up
  work already discussed).
- No in-game toast/animation for reaching a new leaderboard rank — only
  achievement unlocks currently notify.
