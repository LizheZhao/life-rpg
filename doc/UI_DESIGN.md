# Life RPG — UI design

Refined from `LifeRPG UI 设计规范与 UIKit Implementation Plan.md` (the original exploration, UIKit-based). **What was kept:** the visual language. **What changed:** everything that assumed UIKit, Core Data, an XP engine or attributes. The decisions below were made with the user on 2026-10-02 after comparing three throwaway variants of the Today page; variant **A (soft pastel, hand-drawn)** won.

## Decisions

| Topic | Decision |
|---|---|
| Framework | SwiftUI over the existing SwiftData + `LifeRPGCore`. No UIKit rewrite, no Core Data, no Combine, no Coordinator, no `XPEngine`. |
| Concept mapping | Home = Today. Coins / level / streak / savings goal live in the level card. Weekly **epic** = a routine-style row with a flag in its disc (it has no phases: its segments are the 7 days of the week). No attributes (STR/INT…) and no XP: colour follows **difficulty**. |
| Epic weight | The epic is a **routine-style card**: same white surface, radius and layout as a routine row, never a dark or separate hero card. Its title shows in full and a tap on the card expands the detail. Routines and today's quests are the focus of the page. |
| Appearance | Follows the system (light / dark automatically). Every colour token has a light and a dark value. |
| Tabs | Floating tab bar, four tabs: **Today, Calendar, Rewards, Settings**. Debug becomes a section of Settings (simulator/dev tools); Library becomes a page inside Settings; the export / restore menu moves from Today's toolbar into Settings. |
| Completion | Completion is final (`PLAN.md` §3): no Undo, no reverse animation, no Undo toast. The existing confirm alert stays. |
| Doodles | Drawn in code as SwiftUI `Path`s in a 100×100 box (stroke 3.5, round caps and joins), so static icons and the draw-on animation (`trim`) share one mechanism. No PDF pipeline. |
| Per-quest icon | No `iconKey` in the model (that would be `SchemaV4`). Core owns a keyword → `DoodleKey` table with a generic default. |
| Fonts | Plus Jakarta Sans and Caveat (SIL OFL, in `LifeRPG/Fonts/`), registered at launch with `CTFontManagerRegisterFontsForURL` (no Info.plist or pbxproj edit). Both are variable fonts: weights are applied through the `wght` variation axis. All text scales with Dynamic Type. |
| Swipe actions | Reroll / replace / extend / cancel are swipe actions in a `List` today. Tiles in a grid cannot swipe, so each card gets a trailing `⋯` `Menu` (and a context menu) carrying the same actions, greyed out under the same Core rules (`Purchase.blocked`). |

## Tokens

All colours are semantic names with a light and a dark value, defined once in Core (`Palette`, hex ints) and wrapped in SwiftUI `Color` by the app. Views never contain a hex literal. Required contrast (WCAG 4.5:1 for text) is asserted in Core tests for every foreground/background pair, in both appearances.

| Token | Light | Dark (proposal, the contrast test decides) | Use |
|---|---|---|---|
| `canvas` | #F6F3F1 | #151517 | screen background |
| `surface` | #FFFFFF | #212125 | cards, rows, tab bar |
| `ink` | #18181B | #F4F1EE | primary text, stroke of doodles |
| `inkSecondary` | #6B6B73 | #A5A5AD | secondary text on canvas / surface |
| `inkOnTint` | #3F3F46 | #D8D5D1 | secondary text on a pastel tile (`#6B6B73` fails on the sky tile) |
| `inkHand` | #55555D | #B8B8C0 | Caveat labels |
| `fill` / `onFill` | #18181B / #FFFFFF | #F4F1EE / #151517 | selected state, done complete-button, filled week segments |
| `dotEmpty` / `dotFill` | #DAD5D0 / #8ED1B4 | #3A3A40 / #7CC4A6 | level dot grid, empty week segments |
| `tintTrivial` | #BFE8D6 | #2F4A3F | trivial tile (mint) |
| `tintEasy` | #B9E3F4 | #2C4655 | easy tile (sky) |
| `tintMedium` | #F4E29A | #55482A | medium tile (butter) |
| `tintHard` | #F7D9DE | #573640 | hard tile (blush) |
| `tintHidden` | #D4D6FF | #3A3C5E | hidden quest (lavender) |
| `clay` / `clayBg` | #A8502F / #F3DDD2 | #E8A183 / #4A2E22 | overdue and negative balance — never alarm red |
| `avatarPink` | #F7C6D4 | #6B3F4C | avatar disc |

