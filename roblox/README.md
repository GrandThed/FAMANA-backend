# FAMANA — Roblox client/server

Luau game code, synced into Roblox Studio with [Rojo](https://rojo.space).
Talks to the live backend (`../backend`) over HttpService.

## Structure

```
src/
├── shared/   -> ReplicatedStorage.Shared   (visible to client + server)
│   ├── Config.lua      # HP/inventory/cell constants (NOT secret)
│   ├── Items.lua       # item defs, mirrored from backend/src/items.js
│   └── Remotes.lua     # RemoteEvent/Function factory (works both sides)
├── server/   -> ServerScriptService.Server (server only — trusted)
│   ├── init.server.lua     # entry point, starts the services
│   ├── BackendConfig.lua    # backend base URL
│   ├── BackendService.lua   # HttpService wrapper (auth, JSON, errors)
│   ├── PlayerService.lua     # load on join / save on leave / autosave
│   ├── HealthService.lua     # HP restore, regen, death respawn
│   └── Secret.lua            # YOUR API KEY (gitignored — see below)
└── client/   -> StarterPlayer.StarterPlayerScripts.Client
    ├── init.client.lua  # entry point
    ├── HealthUI.lua     # health bar
    └── InventoryUI.lua  # 20-slot inventory panel (toggle with I)
```

## One-time setup

1. **Install Rojo** (CLI + the Studio plugin): https://rojo.space/docs/v7/getting-started/installation/
2. **The API key** — create `src/server/Secret.lua` returning your backend
   `API_KEY` (this file is gitignored so the secret never gets committed):
   ```lua
   return "your-api-key-here"
   ```
   `BackendService` reads it and sends it as the `X-Api-Key` header. It lives in
   `ServerScriptService`, so it is **never** replicated to clients.
3. **Enable HTTP** in Studio: Home → Game Settings → Security →
   **Allow HTTP Requests** = ON. (Required for the game to reach the backend.)

## Running it

```bash
cd roblox
rojo serve          # then click "Connect" in the Rojo Studio plugin
```

Press **Play** in Studio. On join, your character's HP + inventory load from the
backend; the sword + axe show up in the inventory panel (press **I**). HP, cell,
and position autosave every 60s and on leave.

> The backend URL is set in `src/server/BackendConfig.lua`.
