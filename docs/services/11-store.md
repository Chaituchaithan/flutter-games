# Flutter hand-off 11: store

The shop catalogue (coin packs, power-up packs, avatar items, Remove Ads), buying with tokens
or gold, real-money purchases (Google Play and the App Store), subscriptions, ad-free,
avatars and power-ups.

This file is the contract between the Flutter app and the **api-gateway** store routes. It is
written so a Claude agent can implement it directly. Read `00-conventions.md` first: the error
body, list shapes, money parsing, the `Idempotency-Key` header and the device check on
`/sensitive/` routes are defined there and not repeated here. Sessions and the auth
interceptor come from `01-auth.md`. Every purchase writes ledger rows, so read `03-wallet.md`
too.

**Where the samples come from.** Every reply marked "real" was captured from the running
gateway on 24 Nov 2026 with two fresh test players, A and B (B signed up with A's referral
code). The development gateway runs with `DEBUG_MODE` on, so its **sandbox** routes for
real-money packs and subscriptions were used; no receipt was sent to Google or Apple and none
was faked. Replies marked "from the code" were not captured; their shape is read from the
gateway source.

**Read this first: what the backend does not have.** Real-money buying is not finished on
the server. The app must not pretend it is; build the screens and hide what can't work yet
(see "Known issues"):

| Wanted | State today |
|---|---|
| Verify a Google Play or App Store purchase | `POST /sensitive/iap/verify` exists but **always answers `503 UNAVAILABLE`** ("in-app purchase verification is not configured"). No store client is connected. |
| Buy a coin pack in a development build | `POST /sensitive/shop/purchase/sandbox` credits the pack without paying. **Development only** (`503` in production). |
| Buy a subscription | `POST /sensitive/subscriptions/subscribe` takes **no receipt**. It works only on development (sandbox); production answers `503`. |
| Restore purchases | **No route.** |
| Renew a subscription | **No route and no renewal job.** A subscription simply ends at `expires_at`. |
| The store product id of a pack | **Not in the API.** `GET /shop/items` has no Google or Apple product id; keep the map in the app (section 3a). |
| What a subscription plan gives | `GET /subscriptions/plans` sends `features: {}` and no multipliers or tagline. Keep the plan copy in the app (section 4e). |
| Buy Remove Ads for real money | The item has a dollar price, but no route grants ad-free from a store payment. Sell it for gold only. |

---

## For the Claude agent: what to build

1. A `StoreApi` on the shared `ApiClient` with one method per route below. Every buying method
   takes an `idempotencyKey` and sends it as the `Idempotency-Key` header.
2. Models: `ShopItem`, `ShopPurchase`, `SandboxPurchase`, `IapVerifyResult`, `IapTransaction`,
   `SubscriptionPlan`, `MySubscription` (two shapes, section 4b), `AdFreeStatus`, `AdsFlow`,
   `Avatar`, `PowerUp`, `CosmeticPurchase`, `Inventory`. Money fields accept a number **and** a
   numeric string (`00-conventions.md`, "Money"); this module uses both.
3. A `PurchaseFlow` helper that owns one attempt: it makes a new UUID key, sends the request,
   on a timeout retries **once with the same key**, and on success re-reads the wallet
   (`WalletStore` from `03-wallet.md`) and the inventory.
4. An `IapBridge` around `in_app_purchase` (Play Billing / StoreKit) that is **switched off**
   until the server verifies receipts (section 3). In development builds the coin-pack buttons
   call the sandbox route instead; in release builds they are hidden or show "Coming soon".
5. Screens:
   - **Shop**: tabs "Coins" (token and gold packs), "Power-ups" (packs), "Avatars", and a
     "Remove Ads" card. Each tile shows the price in force and any offer or special badge.
   - **Buy sheet**: item, price, the wallet balance in that currency, Confirm. Grey out Confirm
     when the balance is short and offer "Get more gold" / "Get more tokens".
   - **VIP / Subscriptions**: the plans by tier with monthly / yearly, the current plan, and
     Cancel.
   - **Avatars** (also in the profile picker, `02-profile-and-sessions.md` 3): owned, free and
     locked avatars with their level and price.
   - **Power-ups** per game: the catalogue with "You have N" from the inventory.
   - **Purchase history** (optional): `GET /sensitive/iap/history`.
6. Tests: model parsing for each real reply here; error mapping for each route; that a retried
   purchase reuses its key and a new purchase makes a new one; that `Idempotent-Replayed:
   true` is treated as success; that both money shapes parse.

Never log store request or reply bodies, receipts or purchase tokens, even in debug builds.

---

## Endpoints at a glance

All paths are under `http://<host>:1280/api/v1`. All need `Authorization: Bearer
<access_token>`. "Device check" is the `/sensitive/` check from `00-conventions.md`
(`401 FINGERPRINT_MISMATCH`). "Store switch" is the operator's store kill switch
(`503 KILL_SWITCH_ENGAGED`, section "Errors").

| What | Method and path | Device check | Store switch | Success |
|---|---|---|---|---|
| Shop catalogue | `GET /sensitive/shop/items` | yes | no | `200` + array |
| One shop item | `GET /sensitive/shop/items/{id}` | yes | no | `200` |
| Buy with tokens or gold | `POST /sensitive/shop/purchase` | yes | yes | `200` |
| Sandbox coin pack (development) | `POST /sensitive/shop/purchase/sandbox` | yes | yes | `200` |
| Verify a store purchase | `POST /sensitive/iap/verify` | yes | no | `200` (today always `503`) |
| My real-money purchases | `GET /sensitive/iap/history` | yes | no | `200` + page list |
| Plans | `GET /sensitive/subscriptions/plans` | yes | no | `200` + array |
| My subscription | `GET /sensitive/subscriptions/my` | yes | no | `200` |
| Subscribe | `POST /sensitive/subscriptions/subscribe` | yes | yes | `200` |
| Cancel | `POST /sensitive/subscriptions/cancel` | yes | no | `200` |
| Ad-free status | `GET /sensitive/ad-free/status` | yes | no | `200` |
| Which ads to show | `GET /me/ads/flow` | no | no | `200` |
| Avatar catalogue | `GET /cosmetics/avatars` | no | no | `200` + array |
| Buy an avatar | `POST /cosmetics/avatars/{id}/purchase` | no | yes | **`201`** |
| Equip an avatar | `POST /cosmetics/avatars/{id}/equip` | no | no | `200` |
| Power-up catalogue | `GET /cosmetics/power-ups?game_id=` | no | no | `200` + array |
| Buy one power-up | `POST /cosmetics/power-ups/{id}/purchase` | no | yes | **`201`** |
| Use a power-up outside a game | `POST /cosmetics/power-ups/{id}/use` | no | no | `200` (don't call; section 7d) |
| What I own | `GET /users/me/inventory` | no | no | `200` (`02-profile-and-sessions.md`) |

The routes under `/sensitive/shop`, `/sensitive/iap` and `/sensitive/subscriptions` can also
answer `403 GEO_BLOCKED` where an operator has closed the store for the player's region (from
the code). The `/cosmetics` routes don't have that check.