Type styles (Jakarta unless noted; each wraps `UIFontMetrics`): `displayGreeting` 32 Light with an ExtraBold emphasis word, `displayLevel` 52 Light, `titleCard` 22 Bold, `heading` 17 Bold, `bodyStrong` 15 SemiBold, `caption` 13 Regular, `pill` 12 SemiBold, `hand` Caveat 22 Medium. Radii: card 28, tile 26, row 24, pill 12, tab bar 34; all `.continuous`. Insets 22, section gap 14, grid gap 10. Only the floating tab bar has a shadow.

## Today page

Order: header (avatar, add, no export menu) → greeting (Caveat "day N · M day streak", Jakarta line with squiggle under the emphasis word) → level card → **epic** → Routines → Today's quests (and Hidden) → **Completed** → Ahead this week → Backlog.

- **Level card.** Level number, coins, "N to Lv X", 20-dot grid = progress to the next level (each dot 5 %), tier / slot pills, savings-goal bar. The fraction is a Core function, not computed in the view.
- **Epic.** Under its own section header (`Epic`, hand label `this week`), a routine-style row on the surface card: flag doodle in the disc, the title in full (it wraps like a routine title), pills for the reward range, `N days left` (`last day` on the final day, counted by `DayKey` from `Epic.lastDayKey`) and `extended 1/2`, a `⋯` menu (reroll / extend / replace / open link) and the 44 pt complete button. The 7 thin segments (days of the week elapsed, `dotEmpty` empty, `fill` filled) run along the bottom of the card. A tap on the card body expands the detail (`Day 5 of 7 · due Sun Oct 4`, extensions used of the maximum, the drawn value, the link) with a chevron that rotates; nothing is persisted and the body tap never completes.
- **Routines.** Full-width rows: doodle disc, title, pills (`+points`, `N strikes this week` from `Schedule.doneThisWeek`, overdue, lighter version), `⋯` menu, complete button. Auto-verified routines say so only to VoiceOver. Overdue shows a clay pill ("overdue · day 2", the halved payout). Done rows get strikethrough and the filled check.
- **Today's quests.** Two-column grid of tinted tiles, tint = difficulty. The pill shows the **range only** (`5–15`), not the word. The hidden quest (its gate or the revealed tile) sits under its own `Hidden` section header, and the trivial group is a full-width tile. At accessibility text sizes the grid becomes one column.
- **Open sections show only open items.** A card that is done leaves its section. When every item of a section is done the header stays with the hand label `cleared` and no cards (no empty card), so progress is still visible: `Epic · cleared`, `Routines · cleared`, `Hidden · cleared`. A section with something still open keeps `1 / 3 done`, counted over all its items (skipped rows count in the total, never as done). Core: `SectionProgress.handLabel`, `EpicCardState.sectionLabel`.
- **Completed (stacked cards).** One section after Today's quests / Hidden and before Ahead this week, hidden entirely when nothing is done. Header `Completed`, hand label `4 done · +160` (the sum of the points each row was paid, never recomputed). Collapsed: the most recent card with up to two slabs peeking behind it and `+N more`. A tap on the stack or the header fans it out (0.3 s spring; Reduce Motion: 0.2 s fade) into the normal done rows plus a `Collapse` button. Collapsed is the default and the state after a relaunch (`@State` in `TodayView`, not stored). Who is in it: today's completed random quests (they keep their tint), the hidden quest and a finished micro-action group, completed routines (due today, or finished late today), and the week's epic once done. Not in it: skipped, replaced and cancelled rows, routines done ahead (they stay under Ahead this week) and the backlog. Order: most recently completed first, by `completedAt` (every quest and routine occurrence carries one), ties by title. Core: `CompletedStackState`. Done rows have no menu and complete nothing; a tap does nothing except on the epic, which still expands.
- **Moving into the stack.** A card that has just been completed stays in its section for 0.9 s (`TodayView.settling`) so the check, the strikethrough and the floating `+N` finish where the tap was, then leaves its section (fade and slight shrink) while the stack grows (0.3 s; Reduce Motion: 0.2 s fade only). The confirm alert, the payout reveal and the haptic are untouched.
- Backlog, "do ahead" and the Sunday bill keep their current content, restyled as rows.

## Motion and haptics

Complete: button fills, check draws on (0.25 s ease-out), "+N" floats up, new level-dots fill in sequence, medium impact haptic. Press: scale 0.97 spring. Level up: success notification haptic; the existing level card moment stays. Squiggle draws on once at first appearance. With Reduce Motion on, every animation becomes a 0.2 s cross-fade. Bold Text raises each style one weight step.

## Accessibility

