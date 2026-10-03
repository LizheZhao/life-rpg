# Rewards

The Rewards tab shows the coin balance and the user's hand-entered rewards (name, estimated real-world cost, coin price derived from it). A reward can be redeemed, pinned as the savings goal, edited or archived; a missed day offers a streak freeze. Every spend goes through one balance check.

## Sub-features

- `rew-balance` the `Coins` total equals the ledger sum.
- `rew-add` `+` (or the empty state's `Add a reward`) opens `New reward` (Name, Estimated cost → coin price pill, `Saving for this` toggle), `Save`.
- `rew-redeem` `Redeem` asks to confirm and writes a ledger row.
- `rew-goal` `⋯` → `Set as goal` / `Unpin goal`; the reward moves to a `Saving for` card with a progress bar (`Ready to redeem` when affordable) and the goal shows as a bar on Today's level card.
- `rew-freeze` a `Streak` section offers `Freeze · <cost>` for a missed day.

## How to get to it (user POV)

- Tap the Rewards tab; tap `+` (Add a reward) top-right, or `Add a reward` on the empty card; tap `⋯` on a reward card (or long-press it) for Set as goal / Edit / Archive, in that order. There are no swipe actions.

## Driving it with the simulator

Preconditions: `V up --fresh`. A reward must cost at most the balance: the coin price is ceil(cost × 10) up to 500, so on the fresh 100 coins a cost of 10 or less is affordable. Use cost 2 (20 coins).

- **Balance.** Tap Rewards (x=250 pt, y=880 pt). The `Coins` card equals `V ledger`'s balance (100 on a fresh store); with no rewards a card `Something worth saving for` with an `Add a reward` button shows.
- **Add.** Tap `Add a reward` (about 220, 517 pt). Tap `Name` (about 220, 216 pt) and type `Tea`; wait for the text to land, then tap `Estimated cost` (about 220, 344 pt) and type `2`. The pill reads `20 coins`. `Save` stays disabled until the name is non-empty and the cost is above 0; with the number pad up it sits at about 220, 602 pt. Tap it. `V sql "select ZNAME, ZESTIMATEDCOST, ZISACTIVE, ZISGOAL, ZFIXEDCOINS from ZREWARD"` returns `Tea | 2.0 | 1 | 0 | NULL`, and a card `Tea`, `20 coins`, `≈ 2`, `Redeem` shows.
- **Goal.** Tap `⋯` on the card (about 390, 360 pt): the popover lists `Set as goal`, `Edit`, `Archive`. Tap `Set as goal` (about 205, 316 pt). The card moves under `Saving for` with `saving for`, a full bar and `Ready to redeem`; `ZISGOAL` is `1`.
- **Redeem.** Tap `Redeem`: a centered card (the reward's disc and name, `20 coins`, an ink `Redeem 20` pill, `Not yet`; the tab bar fades out). Wait for it to open (a tap during the animation is swallowed) and tap `Redeem 20` (about 220, 490 pt). `V ledger` shows `redeem | -20 | <app day> | Tea`, the balance drops by 20, `ZISGOAL` returns to `0`, and Tea appears under `Redeemed` (`-20`) while staying in the list. `Not yet` or a tap on the dim leaves the ledger alone; with too few coins the button is disabled.
- **Freeze (not driven).** A `Streak` card reads `Missed <day>` with `Freeze · <n>` (300 coins, or 150 from Lv 20; free once a month from Lv 10). It needs a completed day, a missed day after it (`V day 2`) and 300 coins, so a fresh store shows it disabled (`Costs 300, balance is 100`). The confirm pill is `Spend <n>` and the ledger row is `freeze`, dated the missed day.

## Gotchas

- A fresh store has only 100 coins; look at the previewed coin price before saving.
- Reward and goal pricing are Core rules (`RewardPricing`, `SavingsGoal`); prove numbers with `swift test`.
- The goal bar on Today's level card is written from the view source and was not looked at in this pass.
- After switching tabs the first tap is often swallowed; if a redeem card did not open, screenshot before tapping again.
- Redeeming also unpins the goal. Cancelling a quest or routine writes `redeem`-kind rows too, but only rows whose `refID` is a reward id appear under `Redeemed`.
