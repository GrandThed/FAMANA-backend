# Vendor UI Remodel — Tarkov-Style Trade Screen

> Spec for rebuilding `client/StoreUI.lua` from the current list + detail
> panel into a three-pane trade screen modeled on Escape from Tarkov's
> trader view (reference screenshot in chat, 2026-07-07): the vendor's
> stock as an item grid on the left, a deal cart in the middle with one
> big DEAL button, and the player's own inventory grid on the right.
> Everything stays server-authoritative — the client builds a cart and
> asks; `VendorService` validates and executes through `PlayerService`.

## 1. Goal & scope

- **One screen, no tabs.** Buy and sell live together: vendor stock left,
  your grid right, both feeding a central deal cart. The Buy/Sell tabs
  and the detail pane die.
- **Grid-native.** Both sides render items as footprint-sized tiles
  (`Theme.Size.Cell` = 42px module, item `size` W×H), with price chips,
  rarity strokes and the §6.5 hover tooltip — the same visual language as
  `InventoryUI` (see the Lynx Ring tooltip screenshot).
- **Batched trades.** The cart holds buy AND sell lines at once; DEAL
  executes them in one remote call and settles the net gold.
- **New capability: selling rolled instances.** Today `PlayerService.
  removeItem` is id-based and deliberately skips `meta` rows, so rolled
  gear is unsellable. Drag & drop is positional, so sell lines can carry
  a grid position and ride the existing `removeAt` path — rolled gear
  becomes sellable without touching the meta-protection rule.

Out of scope (phase 2+, see §10): stock quantities/restock timers,
barter trades (item-for-item), a buyback tab, rearranging your own grid
while the store is open, per-roll sell pricing.

## 2. Reference mapping (Tarkov → FAMANA)

| Tarkov element | FAMANA equivalent |
|---|---|
| Trader stock grid (left, price tag per tile) | Store's **buyable** trades packed into a grid, `buyPrice` chip per tile |
| Deal zone + "DEAL!" button (center) | Cart with "You give / You get" lines, net gold, DEAL button |
| Player stash grid (right) | The `main` 10×30 grid (read + drag-to-sell; no rearranging in MVP) |
| Roubles | Gold (`◈`, `Gold` attribute) |
| Trader tabs along the bottom | Out of scope — one vendor per screen (`OpenStore` already scopes it) |
| Item context menus / quantity dialog | Click/shift-click/drag + cart steppers (§4) |

Sell-only trades (wood, stone, slime goo, goblin ear) never appear in
the stock pane — they surface as sell-price chips on the player's own
tiles, exactly like Tarkov shows what a trader pays for your loot.

## 3. Layout (authored at 1280×720, `UIKit.autoScale`)

Window ~**1120×620**, centered, `UIKit.stylePanel` + `addShadow`.
Title bar: store name (Display), vendor name (muted), `closeButton`.

```
┌──────────────────────────────────────────────────────────────────┐
│  GENERAL GOODS · Marla the Trader                            [X] │
├──────────────────┬───────────────────┬───────────────────────────┤
│  STOCK           │       DEAL        │  YOUR PACK        ◈ 1 240 │
│ ┌──┬──┬──┬──┐    │  You give         │ ┌──┬──┬──┬──┬──┬──┬──┬──┐ │
│ │▒▒│▒▒│▒▒│▒▒│    │   50× Wood  ◈100  │ │▒▒│▒▒│  │  │▒▒│  │  │  │ │
│ │◈120 ◈40 …  │    │  You get          │ │◈2 │◈2 │  … 10 cols …  │ │
│ ├──┴──┴──┴──┤    │   Iron Sword ◈120 │ ├──┴──┴─────────────────┤ │
│ │ 8 cols,    │    │  ───────────────  │ │ 10×30, ~11 rows       │ │
│ │ scrolls    │    │  Net   pay ◈ 20   │ │ visible, scrolls      │ │
│ └────────────┘    │  [    DEAL    ]   │ └───────────────────────┘ │
│                   │  status line      │                           │
└──────────────────┴───────────────────┴───────────────────────────┘
```

- **Stock pane (left, ~350px):** 8-column grid, scrollable. Tiles are
  packed client-side by first-fit in `stores.json` trade order (curated
  order = shelf layout; the packing is display-only, nothing persists).
  Tile = `ItemModels.preview` viewport + rarity stroke/glow + a price
  chip (`Theme.Text.Xs`, `Semantic.Currency` on Ink900 @ ~20%
  transparency) in the bottom-right corner.