Contrast ≥ 4.5:1 for text (tested in Core), hit targets ≥ 44 pt, Dynamic Type through the largest accessibility size without truncating the title or points. Each tile and row is one VoiceOver element ("Walk 8,000 steps, medium, 12 to 30 coins, not done") with the completion as a custom action; the collapsed Completed stack is one element ("Completed, 4 done, 160 coins", value "collapsed", hint "Shows every completed item") and its header is skipped, so nothing is read twice; expanded, the header is a heading with value "expanded" and the rows are the usual single elements; doodles are hidden from VoiceOver; the dot grid is hidden and the level card reads "Level 8, 312 coins to level 9". Colour is never the only signal: difficulty is also the pill's range, done is check + strikethrough + fill.

## Slices

Each slice is built by one owner, verified on the simulator (light, dark, largest accessibility text size; `verify` skill) and committed on its own. Core logic gets tests first; views only render.

### Done (branch `v0.1`)

| # | Slice | Commits |
|---|---|---|
| 1 | **Design system.** Core `Palette` (light/dark hex + contrast tests) and `DoodleKey`; app `DesignSystem/` (tokens, fonts, doodles, primitive components, gallery). | `2770976`, `9add522` |
| 2 | **Floating tab bar and Settings.** Four tabs (Today, Calendar, Rewards, Settings); Library, Debug, design gallery and export / restore live in Settings. | `e4212c8` |
| 3 | **Today reskin.** Core presentation values (`TodayPresentation`); level card, epic, routine rows, tinted quest tiles, `⋯` menus replacing swipe actions, one-VoiceOver-element cards. Level card about 120 pt so Routines and Today's quests start on the first screen; the epic was first a compact dark card and is now a routine-style card (this change). | `00e1713`, `9158b79` |
| 3b | **Completed stack on the real page.** The user compared a stacked-cards sample with a flat dimmed list in the gallery and chose the stack (2026-10-02). Done cards gather in the Completed section; open sections show only open items; `Settings → Design gallery → Completed stack` renders it collapsed, expanded, with one item and with only the epic. | uncommitted |

Built differently from the first draft of this document: the tab bar is an overlay on the `TabView` (a bottom safe-area inset did not reach scroll views inside navigation stacks), each scroll view reserves its own bottom margin through `reservingTabBarSpace()`, and the bar fades out while the keyboard is up.

### Gate: use it on the phone first

Slices 1 to 3 were only checked on the simulator. Haptics, how the animations feel, real text sizes and whether the doodles and colours are right can only be judged on a device. Live with it for a few days, then collect fixes (layout, colours, doodle character, anything that feels slow) before slice 4, because every later screen reuses these components.

### Next, in this order

| # | Slice | Scope |
|---|---|---|
| 4 | **Payout reveal and moments.** Seen after every completion, so highest value. | Restyle `PointsRollView` (the roll and the rating card); turn the level-up and streak-milestone alerts into cards with a sparkle; restyle the Levels sheet. Tabular digits and a `CADisplayLink` number roll; `CAEmitterLayer`-style sparkle particles from the sparkle doodle (off with Reduce Motion, keep the number change and the haptic). |
| 5 | **Add and Replace sheets.** | `AdHocView` (add, replace a slot, replace a routine) and the epic replace sheet, using the card and tile language and the doodle table. |
| 6 | **Calendar and day detail.** | Month grid with per-day completion in the dot style, day detail as cards, rating summary. |
| 7 | **Rewards.** | Reward cards with price, the savings-goal bar, blocked and negative-balance states in clay. |
| 8 | **Settings and Library.** | Restyle rows; Library rows with doodle and tint; surface the workout-calendar and keyword settings now buried in Debug as a real Settings section. |
| 9 | **Polish.** | Grow the keyword-to-doodle table so fewer quests fall back to the sparkle (and add more doodles if wanted); tune motion; VoiceOver, Reduce Motion and Bold Text passes on device; app icon and launch screen. |

Optional, only if wanted after use: a Hero-style page for the level track, perks, streak milestones and the savings goal. Today's level card already opens the Levels sheet.

### Known gaps carried forward

- Not verified so far: haptics, Reduce Motion, Bold Text, VoiceOver, the long-press context menu, the "+N" float and the dot stagger on a real level-up.
- The trivial-group tile (three micro-actions) only appears on low days, which the simulator cannot produce; it is checked in the gallery and unit tests only.
- Most quests currently show the generic sparkle doodle.
- The payout card, level-up alert, Levels sheet, Add / Replace sheets, Calendar, Rewards, Library and Debug still use the old plain look.
