# Rewards

The Rewards tab shows the coin balance and the user's hand-entered rewards (name, estimated real-world cost, coin price derived from it). A reward can be redeemed, pinned as the savings goal, edited or archived; a missed day offers a streak freeze. Every spend goes through one balance check.

## Sub-features

- `rew-balance` the coin total equals the ledger sum.
- `rew-add` `+` opens `New reward` (Name, Estimated cost → coin price), `Save`.
- `rew-redeem` `Redeem` asks to confirm and writes a ledger row.
- `rew-goal` swipe → `Set as goal` / `Unpin goal`; the goal shows as a bar at the bottom of Today's level card.
- `rew-freeze` a `Streak` section offers `Freeze · <cost>` for a missed day.

## How to get to it (user POV)

- Tap the Rewards tab; tap `+` (Add a reward) top-right; swipe a reward row for Set as goal / Archive / Edit.

## Driving it with the simulator

Preconditions: `V up --fresh`.

- **Balance (driven).** Tap Rewards (x=220 pt). The balance equals `V ledger`'s balance (100 on a fresh store).
- **Add (not yet driven).** Tap `+`, tap `Name`, type a name, tap `Estimated cost`, type a number; the sheet previews `<n> coins`. Tap `Save`. Then `V sql "select ZNAME, ZESTIMATEDCOST from ZREWARD"` must return the row.- **Redeem (not yet driven).** With enough coins, tap `Redeem` → alert text `<name>\n\n<n> coins. This is final.` → the spend button. A negative ledger row appears and the balance drops by that price; with too few coins the action is blocked.

## Gotchas

- A fresh store has only 100 coins; a reward must be cheap (low estimated cost) to redeem. Look at the previewed coin price before saving.
- Reward and goal pricing are Core rules (`RewardPricing`, `SavingsGoal`); prove numbers with `swift test`.
- The authoring run drove only the balance; add and redeem steps are written from the view source (`LifeRPG/RewardsView.swift`) and need a first real pass.