`POST /sensitive/ad-free/activate` and `POST /cosmetics/admin/grant` are console routes; a
player gets `403 FORBIDDEN` (real: `"forbidden: requires Admin or higher"`). Never call them.

---

## How a purchase shows in the wallet

Every money movement of the store is a ledger row (`GET /wallet/ledger`, `03-wallet.md`).
Real rows from player A:

| What happened | `kind` | `direction` | `counterparty` | `item_kind`, `item_name` |
|---|---|---|---|---|
| A wallet purchase (shop item, avatar, power-up, Remove Ads) | `purchase` | `debit` | `house_revenue` | `power_up` / `avatar` / `ad_free`, the item or pack name |
| A gold-priced token pack (none on sale today) | `purchase` | `credit` (tokens) and `debit` (gold) | | from the code |
| A token pack bought for real money (sandbox today) | `iap_token_pack` | `credit` | `store_mint` | `null` |
| A gold pack bought for real money (sandbox today) | `iap_gold_pack` | `credit` | `store_mint` | `null` |
| The referral reward on a first real-money pack | `referral_reward` | `credit` | `promo_budget` | `null` |
| A subscription | **no row** | | | (real: B's balance did not change) |

```json
{"entry_id": "ledger:42166", "created_at": "2026-11-24T09:55:42.662103Z", "currency": "token",
 "direction": "debit", "amount": 250, "kind": "purchase", "counterparty": "house_revenue",
 "counterparty_user_id": null, "tournament_id": null, "match_id": null,
 "item_kind": "power_up", "item_name": "Ludo Shield x5", "game_code": null, "variant_code": null}

{"entry_id": "ledger:42165", "created_at": "2026-11-24T09:55:38.894635Z", "currency": "token",
 "direction": "credit", "amount": 550, "kind": "iap_token_pack", "counterparty": "store_mint",
 "counterparty_user_id": null, "tournament_id": null, "match_id": null,
 "item_kind": null, "item_name": null, "game_code": null, "variant_code": null}
```

The purchase replies also carry the new balance (each section says in which shape). Update the
balance chip from it, then re-read `GET /wallet/balance` when convenient.

---

## 1. Shop catalogue

### 1a. List

`GET /sensitive/shop/items?category=`

| Query | Rule |
|---|---|
| `category` | Optional: `token_pack`, `gold_pack`, `power_up_pack`, `avatar` or `ad_free`. An unknown value returns `[]` (real), not an error. |

A plain array (list shape 1), in display order. Only active, published items are listed.
Real reply, trimmed to one item of each kind:

```json
[
  {"id": 2, "code": "tokens_550", "name": "Pouch of Tokens", "description": "500 tokens + 50 bonus.",
   "category": "token_pack", "token_amount": 500, "gold_amount": 0, "bonus_token_amount": 50,
   "bonus_gold_amount": 0, "power_up_id": null, "power_up_quantity": null, "avatar_id": null,
   "is_active": true, "created_at": "2026-11-14T08:35:16.461863Z",
   "price_unit": "usd", "price_usd_cents": 499, "price_tokens": null, "price_gold": null,
   "price_tier": "default", "regular_price": 499, "special_label": null, "special_until": null},
  {"id": 5, "code": "gold_5000", "name": "Gold Sack", "description": "5,000 gold.",
   "category": "gold_pack", "token_amount": 0, "gold_amount": 5000, "bonus_token_amount": 0,
   "bonus_gold_amount": 0, "power_up_id": null, "power_up_quantity": null, "avatar_id": null,
   "is_active": true, "created_at": "2026-11-14T08:35:16.461863Z",
   "price_unit": "usd", "price_usd_cents": 199, "price_tokens": null, "price_gold": null,
   "price_tier": "default", "regular_price": 199, "special_label": null, "special_until": null},
  {"id": 12, "code": "ludo_shield_x5", "name": "Ludo Shield x5",
   "description": "Five shields against the triple-six penalty.", "category": "power_up_pack",
   "token_amount": 0, "gold_amount": 0, "bonus_token_amount": 0, "bonus_gold_amount": 0,
   "power_up_id": 28, "power_up_quantity": 5, "avatar_id": null, "is_active": true,
   "created_at": "2026-11-14T08:35:16.461863Z",
   "price_unit": "token", "price_usd_cents": null, "price_tokens": 250, "price_gold": null,
   "price_tier": "default", "regular_price": 250, "special_label": null, "special_until": null},
  {"id": 17, "code": "avatar_ludo_golden_crown", "name": "...", "category": "avatar",
   "avatar_id": 15, "price_unit": "token", "price_usd_cents": null, "price_tokens": 500,
   "price_gold": null, "price_tier": "default", "regular_price": 500, "...": "..."},
  {"id": 7, "code": "ad_free_forever", "name": "Remove Ads", "description": "Play without ads, forever.",
   "category": "ad_free", "token_amount": 0, "gold_amount": 0, "bonus_token_amount": 0,
   "bonus_gold_amount": 0, "power_up_id": null, "power_up_quantity": null, "avatar_id": null,
   "is_active": true, "created_at": "2026-11-14T08:35:16.461863Z",
   "price_unit": "gold", "price_usd_cents": 299, "price_tokens": null, "price_gold": 10000,
   "price_tier": "default", "regular_price": 299, "special_label": null, "special_until": null}
]
```

The development catalogue on 24 Nov 2026 (real): token packs `tokens_100` (99 c),
`tokens_550` (499 c), `tokens_1200` (999 c), `tokens_6500` (4999 c); gold packs `gold_5000`
(199 c), `gold_30000` (999 c); power-up packs for Snake & Ladder, Ludo and Bingo (180 to 400
tokens); avatar items for Snake & Ladder, Ludo and Chess; and Remove Ads (10,000 gold). Never
hard-code it; an operator edits it in the console.

### 1b. One item

`GET /sensitive/shop/items/{id}`, numeric id. Same object as one list entry (real, item 12
above). An inactive or unknown id is `404 NOT_FOUND` (`"not found: shop item not found"`,
real).

### 1c. Fields

| Field | Meaning |
|---|---|
| `id` | Send it as `item_id` when buying. |
| `code` | Stable code. Use it for local art and for the store product map (3a). |
| `name`, `description` | Display text (not translated by the server). |
| `category` | `token_pack`, `gold_pack`, `power_up_pack`, `avatar`, `ad_free`. Picks the tab. |
| `token_amount` + `bonus_token_amount` | Tokens a pack gives per unit. Show "500 + 50 bonus". |
| `gold_amount` + `bonus_gold_amount` | Gold a pack gives per unit. |
| `power_up_id`, `power_up_quantity` | For `power_up_pack`: which power-up and how many per pack. Match `power_up_id` to `GET /cosmetics/power-ups` for the icon and the game. |
| `avatar_id` | For `avatar`: the avatar it unlocks (`GET /cosmetics/avatars`). |
| `price_unit` | `usd` (real money only), `token`, `gold`, `both` (sold for gold), `free`, or `null` (not for sale). |
| `price_usd_cents` | Real-money price in US cents, or `null`. |
| `price_tokens` | Wallet price in tokens for the whole pack, or `null`. |
| `price_gold` | Wallet price in gold for the whole pack, or `null`. |
| `price_tier` | `default`, `offer` (a standing discount) or `special` (a timed sale). Missing when the item has no price. |
| `regular_price` | The price before the discount, in the **same unit as the charged price**. See Known issue 6. |
| `special_label`, `special_until` | The sale's name and end (UTC), only while it runs. |

**Which price to show and charge** (the server's rule):

- `price_tokens` set: buy with tokens (section 2).
- `price_gold` set: buy with gold (section 2).
- Only `price_usd_cents` set (`price_unit: "usd"`): a real-money pack (section 3).
- Remove Ads has both `price_gold` and `price_usd_cents`. Sell it for **gold** only (Known
  issue 5).
- Nothing set: not for sale; hide the buy button.

**Discount badges:** when `price_tier` is `offer` or `special` and `regular_price` is above
the charged price, show the regular price struck through. For `special`, show
`special_label` and a countdown to `special_until`; when the countdown ends, reload the
catalogue (the price goes back). The price is always charged by the server at the moment of
purchase; never send a price.

---

## 2. Buy with tokens or gold

`POST /sensitive/shop/purchase`

| Header | |
|---|---|
| `Idempotency-Key` | Send it: a new UUID per purchase attempt, the same one on a retry. 1 to 100 printable ASCII characters. |

```json
{"item_id": 12, "quantity": 1, "currency": "token"}
```

| Field | Rule |
|---|---|
| `item_id` | Required. A shop item id. |
| `quantity` | Required, 1 to 100. Avatars and Remove Ads: only 1. |
| `currency` | Required. `token` or `gold`; must be the currency the item has a price in. |
| `idempotency_key` | Optional, the same key in the body instead of the header. If both are sent they must match. Prefer the header. |

What can be bought here: power-up packs, avatar items, Remove Ads (gold), and token packs that
have a gold price (none today). Real-money packs can't (`400`, below).

**Success:** `200`. Real (player A, Ludo Shield x5):

```json
{"purchase_id": 3, "item_id": 12, "quantity": 1, "total_price": 250, "currency": "token", "new_balance": "400"}
```

| Field | Meaning |
|---|---|
| `purchase_id` | The purchase record. |
| `total_price` | Amount taken (number), in `currency`. Unit price times `quantity`. |
| `new_balance` | The balance in that currency afterwards, a **string**. Update the chip from it. |

What the buyer gets, in the same transaction:

| `category` | Granted |
|---|---|
| `power_up_pack` | `power_up_quantity x quantity` of that power-up in the inventory. Real: A's inventory then read `{"power_up_id": 28, "code": "shield", "name": "Shield", "game_id": 1, "quantity": 5}`. |
| `avatar` | The avatar, owned (it shows in the inventory and can be equipped). |
| `ad_free` | Ad-free for good (section 5). |
| `token_pack` (gold-priced) | The pack's tokens plus bonus. |

**Retry with the same key:** `200`, the first reply again, header `Idempotent-Replayed: true`.
Nothing is charged twice. Real (the field order differs; parse by name):

```json
{"currency": "token", "item_id": 12, "new_balance": "400", "purchase_id": 3, "quantity": 1, "total_price": 250}
```

**Errors** (all real unless marked)

| Status | `error` | When | Show |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` (`field: "quantity"`) | `quantity` outside 1-100. | App bug. |
| 400 | `VALIDATION_ERROR` | Wrong currency for the item (`item 12 cannot be bought with gold`); a real-money pack (`item 1 cannot be bought with token`); a second avatar or Remove Ads in one go (`avatars can only be bought once`, `ad-free can only be bought once`). | App bug: buy in the item's currency. |
| 400 | `BAD_REQUEST` | `currency` not `token`/`gold`; a missing field; a bad key; header and body keys differ. | App bug. |
| 401 | `FINGERPRINT_MISMATCH` | Network or app identity changed since login (production; from the code). | Log in again. |
| 403 | `LEVEL_REQUIRED` | An avatar above the player's level. | "Reach level 5 to unlock." Take the number from the catalogue's `required_level`. |
| 403 | `GEO_BLOCKED` | The store is closed in the region (from the code). | "The store isn't available in your region." |
| 404 | `NOT_FOUND` | No such item, or it was switched off. | Reload the catalogue. |
| 409 | `INSUFFICIENT_FUNDS` | Not enough of that currency. | "Not enough tokens." Offer coin packs. |
| 409 | `CONFLICT` | The avatar is already owned (`avatar already owned`, from the code); Remove Ads already owned for good (`already ad-free for good`, real); the key was used for a different purchase. | Owned: mark it owned and close the sheet. Key: app bug. |
| 503 | `KILL_SWITCH_ENGAGED` | The operator paused the store (from the code). | Show the `message`; disable every Buy button. |

```json
{"error": "INSUFFICIENT_FUNDS", "message": "insufficient funds"}
{"error": "VALIDATION_ERROR", "message": "validation error: item 12 cannot be bought with gold"}
{"error": "VALIDATION_ERROR", "message": "validation error: item 1 cannot be bought with token"}
{"error": "VALIDATION_ERROR", "message": "validation error: avatars can only be bought once"}
{"error": "VALIDATION_ERROR", "field": "quantity", "message": "validation error: quantity: must be between 1 and 100"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected `token` or `gold` at line 1 column 45"}
{"error": "BAD_REQUEST", "message": "bad request: the Idempotency-Key header and idempotency_key differ"}
{"error": "BAD_REQUEST", "message": "bad request: idempotency key must be 1 to 100 printable ASCII characters"}
{"error": "LEVEL_REQUIRED", "message": "Requires level 5 (you are level 1)"}
{"error": "NOT_FOUND", "message": "not found: shop item not found"}
{"error": "CONFLICT", "message": "conflict: already ad-free for good"}
{"error": "CONFLICT", "message": "conflict: idempotency key was already used for another purchase"}
```

`LEVEL_REQUIRED` is new to this file: add it to the `ApiError` mapping. The player's level
for avatars is their **highest level in any game** (`08-progress-and-history.md`); level 1
with no games played.

No network or a timeout: don't assume it failed. Retry **once with the same key**; the reply
says whether it went through.

---

## 3. Real-money purchases (Google Play and App Store)

**State on 24 Nov 2026:** the server cannot verify a store purchase yet. The route below is
the contract the app will use, but every call answers `503 UNAVAILABLE`. Until that changes:

- **Release builds:** don't start a store payment. Show coin packs with their price and a
  "Coming soon" state, or hide the Coins tab. A player must never pay a store for something
  the server can't credit.
- **Debug builds:** buy packs with the sandbox route (3c). It needs no payment.

### 3a. Verify a purchase (from the code; today always `503`)

`POST /sensitive/iap/verify`

```json
{
  "store": "google",
  "receipt_data": "<the store's proof of purchase>",
  "product_id": "tokens_100",
  "transaction_id": "GPA.3301-1234-5678-90123",
  "amount_cents": 99,
  "currency_code": "USD"
}
```

| Field | Rule | Google Play | App Store |
|---|---|---|---|
| `store` | `google` or `apple`. | `google` | `apple` |
| `receipt_data` | 1 to 65,536 characters. | The purchase token (`PurchaseDetails.verificationData.serverVerificationData`). | The receipt or signed transaction from `serverVerificationData`. |
| `product_id` | 1 to 120 characters. The store's product id. | e.g. `tokens_100` | e.g. `com.allgames.tokens.100` |
| `transaction_id` | 1 to 120 characters. The store's id for this purchase. Used to refuse a replay. | The order id (`GPA....`). | The transaction id. |
| `amount_cents` | 0 or more. What the store charged, in minor units. **Recorded, never trusted.** | from `ProductDetails` | from `ProductDetails` |
| `currency_code` | Exactly 3 letters (ISO 4217). | | |

**Product ids.** The shop API does not send them. On the development database each pack has
(read from the database, 24 Nov 2026):

| Shop `code` | Google product id | Apple product id |
|---|---|---|
| `tokens_100` | `tokens_100` | `com.allgames.tokens.100` |
| `tokens_550` | `tokens_550` | `com.allgames.tokens.550` |
| `tokens_1200` | `tokens_1200` | `com.allgames.tokens.1200` |
| `tokens_6500` | `tokens_6500` | `com.allgames.tokens.6500` |
| `gold_5000` | `gold_5000` | `com.allgames.gold.5000` |
| `gold_30000` | `gold_30000` | `com.allgames.gold.30000` |
| `ad_free_forever` | `ad_free_forever` | `com.allgames.adfree` |

Keep this map in the app config, keyed by shop `code`, and confirm it with the server owner
before release. Subscription plans have **no** product ids yet.

**Success (from the code, never seen):** `200`

```json
{"receipt_id": 1, "transaction_id": 1, "verified": true, "tokens_credited": "550"}
```

`transaction_id` here is the server's record id, not the store's. `tokens_credited` is a
decimal sent as a string. The server credits what **its catalogue** says the product gives,
never `amount_cents`. A ledger row `iap_token_pack` follows.

**Errors**

| Status | `error` | When | What the app does | Seen |
|---|---|---|---|---|
| 400 | `VALIDATION_ERROR` | A field breaks a rule (`field` names it). | App bug. Don't finish the store transaction. | real |
| 400 | `BAD_REQUEST` | `store` not `google`/`apple`; a missing field. | App bug. | real |
| 404 | `NOT_FOUND` | No shop item sells that `product_id`. | Keep the store transaction open; report it. | code |
| 409 | `DUPLICATE_TRANSACTION` | This `transaction_id` was already credited (a replay). | Treat as **success**: finish the store transaction and re-read the balance. | code |
| 503 | `UNAVAILABLE` | Verification is not configured (**every call today**). | Keep the store transaction open; show "Purchases are not available yet". | real |
| 503 | `KILL_SWITCH_ENGAGED` | Not checked on this route today (from the code). | | |

Real replies:

```json
{"error": "UNAVAILABLE", "message": "unavailable: in-app purchase verification is not configured"}
{"error": "VALIDATION_ERROR", "field": "currency_code", "message": "validation error: currency_code: must be 3 characters"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected `apple` or `google` at line 1 column 18"}
```

(The `503` above came from a body with `"receipt_data": "w11doc-not-a-real-receipt"`; nothing
was recorded.)

**Order of steps when it works** (the usual store rule; plan for it now):

1. Start the payment with the store's product id.
2. On `purchased`, send `/iap/verify`. Don't credit anything on the device.
3. On `200` or `409 DUPLICATE_TRANSACTION`: complete the purchase (`completePurchase`, which
   consumes a Google consumable and finishes the Apple transaction), then re-read the wallet.
4. On any other error or no network: leave the purchase **pending**. The store will hand it
   back on the next app start (`purchaseStream`); send it again then. The `transaction_id`
   makes a repeat safe.

Note: the verify route has no `Idempotency-Key`; the store's `transaction_id` plays that role.
Today it credits **tokens only**; a gold pack or Remove Ads through it would credit nothing
(Known issue 2).

### 3b. My real-money purchases

`GET /sensitive/iap/history?page=&per_page=`, page list shape 2 (`per_page` 1-100, default
20). Real (player A, nothing verified yet):

```json
{"data": [], "total": 0, "page": 1, "per_page": 20, "total_pages": 0}
```

An item (from the code):

```json
{"id": 1, "receipt_id": 1, "user_id": "ee50efab-2d91-4ea6-8fa4-14b7b2638703", "product_id": "tokens_550",
 "shop_item_id": 2, "subscription_plan_id": null, "amount_cents": 499, "currency_code": "USD",
 "store_currency_code": "INR", "status": "completed", "refunded_at": null,
 "purchased_at": "2026-11-24T10:00:00Z", "created_at": "2026-11-24T10:00:00Z"}
```

`amount_cents` is always US cents (`currency_code` is always `USD`); `store_currency_code`
is what the store charged in. `status` is `completed` or `refunded`. Sandbox purchases (3c)
are **not** listed here (real: still empty after them); they show only in the wallet ledger.

`per_page` over 100 is `400 VALIDATION_ERROR` (`field: "per_page"`, real).

### 3c. Sandbox coin packs (development builds only)

`POST /sensitive/shop/purchase/sandbox`. Credits a token or gold pack **without payment**,
only while the server runs with `DEBUG_MODE`. Production answers `503 UNAVAILABLE`
(`"real-money packs need a verified store payment; sandbox buying is DEBUG_MODE only"`, from
the code). Use it behind a debug-build flag only.

Header `Idempotency-Key` as in section 2.

```json
{"item_id": 2, "quantity": 1}
```

| Field | Rule |
|---|---|
| `item_id` | A `token_pack` or `gold_pack` with a dollar price. |
| `quantity` | 1 to 100. |
| `idempotency_key` | Optional body copy of the key. |

**Success:** `200`. Real (A, `tokens_550`):

```json
{"purchase_id": 2, "item_id": 2, "quantity": 1, "tokens_credited": 550, "gold_credited": 0,
 "price_usd_cents": 499, "sandbox": true, "balances": {"tokens": 650, "gold": 500}}
```

Real (A, `gold_5000` x 2):

```json
{"purchase_id": 5, "item_id": 5, "quantity": 2, "tokens_credited": 0, "gold_credited": 10000,
 "price_usd_cents": 398, "sandbox": true, "balances": {"tokens": 300, "gold": 10500}}
```

`balances` are **numbers** here (strings elsewhere). The bonus is included in the credited
amount. The ledger gets `iap_token_pack` / `iap_gold_pack` rows, exactly as a verified store
purchase will; and it counts as a real-money purchase for the referral reward (3d).

Retry with the same key: the first reply and `Idempotent-Replayed: true` (real). Errors
(real): `400 VALIDATION_ERROR` `"item 12 is not a real-money token or gold pack"`,
`field: "quantity"` for 0, `409 CONFLICT` for a key used on another purchase,
`404 NOT_FOUND` for an unknown item, `503 KILL_SWITCH_ENGAGED` (from the code).

### 3d. Referral reward on the first real-money purchase

`09-social.md` 5d: a player who signed up with a referral code pays both sides when they make
their **first real-money pack purchase** (a verified store purchase, or a sandbox one on
development). Nothing to call: the reward is written in the same transaction as the pack.

Real: B signed up with A's code, then bought `tokens_100` on the sandbox. In the same second
both ledgers got a row, and A's stats moved:

```json
// B's ledger (and the same row in A's)
{"entry_id": "ledger:42175", "created_at": "2026-11-24T09:56:49.352642Z", "currency": "gold",
 "direction": "credit", "amount": 500, "kind": "referral_reward", "counterparty": "promo_budget",
 "counterparty_user_id": null, "tournament_id": null, "match_id": null, "item_kind": null,
 "item_name": null, "game_code": null, "variant_code": null}

// GET /referrals/stats for A: before, then after
{"total_referrals": 1, "rewards_granted": 0}
{"total_referrals": 1, "rewards_granted": 1}
```

B's second pack paid nothing more (real). Wallet purchases with tokens or gold, and
subscriptions, don't count. What the app does: after a successful pack purchase, re-read the
balance (it includes the reward) and, if the invite screen is open, `GET /referrals/stats`.
The pack reply's `balances` already include the reward (real: B's sandbox reply showed
`"gold": 1000` = 500 start + 500 reward).

### 3e. Restore purchases

There is **no restore route**. What that means per item:

| Item | Restore |
|---|---|
| Token and gold packs | Consumables; nothing to restore. A purchase left pending is handed back by the store on the next start (3a, step 4). |
| Remove Ads | Owned on the account, not the device: `GET /sensitive/ad-free/status` after login is the restore. |
| Avatars and power-ups | Owned on the account: `GET /users/me/inventory`. |
| Subscriptions | Owned on the account: `GET /sensitive/subscriptions/my`. There is no way to link a store subscription bought on another device. |

Apple requires a "Restore Purchases" button for non-consumables and subscriptions. Put one in
settings that re-reads the three account routes above (and, once 3a works, calls
`restorePurchases()` and sends each result to `/iap/verify`).

---

## 4. Subscriptions (VIP)

Four tiers rank **free < silver < gold < royal**. Everyone is on free unless they hold an
active paid plan.

### 4a. Plans

`GET /sensitive/subscriptions/plans`. Plain array, cheapest first. Real (complete):

```json
[
  {"id": 1, "name": "Free Monthly", "tier": "free", "billing_interval": "monthly", "price_cents": "0", "duration_days": 30, "features": {}, "is_active": true},
  {"id": 2, "name": "Silver Monthly", "tier": "silver", "billing_interval": "monthly", "price_cents": "499", "duration_days": 30, "features": {}, "is_active": true},
  {"id": 4, "name": "Gold Monthly", "tier": "gold", "billing_interval": "monthly", "price_cents": "999", "duration_days": 30, "features": {}, "is_active": true},
  {"id": 6, "name": "Royal Monthly", "tier": "royal", "billing_interval": "monthly", "price_cents": "1999", "duration_days": 30, "features": {}, "is_active": true},
  {"id": 3, "name": "Silver Yearly", "tier": "silver", "billing_interval": "yearly", "price_cents": "4999", "duration_days": 365, "features": {}, "is_active": true},
  {"id": 5, "name": "Gold Yearly", "tier": "gold", "billing_interval": "yearly", "price_cents": "9999", "duration_days": 365, "features": {}, "is_active": true},
  {"id": 7, "name": "Royal Yearly", "tier": "royal", "billing_interval": "yearly", "price_cents": "15999", "duration_days": 365, "features": {}, "is_active": true}
]
```

| Field | Meaning |
|---|---|
| `id` | Send it as `plan_id`. |
| `name` | Built from tier and interval ("Gold Monthly"). Use your own translated text from `tier` and `billing_interval`. |
| `tier` | `free`, `silver`, `gold`, `royal`. |
| `billing_interval` | `monthly` or `yearly`. |
| `price_cents` | US cents as a **string**. |
| `duration_days` | 30 or 365 (the real period is one calendar month or year). |
| `features` | Empty today. Don't rely on it (4e). |

Show the free plan as "Current" for non-subscribers; it can't be bought.

### 4b. My subscription

`GET /sensitive/subscriptions/my`. **Two shapes**; tell them apart by `status`.

No paid plan (real):

```json
{"plan_id": 1, "tier": "free", "status": "default"}
```

An active paid plan (real, A after subscribing):

```json
{"id": "f9392fb1-16ff-4115-9718-a9bc89230bde", "user_id": "ee50efab-2d91-4ea6-8fa4-14b7b2638703",
 "plan_id": 4, "status": "active", "started_at": "2026-11-24T09:56:26.360989Z",
 "expires_at": "2026-12-24T09:56:26.360989Z", "cancelled_at": null, "auto_renew": true}
```

| Field | Meaning |
|---|---|
| `status` | `default` = free tier (first shape). `active` = paid. |
| `plan_id` | Look up tier and interval in the plans list (the paid shape has no `tier`). |
| `started_at`, `expires_at` | The current period. Show "Renews on" (if `auto_renew`) or "Ends on" `expires_at`. |
| `auto_renew` | The player's choice at subscribe time. Nothing renews automatically today (Known issue 3). |

Re-read it on app start, on resume, and after subscribe or cancel.

### 4c. Subscribe (development sandbox only)

`POST /sensitive/subscriptions/subscribe`

```json
{"plan_id": 4, "auto_renew": true, "sandbox_store": "apple"}
```

| Field | Rule |
|---|---|
| `plan_id` | Required. A paid, active plan. |
| `auto_renew` | **Required** boolean. |
| `sandbox_store` | Optional, `google` (default) or `apple`: which store the sandbox records. Development only; ignored in production. |

There is **no receipt field**: the server cannot take a store payment for a plan yet. With
`DEBUG_MODE` (development) it grants the plan at once; in production it answers `503
UNAVAILABLE` ("payment for plan 'Gold Monthly' cannot be verified yet", from the code).
Release builds: show the plans with "Coming soon"; don't start a store subscription.

**Success:** `200`. Real:

```json
{"subscription_id": "f9392fb1-16ff-4115-9718-a9bc89230bde", "plan_id": 4, "plan_name": "Gold Monthly",
 "started_at": "2026-11-24T09:56:26.360989Z", "expires_at": "2026-12-24T09:56:26.360989Z", "auto_renew": true}
```

No money moves and no ledger row is written (real). No `Idempotency-Key`: a double tap gets
`409` the second time, which is harmless.

**Errors** (real unless marked)

| Status | `error` | When | Show |
|---|---|---|---|
| 400 | `BAD_REQUEST` | The free plan (`the free plan is the default; no subscription is needed`); `auto_renew` missing. | App bug. |
| 404 | `NOT_FOUND` | No such plan, or inactive. | Reload the plans. |
| 409 | `CONFLICT` | Already has an active plan (`user already has an active subscription`), also for a different tier. | "You already have a plan." There is **no upgrade or downgrade route**: the player must cancel first. |
| 503 | `UNAVAILABLE` | Production: payment can't be verified (from the code). | "Subscriptions are coming soon." |
| 503 | `KILL_SWITCH_ENGAGED` | Store paused (from the code). | Show the `message`. |
| 403 | `GEO_BLOCKED` | Store closed in the region (from the code). | |

```json
{"error": "BAD_REQUEST", "message": "bad request: the free plan is the default; no subscription is needed"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: missing field `auto_renew` at line 1 column 14"}
{"error": "NOT_FOUND", "message": "not found: subscription plan not found"}
{"error": "CONFLICT", "message": "conflict: user already has an active subscription"}
```

### 4d. Cancel

`POST /sensitive/subscriptions/cancel`. No body. Real:

```json
{"id": "f9392fb1-16ff-4115-9718-a9bc89230bde", "user_id": "ee50efab-2d91-4ea6-8fa4-14b7b2638703",
 "plan_id": 4, "status": "cancelled", "started_at": "2026-11-24T09:56:26.360989Z",
 "expires_at": "2026-12-24T09:56:26.360989Z", "cancelled_at": "2026-11-24T09:56:29.327332Z", "auto_renew": false}
```

**Cancelling ends the plan at once**, not at `expires_at`: `GET /subscriptions/my` right after
answered `{"plan_id": 1, "tier": "free", "status": "default"}` (real), and there is no refund.
Warn the player before they confirm: "Your Gold benefits end now. This can't be undone."
(Known issue 4.) No active plan: `404 NOT_FOUND` `"not found: no active subscription"` (real).

### 4e. What a plan gives today

`features` is empty, so the app keeps the plan copy itself. What the server applies today,
from the code and the plan rows on the development database:

| Benefit | silver | gold | royal | Applied where |
|---|---|---|---|---|
| Daily bonus and bonus game prizes multiplied | x1.5 | x2 | x8 | `07-rewards.md` (daily bonus shows the multiplied amount). |
| Welcome bonus multiplier | by tier | | | Only for a plan held at sign-up, so in practice never. |
| VIP tables (modes with a minimum tier) | | | | Teen Patti, UNO and Roulette VIP rooms refuse a lower tier (each game's file). |
| Tournaments with a required plan | | | | `06-tournaments.md`. |
| Fewer or no ads | by operator rule | by operator rule | yes | `GET /me/ads/flow` (section 5c). Real: B on Royal got `"decided_by": "tier"` with every ad suppressed. Silver and Gold were not checked. |

Stored on the plan rows but **not applied anywhere** (from the code): the token and gold win
multipliers (taglines such as "4x tokens, 2x gold"), the yearly plans' welcome tokens (real:
B's balance did not change after Royal Yearly), and "includes ad-free" (real: B's
`/ad-free/status` stayed `is_active: false`). Don't promise these in the app until the server
owner confirms.

---

## 5. Ad-free

### 5a. Buy Remove Ads

Through the shop (section 2): `item_id` of the `ad_free` item, `quantity: 1`,
`currency: "gold"`. Real (A, after buying gold on the sandbox):

```json
{"purchase_id": 6, "item_id": 7, "quantity": 1, "total_price": 10000, "currency": "gold", "new_balance": "500"}
```

Ledger: a `purchase` debit with `item_kind: "ad_free"`, `item_name: "Remove Ads"` (real).
Buying again: `409 CONFLICT` `"conflict: already ad-free for good"` (real); show it as owned.
With `currency: "token"`: `400 VALIDATION_ERROR` `"item 7 cannot be bought with token"`
(real).

### 5b. Status

`GET /sensitive/ad-free/status`. Real, before and after:

```json
{"is_active": false, "granted_via": null, "expires_at": null}
{"is_active": true, "granted_via": "pass", "expires_at": null}
```

| Field | Meaning |
|---|---|
| `is_active` | Ad-free now. |
| `granted_via` | `pass` (bought in the shop), `purchase`, `subscription`, `promo` (granted by an operator), or `null`. Display only. |
| `expires_at` | `null` = for good; otherwise when it ends. |

Cached by the server for up to 5 minutes, but a purchase clears it (real: `true` at once).
Use it to show "Ads removed" on the Remove Ads card.

### 5c. Which ads to show

The ad decision lives in `GET /me/ads/flow` (owned by the ads work, not this module). It
combines ad-free, the subscription tier and operator rules, so **ask it, not
`/ad-free/status`, whether to show an ad**. Trimmed real replies:

```json
// A: Remove Ads bought. Banners and interstitials suppressed; rewarded ads stay (opt-in).
{"decided_by": "ad_free_pass", "effect": "rewarded", "stages": [
  {"stage": "lobby", "formats": [], "placements": [], "suppressed": [{"id": 2, "format": "banner", "suppressed_by": "ad_free_pass"}]},
  {"stage": "post", "formats": ["rewarded"], "placements": [{"id": 5, "code": "sample_post_rewarded", "format": "rewarded",
    "trigger_rule": "After a loss", "daily_cap": 0, "cooldown_s": 0, "skip_after_s": null, "refresh_s": null, "reward": "20 tokens"}], "suppressed": []},
  "..."]}

// B: Royal plan, no Remove Ads. Every ad suppressed by the tier.
{"decided_by": "tier", "effect": null, "stages": [
  {"stage": "lobby", "formats": [], "placements": [], "suppressed": [{"id": 2, "format": "banner", "suppressed_by": "tier"}]},
  "..."]}
```

Stages are `launch`, `lobby`, `pre`, `in`, `post`, `results`. Show only the `formats` and
`placements` a stage lists; nothing else. Re-read after a Remove Ads purchase, a subscribe or a
cancel. Note that the placement codes and rewards on development are sample data.

---

## 6. Avatars

The profile side (the picker, `PATCH /users/me/profile` with `avatar_id`, drawing an avatar
whose image isn't served) is in `02-profile-and-sessions.md` 3. This section is the buying.

### 6a. Catalogue

`GET /cosmetics/avatars`. Plain array of every active avatar. Real, trimmed:

```json
[
  {"id": 1, "code": "default_blue", "name": "Blue Buddy", "image_url": "/assets/avatars/default/blue.svg",
   "is_premium": false, "required_level": null, "is_purchasable": false, "sort_order": 1,
   "price_currency": null, "price_amount": null},
  {"id": 15, "code": "ludo_golden_crown", "name": "Golden Crown", "image_url": "/assets/avatars/ludo/golden_crown.svg",
   "is_premium": true, "required_level": 5, "is_purchasable": true, "sort_order": 201,
   "price_currency": "token", "price_amount": 500, "price_tier": "default", "regular_price": 500,
   "special_label": null, "special_until": null},
  {"id": 12, "code": "snl_shield_bearer", "name": "Shield Bearer", "image_url": "/assets/avatars/snl/shield_bearer.svg",
   "is_premium": true, "required_level": 15, "is_purchasable": true, "sort_order": 103,
   "price_currency": "gold", "price_amount": 25, "price_tier": "default", "regular_price": 25,
   "special_label": null, "special_until": null},
  {"id": 69, "code": "snl_charmed_token", "name": "Charmed Token", "image_url": "/assets/avatars/snl/charmed_token.svg",
   "is_premium": true, "required_level": null, "is_purchasable": false, "sort_order": 105,
   "price_currency": null, "price_amount": null}
]
```

| Field | Meaning |
|---|---|
| `price_currency`, `price_amount` | The wallet price in force (`token` or `gold`), or `null` when not sold. |
| `price_tier`, `regular_price`, `special_label`, `special_until` | As in 1c. Missing when not priced. |
| `required_level` | The player level needed to buy (6b). |
| `is_purchasable` | Sold here. `false` + `is_premium: true` = earned some other way (an achievement or a grant); show it locked with no price. |

Mark owned avatars from `GET /users/me/inventory` (`avatars[].avatar_id`).

### 6b. Buy

`POST /cosmetics/avatars/{id}/purchase`. No body; header `Idempotency-Key`. The price and
currency come from the catalogue.

**Success: `201`** (not `200`). Shape from the code (no test player reached level 5; the
numbers are an example):

```json
{"item_id": 15, "item_type": "avatar", "currency": "token", "amount_spent": 500, "new_balance": "150"}
```

A retry with the same key: the first reply, `201`, `Idempotent-Replayed: true`. The avatar
can also be bought as a shop item (section 2, category `avatar`); both give the same result.
Use one path per screen; the shop tab uses section 2, the avatar picker this route.

**Errors** (real unless marked)

| Status | `error` | When | Show |
|---|---|---|---|
| 400 | `BAD_REQUEST` | Not for sale (`item is not purchasable`), e.g. a free default avatar. | Don't offer Buy for it. |
| 403 | `LEVEL_REQUIRED` | Below `required_level`. Nothing is charged. | "Reach level 5 to unlock." |
| 404 | `NOT_FOUND` | No such avatar (`not found: avatar 999`). | Reload. |
| 409 | `CONFLICT` | Already owned (`already own this avatar`, from the code); key reused for another purchase. | Mark owned. |
| 409 | `INSUFFICIENT_FUNDS` | Not enough of `price_currency` (from the code). | "Not enough tokens." |
| 503 | `KILL_SWITCH_ENGAGED` | Store paused (from the code). | Show the `message`. |

```json
{"error": "LEVEL_REQUIRED", "message": "Requires level 5 (you are level 1)"}
{"error": "BAD_REQUEST", "message": "bad request: item is not purchasable"}
{"error": "NOT_FOUND", "message": "not found: avatar 999"}
```

### 6c. Equip

`POST /cosmetics/avatars/{id}/equip`. No body. Sets the profile avatar, like
`PATCH /users/me/profile` (`02-profile-and-sessions.md` 3). Real:

```json
{"avatar_id": 2, "equipped": true}
```

Errors (real): `400 BAD_REQUEST` `"you do not own this avatar"` for a premium avatar not
owned; `404 NOT_FOUND` `"not found: avatar 999"`. After equipping, re-read `GET /users/me` or
update the cached profile's `avatar_id`.

---

## 7. Power-ups

Power-ups belong to **one game** each (`game_id`). They are bought into the account
inventory and spent **inside a game** over that game's socket.

### 7a. Catalogue

`GET /cosmetics/power-ups?game_id=<numeric game id>`. Without `game_id`, every game's. Real
(Ludo is `game_id` 1; take ids from `GET /games` by `code`, `04-game-catalogue.md`), one item:

```json
{"id": 29, "game_id": 1, "code": "force_six", "name": "Force Six",
 "description": "Guarantee a 6 on your next dice roll.", "icon_url": "powerups/force_six.svg",
 "effect_config": {"effect": "force_six", "trigger": "pre_roll"}, "is_consumable": true,
 "max_per_match": 1, "sort_order": 2, "price_currency": "token", "price_amount": 100,
 "price_tier": "default", "regular_price": 100, "special_label": null, "special_until": null}
```

Ludo has four (real): `shield` (50 tokens, 2 a match), `force_six` (100, 1), `extra_turn`
(100, 1), `home_rush` (75, 2). Twelve games had power-ups on 24 Nov 2026.

| Field | Meaning |
|---|---|
| `code` | The name the game socket uses (`powerup_code`). |
| `icon_url` | A relative path that nothing serves (like avatars). Ship icons in the app keyed by `game code + code`. |
| `effect_config` | For display hints only; the game server applies the effect. |
| `max_per_match` | How many the player may use in one match. Show "1 per game". |
| `price_currency`, `price_amount` | Price of **one**. Packs in the shop (section 1) sell several at once. |

`game_id` that isn't a number: `400 BAD_REQUEST` (real). An unknown number returns `[]`.

### 7b. Buy one

`POST /cosmetics/power-ups/{id}/purchase`. No body; header `Idempotency-Key`. Adds **one**
to the inventory. **Success: `201`.** Real:

```json
{"item_id": 29, "item_type": "power_up", "currency": "token", "amount_spent": 100, "new_balance": "300"}
```

Replay: `201`, the same body, `Idempotent-Replayed: true` (real). Errors (real):
`404 NOT_FOUND` `"not found: power_up 999"`; `409 CONFLICT` for a reused key; from the code,
`409 INSUFFICIENT_FUNDS`, `400 BAD_REQUEST` `"item is not purchasable"` (no wallet price) and
`503 KILL_SWITCH_ENGAGED`. To buy several, use a shop pack (section 2) or call again with a
new key.

### 7c. Inventory

`GET /users/me/inventory` (`02-profile-and-sessions.md`). Real (A after a Ludo Shield x5 pack
and one Force Six):

```json
{"power_ups": [{"power_up_id": 28, "code": "shield", "name": "Shield", "game_id": 1, "quantity": 5},
               {"power_up_id": 29, "code": "force_six", "name": "Force Six", "game_id": 1, "quantity": 1}],
 "avatars": []}
```

Only quantities above 0 are listed. Re-read it after a purchase, and after each game (the
game spends from it).

### 7d. Using a power-up in a game

The app sends nothing to the gateway. In a game that allows power-ups, the player taps one and
the app sends the game's own socket action; the game server takes one from the inventory,
checks `max_per_match`, and applies it. For Ludo: `game.action` with `action_type:
"use_powerup"` and `powerup_code` (`games/ludo.md`, "Other actions"); the ack has
`remaining_quantity`. Each game's file names its action.

- Show the in-game power-up bar only when the room's rules allow power-ups (Ludo:
  `rules.powerups_allowed`) and only codes with `quantity > 0` for that game.
- The socket refusals carry messages such as `no 'shield' power-ups remaining` and `'shield'
  usage limit reached (2 per match)` (from the shared code); grey the button out.

**Don't call `POST /cosmetics/power-ups/{id}/use`.** It takes one from the inventory with no
game, no match and no per-match limit: the power-up is simply lost. Real:

```json
{"power_up_id": 29, "remaining_quantity": 0}
{"error": "BAD_REQUEST", "message": "bad request: no power-ups remaining"}
```

---

## Errors

The error body and the shared codes are in `00-conventions.md`, "Errors". Store additions:

| Status | `error` | Routes | What the app does |
|---|---|---|---|
| 403 | `LEVEL_REQUIRED` | Avatar purchases (2, 6b). | "Reach level N"; `N` from `required_level`. |
| 409 | `INSUFFICIENT_FUNDS` | Every wallet purchase. | "Not enough gold / tokens"; offer coin packs (development: sandbox). |
| 409 | `CONFLICT` | Already owned; already subscribed; key reused. | Owned: show as owned. Key: app bug. |
| 409 | `DUPLICATE_TRANSACTION` | `/iap/verify` (once it works). | Success: finish the store transaction. |
| 503 | `UNAVAILABLE` | `/iap/verify` always; sandbox and subscribe in production. | "Coming soon"; never retry in a loop. |
| 503 | `KILL_SWITCH_ENGAGED` | Shop purchase, sandbox, avatar and power-up purchase, subscribe. | Show the operator's `message`; disable Buy. Browsing, status reads and cancel keep working. |

The store switch is also engaged by the operator's platform-wide switch (from the code).
Real `KILL_SWITCH_ENGAGED` bodies were not captured (switching it needs the console); the shape
is `{"error": "KILL_SWITCH_ENGAGED", "message": "<operator text>"}`.

---

## Limits

| What | Limit |
|---|---|
| All routes | The general limit, about 100 requests a minute per player. |
| `quantity` | 1 to 100 per purchase. |
| `Idempotency-Key` | 1 to 100 printable ASCII characters. |
| Catalogue reads | Cache the shop, avatars, power-ups and plans for the session; reload on pull to refresh, when a special ends, and on `404` for an item. |

---

## Known issues (the app must cope)

1. **Store purchases can't be verified.** `/iap/verify` always answers `503`, and
   subscriptions take no receipt. Don't take real money in release builds (section 3).
2. **`/iap/verify` credits tokens only.** Its code credits a token amount and nothing else, so
   a gold pack or Remove Ads bought through it would give nothing. Also, the store product ids
   are not in the shop API (3a). Reported to the lead.
3. **No renewal.** `auto_renew` is stored, but nothing renews a plan; it ends at `expires_at`.
4. **Cancel ends the plan at once** although `expires_at` stays a month away (real). Warn
   before cancelling. There is no upgrade route either (`409` until cancelled).
5. **Remove Ads has a dollar price but can only be bought with gold.** Show the gold price.
6. **Remove Ads' `regular_price` is in cents, not gold** (real: `price_gold: 10000`,
   `regular_price: 299`). When an item has both a wallet price and `price_usd_cents`,
   `regular_price` and `price_tier` describe the **dollar** price. Show a struck-through
   regular price only when `regular_price` is in the same unit as the shown price (no
   `price_usd_cents`, or a `usd` item).
7. **Plan benefits are not in the API** and several stored ones are not applied (4e). Keep
   the copy in the app and promise only what 4e lists as applied.
8. **Two money shapes.** `new_balance` and `price_cents` are strings; `balances`,
   `amount_spent`, `total_price` and the ledger are numbers. Parse both.
9. **Two success codes.** Shop routes answer `200`; `/cosmetics/.../purchase` answers `201`.
   Treat any 2xx as success.
10. **Image paths aren't served.** `image_url` and `icon_url` are relative paths with no file
    behind them (`02-profile-and-sessions.md`, Known issues). Bundle the art in the app.
11. **The key conflict message says "purchase"** on every route. Decide on `error`, never on
    `message`.

---

## Done when

- [ ] The Shop shows Coins, Power-ups, Avatars and Remove Ads from `GET /sensitive/shop/items`,
      each with the price in force, offer and special badges, and a countdown that reloads
      when a special ends.
- [ ] Buying a power-up pack charges the right currency, updates the balance chip from
      `new_balance`, and the inventory shows the new quantity.
- [ ] Every buy sends a new `Idempotency-Key`; a timeout retries once with the same key; a
      replayed reply is shown as success.
- [ ] `INSUFFICIENT_FUNDS`, `LEVEL_REQUIRED`, already owned (`409`) and
      `KILL_SWITCH_ENGAGED` each show their own message.
- [ ] Release builds start no store payment and show coin packs and plans as "Coming soon";
      debug builds buy coin packs through the sandbox route and show the ledger rows
      `iap_token_pack` / `iap_gold_pack`.
- [ ] A player who signed up with a referral code gets the 500 gold reward on the first coin
      pack, visible in the balance and the ledger; the referrer's stats move.
- [ ] The `IapBridge` is written against 3a (verify, then complete; `409
      DUPLICATE_TRANSACTION` counts as success; pending purchases resent on start) but
      switched off.
- [ ] The VIP screen shows the plans, the current plan in both shapes, subscribe (debug) and
      cancel with the "ends now" warning.
- [ ] Remove Ads can be bought for gold once; the card then shows "Ads removed"; ads follow
      `GET /me/ads/flow`.
- [ ] The avatar picker shows owned, free and locked avatars with level and price; Buy and
      Equip work; Equip on a locked one is never offered.
- [ ] The game's power-up bar shows only that game's owned power-ups and spends them over the
      socket; the app never calls `/cosmetics/power-ups/{id}/use`.
- [ ] A "Restore Purchases" button re-reads ad-free, inventory and subscription.
- [ ] No store body, receipt or purchase token appears in any log.

---

## Test accounts

Create your own players on the development server with `POST /auth/register` (any
`@example.com` email), as in `01-auth.md`. Each starts with 100 tokens and 500 gold; in a
debug build, top up with the sandbox coin packs (3c). Avatars for sale need player level 5
or more, so a new player sees `LEVEL_REQUIRED`; play games to level up
(`08-progress-and-history.md`). To see the referral reward, sign the second player up with the
first one's code and buy one sandbox pack. Don't use other people's accounts.

The samples in this file came from two players made for it on 24 Nov 2026:
`w11doca1795514090` (A, `ee50efab-2d91-4ea6-8fa4-14b7b2638703`: Ludo power-ups, Remove Ads,
Gold Monthly subscribed then cancelled) and `w11docb1795514207` (B,
`4fcbb8fe-3b3b-4c75-8b0b-9c1dd30b4807`: signed up with A's code `2J1O2COW`, two sandbox packs,
Royal Yearly active).