- **Deal pane (center, ~250px):** two stacked line lists under "YOU
  GIVE" / "YOU GET" headers, then a net-gold row, the DEAL button
  (`UIKit.primaryButton`), and the status line (keep `ERROR_TEXT`).
  Cart line (42px): thumb · name (rarity-tinted, truncated) · qty
  stepper `− n +` (stackables only) · line total · remove `×`.
- **Player pane (right, ~450px):** the `main` grid, 10 wide, ~11 rows
  visible, scrollable — same tile visuals as InventoryUI. Header: gold
  readout. Tiles of items this store buys get a `sellPrice` chip;
  everything the store does NOT buy renders dimmed (~50% transparency)
  with a "Not traded here" tooltip line.
- Sharp corners, one ember accent (the DEAL button), tooltips identical
  to the inventory's (§6 below). `docs/UI.md` §8's vendor line gets
  rewritten to this layout.

## 4. Interactions

**Adding to the cart**
- Click a stock tile → +1 buy line (shift-click → +5, stackables only —
  preserves today's modifier). Drag a stock tile into the deal pane →
  same.
- Click a player tile → +1 sell line (shift-click → +5). Drag a player
  tile into the deal pane → the whole stack.
- Rolled instances (`meta` present) always add quantity 1 and carry
  their grid position; their line shows the "[Lv N]" tier-colored label.
- Cart steppers clamp: sells to the quantity owned (main grid only),
  buys to 99 (`MAX_TRADE_QUANTITY`). Same item id merges into one line
  per side; distinct rolled instances stay distinct lines.

**The DEAL button**
- Label shows the settlement: `DEAL — PAY ◈ 20` / `DEAL — GET ◈ 130`.
- Disabled (ghost style) when the cart is empty or net gold is short;
  the net row turns `Semantic.Danger` when unaffordable.
- On success: cart clears; grids and gold refresh through the existing
  `InventoryUpdated` push + `Gold` attribute (no local bookkeeping,
  same as today); server sends the Notify toast.
- On failure: unexecuted lines stay in the cart, status line maps the
  error code.

**Lifecycle**
- Opens on `OpenStore` (unchanged). Cart starts empty, always.
- New `ClientState.storeOpen` flag; `ShiftLockController` frees the
  cursor when `inventoryOpen or storeOpen`.
- Exclusive with the inventory screen: opening one closes the other
  (the windows overlap, and the store already shows your grid).
- Client auto-closes past ~20 studs from the vendor (watch every 0.5s);
  the server's `MAX_TRADE_DISTANCE = 16` check stays authoritative.

## 5. Protocol — `StoreDeal` replaces `StoreTrade`

No changes to `stores.json` / `Stores.lua` / backend content. One new
RemoteFunction, owned by `VendorService`; `StoreTrade` is deleted with
the old UI (StoreUI is its only consumer).

```lua
-- request
{
  storeId = "general_goods",
  lines = {
    { side = "buy",  itemId = "sword_iron", quantity = 1 },
    { side = "sell", itemId = "wood", quantity = 50 },
    -- rolled instance: positional, quantity always 1
    { side = "sell", itemId = "ring_lynx", x = 3, y = 7 },
  },
}
-- response
{ ok = true }                                    -- everything executed
{ ok = false, error = "no_gold", applied = 2 }   -- lines[1..2] executed, rest kept in cart
```

**Validation (reject the whole deal up front):** payload shape; ≤ 16
lines; `nearVendor`; every line traded by the store with the right
price side; quantities in 1..99; positional lines resolve to a matching
`main`-grid entry (itemId + meta present).

**Execution order — sells first, then buys** (the sale gold funds the
purchases, maximizing success):
1. Sell (plain): `PlayerService.removeItem(player, itemId, qty)` — the
   existing id-based remove; it skips meta rows, which is correct here.
2. Sell (rolled): the positional path `PlayerService.dropItem`-style →
   backend `removeAt` (meta rows are quantity-1 rows, so whole-row
   removal IS the sale). Extract the remove half of `dropItem` into
   `PlayerService.removeItemAt(player, ref)` so DropService and
   VendorService share it. Payout: base `sellPrice` (see §10.1).
3. Buy: `spendGold` → `addItem`; on `no_space`, refund that line's gold
   (today's behavior) and abort.
4. First failed line aborts the remainder → `{ ok = false, error,
   applied }`. Already-executed lines are NOT rolled back — inventory
   writes go through to the backend per call, so full atomicity needs a
   backend batch endpoint (§10.4). One toast summarizes what settled.

New error codes joining `ERROR_TEXT`: `bad_line` ("That trade isn't
valid anymore"), `too_many_lines` ("Deal too large").

## 6. Client architecture

Two extractions make both store panes cheap, then StoreUI is a rebuild:

1. **`client/ItemTooltip.lua`** — lift InventoryUI's §6.5 tooltip
   (rarity-tinted stroke, name/level/type rows, trait lines, stat line)
   into a module both screens require: `ItemTooltip.show(gui, entryOrDef,
   screenPos)` / `.hide()`. InventoryUI switches to it in the same PR —
   it's the regression test that the extraction is faithful.
2. **`client/ItemGrid.lua`** — a render-only grid view: takes a column
   count and a list of `{ itemId, quantity, x, y, meta?, price?,
   dimmed? }`, renders footprint tiles (viewport thumb, rarity stroke,
   qty badge, price chip), diffs tiles across updates like InventoryUI
   does, and exposes `onClick` / `onDragOut` / hover callbacks. The
   stock pane feeds it synthetic packed entries; the player pane feeds
   real `main` entries. It does NOT do within-grid drag/rotate — that
   complexity stays in InventoryUI until a later migration (§10.5).
3. **`client/StoreUI.lua`** — rebuilt: three panes, cart state
   (`{ side, itemId, quantity, x?, y?, meta? }` lines), DEAL via
   `StoreDeal`. Keeps: `OpenStore` wiring, `InventoryUpdated` +
   `RequestInventory` inventory mirror, `Gold` attribute readout,
   `ERROR_TEXT` mapping.

`ClientState.storeOpen` + the ShiftLockController read and the
InventoryUI/StoreUI mutual-close are the only touches outside these
three files (plus `EQUIP/BIND` hover keys are inventory-only — the
store grids don't quick-bind).

## 7. Server changes

- **`VendorService`**: replace `handleTrade` with the `StoreDeal`
  handler (§5). Vendor building, prompts, `VENDOR_DEFS`, `nearVendor`
  all unchanged.
- **`PlayerService`**: extract `removeItemAt(player, ref)` from
  `dropItem` (remove + refresh + return `itemId, quantity, meta`);
  `dropItem` becomes a thin wrapper. No new backend routes.

## 8. Implementation checklist

1. `ItemTooltip.lua` extraction + InventoryUI switched to it (no visual
   change — screenshot-compare the Lynx Ring tooltip).
2. `PlayerService.removeItemAt` + `VendorService.StoreDeal` (keep
   `StoreTrade` alive until step 4 lands so the old UI keeps working).
3. `ItemGrid.lua` + the three-pane StoreUI with click-to-cart only.
4. Drag & drop from both grids into the deal pane; delete `StoreTrade`.
5. Polish: dimming + "Not traded here", price chips, auto-close on
   walk-away, empty-cart state, `ClientState.storeOpen` cursor wiring.
6. Docs: CLAUDE.md (StoreUI/VendorService/new modules lines), UI.md §8
   vendor layout, this file's status.

## 9. Verification

- `luau-analyze` on every touched Luau file.
- Manual, in Studio at Marla:
  1. Buy 1 sword + 50 wood sell in one deal → net settles correctly,
     toast fires, grids refresh.
  2. Net short on gold → DEAL disabled; drop the buy line → enabled.
  3. Fill the grid, buy a 2×2 piece → `no_space`, gold refunded, prior
     lines settled, `applied` count matches.
  4. Kill goblins for a rolled drop → its tile sells via drag, the line
     shows "[Lv N]" in tier color, meta row gone after the deal.
  5. Shift-click ×5 on wood both directions; steppers clamp at owned/99.
  6. Tooltip on stock/player tiles matches the inventory's pixel-for-
     pixel; dimmed non-traded tiles say so.
  7. Open inventory (B) while trading → store closes (and vice versa);
     walk 20+ studs away → panel closes itself.
  8. Resize the window (small viewport) → `autoScale` keeps all three
     panes usable.

## 10. Open questions

1. **Rolled-instance pricing** — flat base `sellPrice` (proposed MVP),
   or scale by `meta.itemLevel` × rarity (needs a shared formula so the
   chip, the cart line and the server agree)?
2. **Stock limits / restock** — Tarkov's scarcity loop. Needs per-store
   state (in-memory per server, or backend if shared). Post-MVP.
3. **Barter trades** — `stores.json` trades could grow a
   `barter: [{ itemId, qty }]` cost; the cart model already fits it.
4. **Deal atomicity** — accept sequential-with-report (proposed), or
   add a backend `POST /player/:id/deal` batch endpoint that settles
   gold + all lines in one transaction?
5. **ItemGrid ↔ InventoryUI convergence** — after the store ships,
   migrate InventoryUI's grid onto `ItemGrid` (adding drag-within/
   rotate), or keep them separate implementations?
6. **DEAL flavor** — plain "DEAL", or Aethelgard-flavored copy
   ("Seal the Bargain")? Pure copywriting, ember button either way.
