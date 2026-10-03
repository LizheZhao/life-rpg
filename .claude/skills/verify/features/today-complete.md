# Today: complete a quest

The Today tab is a scroll of cards: header (avatar, `+`), greeting, level card, an `Epic` section with a routine-style card (tap the body to expand), Routines (full-width rows), Today's quests (full-width tinted rows), a `Hidden` section, then Completed and Ahead this week (each a stack). There is no Backlog section: routines that ran out their day are pinned at the top of Routines as `overdue · day N`, and the missed ones are listed on the Calendar's `Did not finish` card. The round complete button on a quest or routine row asks for confirmation, writes a ledger entry, plays the payout reveal (quests only; a routine's fixed payout goes straight to `+N` and `paid`) and offers a rating, all in one centered card. The coin count on the level card must equal the ledger.

## Sub-features

- `today-render` shows the level card, the epic card, `Routines`, `Today's quests` for the app day.
- `today-complete` completes a random slot: the centered card (`?` + `Complete` + `Not yet`), then in place rolling, landed (`+N`), rate; ledger row, level card update, hand line `1 day streak`.
- `today-rate` logs a rating (−2…+2) from the card's rate phase (pick, then `Done`; a tap on the dim or 8 s later leaves with the pick, or without one).
- `today-routine-complete` completes a routine row (open, and its late/lighter variants).
- `today-menu` the `⋯` on a quest row, a routine row and the epic card opens a popover of Reroll / Cancel / Replace / Extend, each with a price pill (`10 coins`, or `free`); a blocked item is greyed out and keeps its pill. The same items are in the long-press context menu.
- `today-ahead` the `Ahead this week` header (`6 open`, clay `−13 Sun night`) over a stack of rows; tap the stack or the header to fan out, `Collapse` to fold; `Do now` on a candidate raises the same centered card (header, `+N` pill, `Complete`, `Not yet`) and a `routine` ledger row follows. Weekdays start collapsed, Saturday and Sunday open.
- `today-add` the `+` sheet adds an ad-hoc routine from the library.
- `today-levels` the level card (or the avatar) opens the Levels sheet (`Levels`, a perk list, a full-width `Done` pill at the bottom, about 220, 890 pt).
- `today-completed` a done card leaves its section at once for the `Completed` stack after Today's quests / Hidden: header `<n> done · +<sum>` equals the done ledger rows, tap the stack or the header to fan out, `Collapse` or the header to fold, collapsed again after `V relaunch`. The section it left reads `<n> / <m> done`, or `cleared` when nothing is open.

## How to get to it (user POV)

- Open the app; the Today tab is first.
- Tap the round button on a quest or routine row.
- Tap `⋯` on a row or the epic card (or long-press it) for Reroll / Replace / Cancel / Extend; tap `+` (Add for today) top-right.
- Tap the level card or the avatar to open the level track sheet.

## Driving it with the simulator

Preconditions:

- `V up --fresh`; `V doctor` shows `offset: 0` and note `app day`.
- The level card reads `100 coins`, `60 to Lv 2`, `normal day`, and `<n> random slots`; the hand line has no streak part. The slot count follows the day's routine load: 3 on a quiet weekday, 1 on a Saturday (6 routines), 2 on a Sunday (4).

- **Open the card.** Scroll until a quest row is visible (rows are tinted, pill shows a range such as `5–15`). Scroll with a swipe that starts around y=760 pt and ends at 200–300 pt. Tap the quest's round button (the first tap after a card closes or the app launches is often swallowed; screenshot and repeat). A centered card appears on a dimmed page with the quest's disc and title, a `?` box, `Complete` and `Not yet` (the tab bar fades out). A tap on the dim, like `Not yet`, closes it and leaves the ledger alone.
- **Complete.** Tap `Complete` (about x=220 pt, y=545 pt for a one-line title). The card turns in place: range pill and blurred numbers scrolling (about 1.5 s), then `+<points>` with `paid` (a tap on the dim skips the roll), then after 0.9 s `how did that feel?` with five round buttons and `Done`. Screenshots with `V shot` lag less than the control tool's. Capture `V shot today-complete-reveal`.
- **Rate.** Tap a button (the right-most is `Loved it`: about 320, 519 pt on a quest card), then `Done` (about 220, 574 pt). The rating row is written when the card closes. The 8 s idle timer starts when the rate phase appears and restarts on every pick, and the control tool plus a screenshot read takes longer than that: **reading a screenshot between `Complete` and the thumb loses the rating** (the card closes and the taps land on the page). Take the screenshot for the proof first, or tap `Complete` → thumb → `Done` back to back using the coordinates above. For a routine card they are about 320, 540 and 220, 595.
- **Read the stored result.** Run `V ledger | tee build/verify-evidence/today-complete-ledger.txt`. A `quest` row for today with the points shown on the card appears, and the balance equals 100 + those points. Run `V sql "select ZRATING, ZTARGETKINDRAW, ZTEXTSNAPSHOT, ZQUESTID is not null from ZQUESTRATING"`: one row, rating `2`, `quest`, the quest's text, `1`.
- **Check the page.** Screenshot Today: the level card's coins equal the ledger balance, the hand line ends `1 day streak`, `Completed` reads `1 done · +<points>` and its top card shows a drawn check, a struck-through title and `+<points>` in its pill. Capture `V shot today-complete-after`.
- **Menu purchase.** Tap `⋯` on an open quest row: `Reroll` (pill `10 coins`), `Cancel` (greyed while the balance is too low, pill kept, e.g. `120 coins`), `Replace`, and `Open link` when the quest has a link. Tap `Reroll`: a card `Reroll?` with "Swap it for a different <tier> for 10 coins. The next reroll of this slot today costs more.", `Spend 10`, `Not yet`. Tap `Spend 10` (about 220, 503 pt). `V ledger` shows a `reroll` row of `-10` dated the app day, note `Reroll: <old title>`; `V sql "select ZSLOTRAW, ZTEXTSNAPSHOT, ZREPLACED, ZREPLACEDREASONRAW, ZREROLLCOUNT from ZDAILYQUEST where ZDAYKEY='<day>'"` keeps the old row with `ZREPLACED=1` and `rerolled`, and adds a new row of the same tier with `ZREROLLCOUNT=1`. At Lv 3 the first reroll is `free` and the button reads `Use free reroll`.
- **Routine.** Tap the round button on a routine row: the card has the routine's disc and title, a `+<n>` pill and no `?` box. `Complete` turns it (a short fade, no roll) into the big `+<n>`, `paid`, `how did that feel?` and `Done`; `<n>` equals the `routine` row in `V ledger`. The completed row shows an extra pill such as `1 strike this week`. A rating is filed as `routine` in `ZQUESTRATING` with `ZQUESTID` = the occurrence's id. The same holds for `Do now` on an Ahead row (needs a Saturday or `V day`).

## Gotchas

- Payout points are drawn once at completion, within the band on the row's pill (e.g. `5–15`). Assert the band and that the card, the row and the ledger agree — not a fixed number.
- Completion is final. To repeat the recipe use `V up --fresh`, not Debug → Reset today / Reopen quests (those are test aids, not an app behavior to prove).
- A rating is optional: the card closes by itself 8 s after the rate phase appears or after the last pick, and the rating row exists only if one was picked.
- The streak counts only random quests: a routine or epic completion does not produce `1 day streak`.
- "Clear every slot to unlock" below the quest rows is the hidden quest's gate; it becomes `Reveal the hidden quest` when its condition is met. Observed: it stayed locked after the day's only random slot was done while routines were still open, so whether routines also gate it is unconfirmed here.
- A level-up or streak-milestone card can pop up after the rating card closes and blocks the next tap (from the source; not reached in this pass).
- A scroll gesture opened the Levels sheet once right after launch (a swipe from 700 to 160 pt); it did not repeat. If a sheet appears, close it with `Done` and scroll again.
- Overdue (`overdue · day 2`) and the Ahead section need `V day <N>`; on a weekend Ahead opens by itself. The swipe actions are gone: nothing on Today responds to a swipe except scrolling.
- Every state of the cards without time travel: Settings → Design gallery (the row sits at about y = 795 pt at the top of Settings; check a screenshot). Sections, top to bottom: `Completed stack` (FIRST), `Ahead stack`, colours, type … and `Today cards` last. A flick from y=800 to y=120 scrolls about one screen. Start swipes above y=840: the floating bar swallows gestures that begin on it.
