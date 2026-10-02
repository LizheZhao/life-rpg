# Today: complete a quest

The Today tab is a scroll of cards: header (avatar, `+`), greeting, level card, an `Epic` section with a routine-style card (tap the body to expand), Routines (full-width rows), Today's quests (full-width tinted rows), a `Hidden` section, then Completed, Ahead this week (a stack, like Completed) and Backlog. The round complete button on a quest or routine row asks for confirmation, writes a ledger entry, plays the payout reveal (quests only) and offers a rating. The coin count on the level card must equal the ledger.

## Sub-features

- `today-render` shows the level card, the epic card, `Routines`, `Today's quests` for the app day.
- `today-complete` completes a random slot: alert, payout card, ledger row, level card update, hand line `1 day streak`.
- `today-rate` logs a rating (−2…+2) from the payout card.
- `today-routine-complete` completes a routine row (open, and its late/lighter variants).
- `today-menu` the `⋯` on a quest row, a routine row and the epic card lists Reroll / Cancel / Replace / Extend with prices; a blocked item is greyed out without a price. The same items are in the long-press context menu.
- `today-ahead` the `Ahead this week` header (`5 open`, clay `−13 Sun night`) over a stack of rows; tap the stack or the header to fan out, `Collapse` to fold; `Do now` on a candidate raises `Mark as done?` and a `routine` ledger row follows. Weekdays start collapsed, Saturday and Sunday open.
- `today-add` the `+` sheet adds an ad-hoc routine from the library.
- `today-levels` the level card (or the avatar) opens the Levels sheet.
- `today-completed` a done card leaves its section (0.9 s later) for the `Completed` stack after Today's quests / Hidden: header `<n> done · +<sum>` equals the done ledger rows, tap the stack or the header to fan out, `Collapse` or the header to fold, collapsed again after `V relaunch`. A section with nothing open reads `cleared` under its header.

## How to get to it (user POV)

- Open the app; the Today tab is first.
- Tap the round button on a quest or routine row.
- Tap `⋯` on a row or the epic card (or long-press it) for Reroll / Replace / Cancel / Extend; tap `+` (Add for today) top-right.
- Tap the level card or the avatar to open the level track sheet.

## Driving it with the simulator

Preconditions:

- `V up --fresh`; `V doctor` shows `offset: 0` and note `app day`.
- The level card reads `100 coins`, `60 to Lv 2`, `normal day`, `3 random slots`; the hand line has no streak part.

- **Open the alert.** Scroll until a quest row is visible (rows are tinted, pill shows a range such as `5–15`). Tap its round button. The alert `Mark as done?` shows the quest text and `This is final — completion cannot be undone.`
- **Complete.** Tap `Complete` (right button, about x=294 pt, y=558 pt). The payout card shows `+<points>` and `How did that feel?` with five thumbs. Capture `V shot today-complete-reveal`.
- **Rate.** Tap the right-most thumb (about x=324 pt, y=585 pt). The card dismisses.
- **Read the stored result.** Run `V ledger | tee build/verify-evidence/today-complete-ledger.txt`. A `quest` row for today with the points shown on the card appears, and the balance equals 100 + those points. Run `V sql "select ZRATING, ZTARGETKINDRAW, ZTEXTSNAPSHOT from ZQUESTRATING"`: one row, rating `2`, the quest's text.
- **Check the page.** Screenshot Today: the level card's coins equal the ledger balance, the hand line ends `1 day streak`, the row shows a drawn check, a struck-through title and `+<points>` in its pill. Capture `V shot today-complete-after`.
- **Menu purchase.** Tap `⋯` on an open quest row: `Reroll · <price>`, `Cancel` (greyed while the balance is too low), `Replace`, and `Open link` when the quest has a link. Tap `Reroll`, then `Spend <price>`. `V ledger` shows a `reroll` row of `-<price>`.
- **Routine.** Tap the round button on a routine row, then `Complete`: the pill reads `+<n>`, no reveal; `V ledger` has a `routine` row.

## Gotchas

- Payout points are drawn once at completion, within the band on the row's pill (e.g. `5–15`). Assert the band and that the card, the row and the ledger agree — not a fixed number.
- Completion is final. To repeat the recipe use `V up --fresh`, not Debug → Reopen today (that is a test aid, not an app behavior to prove).
- Tapping a thumb is optional only in the sense that the card can be left up; the rating row exists only if you tap one.
- "Clear every slot to unlock" below the quest rows is the hidden quest's gate; it becomes `Reveal the hidden quest` only after all slots are done.
- Overdue (`overdue · day 2`), backlog and the Ahead section need `V day <N>`; on a weekend Ahead opens by itself. The swipe actions are gone: nothing on Today responds to a swipe except scrolling.
- Every state of the cards without time travel: Settings → Design gallery (the row sits at about y = 672 now that Workout detection has its own row; check a screenshot). Sections, top to bottom: `Completed stack` (FIRST), `Ahead stack`, colours, type … and `Today cards` last. A flick from y=800 to y=120 scrolls about one screen. Start swipes above y=840: the floating bar swallows gestures that begin on it.
