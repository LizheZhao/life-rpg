# Life RPG — UI design

Refined from `LifeRPG UI 设计规范与 UIKit Implementation Plan.md` (the original exploration, UIKit-based). **What was kept:** the visual language. **What changed:** everything that assumed UIKit, Core Data, an XP engine or attributes. The decisions below were made with the user on 2026-10-02 after comparing three throwaway variants of the Today page; variant **A (soft pastel, hand-drawn)** won.

## Decisions

| Topic | Decision |
|---|---|
| Framework | SwiftUI over the existing SwiftData + `LifeRPGCore`. No UIKit rewrite, no Core Data, no Combine, no Coordinator, no `XPEngine`. |
| Concept mapping | Home = Today. Coins / level / streak / savings goal live in the level card. Weekly **epic** = a routine-style row with a flag in its disc (it has no phases: its segments are the 7 days of the week). No attributes (STR/INT…) and no XP: colour follows **difficulty**. |
| Epic weight | The epic is a **routine-style card**: same neutral surface, radius and layout as a routine row, never a dark or separate hero card. Its title shows in full and a tap on the card expands the detail. Routines and today's quests are the focus of the page. |
| Appearance | Follows the system (light / dark automatically). Every colour token has a light and a dark value. |
| Tabs | Floating tab bar, four tabs: **Today, Calendar, Rewards, Settings**. Debug becomes a section of Settings (simulator/dev tools); Library becomes a page inside Settings; the export / restore menu moves from Today's toolbar into Settings. |
| Completion | Completion is final (`PLAN.md` §3): no Undo, no reverse animation, no Undo toast. The existing confirm alert stays. |
| Doodles | Drawn in code as SwiftUI `Path`s in a 100×100 box (stroke 3.5, round caps and joins), so static icons and the draw-on animation (`trim`) share one mechanism. No PDF pipeline. |
| Per-quest icon | Core owns a keyword → `DoodleKey` table with a generic default (`DoodleKey.forText`). Only a custom ad-hoc routine stores a chosen doodle: `RoutineOccurrence.iconKey` (`SchemaV4`, optional). `DoodleKey.resolve(iconKey:text:)` is the one rule that reads it: a known key wins, an unknown or missing one falls back to the text. Library rows and quest templates have no key yet. |
| Fonts | Plus Jakarta Sans and Caveat (SIL OFL, in `LifeRPG/Fonts/`), registered at launch with `CTFontManagerRegisterFontsForURL` (no Info.plist or pbxproj edit). Both are variable fonts: weights are applied through the `wght` variation axis. All text scales with Dynamic Type. |
| Swipe actions | Reroll / replace / extend / cancel are swipe actions in a `List` today. Swipe is gone: each card has a trailing `⋯` `Menu` (and a context menu) carrying the same actions, greyed out under the same Core rules (`Purchase.blocked`). |

## Tokens

All colours are semantic names with a light and a dark value, defined once in Core (`Palette`, hex ints) and wrapped in SwiftUI `Color` by the app. Views never contain a hex literal. The values are the user's palette sheet (`diary_palette.xlsx`, chosen 2026-10-02 after comparing four candidates on the real pages); light uses the sheet's original hexes, dark its softened ones. The neutrals (`surface`, `hairline`, `divider`, `ink`, `iconNeutral`, `sectionTitle`, `tabPill`) were then set from `neutral_surface_fix.xlsx` (2026-10-02); `canvas` stays as above. Required contrast (WCAG 4.5:1 for text) is asserted in Core tests for every foreground/background pair, in both appearances, with one documented exception (below).

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | #FBFBF8 | #14141A | screen background (the sheet's page) |
| `surface` | #FFFFFF | #23222C | neutral cards, Settings rows, tab bar. One step off the page in both appearances (1.04:1 in light, 1.17:1 in dark) |
| `hairline` | #ECECE6 | #2F2E3A | 1 pt edge of a neutral card and of the tab bar |
| `divider` | #ECECE6 | #34323F | ruled lines: Settings row separators, the slabs behind a stack |
| `ink` | #25232F | #E8E6EE | primary text, doodles, the filled complete button (`fill`), the selected tab icon |
| `inkSecondary` | #6A6877 | #B1AFBD | secondary text on the canvas and surface: captions, footers, placeholders, Workout detection headers (derived) |
| `iconNeutral` | #6E6C7A | #8A8896 | chevrons and decorative icons, including the Settings section icons and the unselected tab icons. Non-text, held to 3:1: 5.14 / 4.52 on the surface, 4.20 / 3.29 on `tabPill` |
| `sectionTitle` | #7A7886 | #9C9AA8 | Settings section headers only (17 pt Bold, so large text, 3:1 bar). Dark is 5.69 on the surface and 6.64 on the page; light is 4.32 and 4.17, below 4.5, kept as the user's sheet has it |
| `tabPill` | #E9E7F2 | #3A3848 | the circle behind the selected tab icon |
| `accent` | #4682B4 | #8FB0CC | the Caveat hand labels and the ring of an open complete button on a neutral card (the sheet's "Dear diary" / checkbox accent). Large text: 3.96 on the light canvas, 8.08 on the dark one |
| `onFill` | #FFFFFF | #14141A | the check on a filled button |
| `dotEmpty` / `dotFill` | #DDDED9 / #9CAF88 | #34333F / #86987A | level dot grid, empty week segments (derived) |
| `tintTrivial` | #9CAF88 | #86987A | trivial rows (sage) |
| `tintEasy` | #4682B4 | #3F76A5 | easy rows (steel blue) |
| `tintMedium` | #FFBF00 | #D8A645 | medium rows (amber) |
| `tintHard` | #C8465A | #B84A60 | hard rows (crimson) |
| `tintHidden` | #8A7BB3 | #7A6CA8 | the hidden quest (dusk violet) |
| `onTintDark` | #25232F | #1B1A22 | title, caption, doodle, `⋯` and open ring on amber and sage |
| `onTintWhite` | #FFFFFF | #FFFFFF | the same on steel blue, crimson and violet (`Palette.ink(on:)` picks per tint) |
| `chip` | #FFFFFF | #14141A | a pill on a tinted row, solid (the sheet's weather chips); its text is `ink` |
| `pillFill` | #EEEFEA | #2E2D38 | a pill on a neutral card or the canvas (derived) |
| `clay` / `clayBg` | #9C472A / #F3DDD2 | #E8A183 / #4A2E22 | overdue and negative balance, never alarm red (derived) |
| `avatarPink` | #F7C6D4 | #6B3F4C | avatar disc |

Neutral cards sit one step off it in both modes and let text and the tinted rows carry the contrast, so there is one `ink`, `inkSecondary`, `accent`, `pillFill` and `divider` for the page and for every card on it; there are no card-side variants of those tokens.

Two groups of pairs sit under 4.5:1 on purpose, each named in `PaletteTests` with its measured ratio. First, two light pairs of the sheet fall under 4.5:1 for 15 pt text, and are kept as the user chose them: white on steel blue #4682B4 (4.11) and white on dusk violet #8A7BB3 (3.77). `PaletteTests.knownBelowAA` names exactly these and holds them to the 3:1 large-text floor; no other pair may slip. Optional one-line fixes, not applied: steel blue #4179A7 (white 4.6) and violet #9386B9 (dark ink 4.7). Second, the light `sectionTitle` (4.32 on a card, 4.17 on the page) is held to the 3:1 large-text floor because Settings headers are 17 pt Bold; the smallest nudge that would reach 4.5 on both grounds is #747281, not applied. Every other secondary text is `inkSecondary` at 4.5. Icons and chevrons (`iconNeutral`) are non-text and tested at 3:1 on the surface, on `tabPill` and on each section circle. Sheet roles with no view yet: the inner panels of the diary cards and their ruled lines.

**Section icon tints.** Each Settings section icon sits in a 32 pt circle filled with the section's tint at 18 % (`Palette.sectionCircleOpacity`); the glyph stays `iconNeutral`, so Settings gains colour without losing calm. Library is sage (`tintTrivial`), Auto-verify steel blue (`tintEasy`), Data dusk violet (`tintHidden`, the same circle on each of its three rows), Design amber (`tintMedium`), Developer crimson (`tintHard`). Rows are buttons with their own `iconNeutral` chevron, because the system disclosure indicator cannot be coloured.

**Tab bar.** A `surface` capsule with a 1 pt `hairline` and a soft black shadow (10 %, radius 15, y 10), so it still reads as a floating bar over a white card in light. The selected tab shows a `tabPill` circle (it slides with `matchedGeometryEffect`) and an `ink` icon; the others are `iconNeutral`.

**Shadows.** The shared card background (`Palette.shadow`) gives a neutral card a 1 pt `hairline` and, in light only, a soft black shadow (radius 12, y 4, 5.5 %); in dark the hairline alone is the edge. A tinted row has no hairline and a shadow of radius 16, y 6: its own colour at 22 % in light, plain black at 40 % in dark. The level card and the epic card are ordinary neutral cards.

Type styles (Jakarta unless noted; each wraps `UIFontMetrics`): `displayGreeting` 32 Light with an ExtraBold emphasis word, `displayLevel` 52 Light, `titleCard` 22 Bold, `heading` 17 Bold, `bodyStrong` 15 SemiBold, `caption` 13 Regular, `pill` 12 SemiBold, `hand` Caveat 22 Medium. Radii: card 28, tile 26, row 24, pill 12, tab bar 34; all `.continuous`. Insets 22, section gap 14, grid gap 10. Shadows: see above.

## Today page

Order: header (avatar, add, no export menu) → greeting (Caveat "day N · M day streak", Jakarta line with squiggle under the emphasis word) → level card → **epic** → Routines → Today's quests (and Hidden) → **Completed** → **Ahead this week** → Backlog. Completed and Ahead are the same `StackedCards` component, headed like every other section.

- **Level card.** Level number, coins, "N to Lv X", 20-dot grid = progress to the next level (each dot 5 %), tier / slot pills, savings-goal bar. The fraction is a Core function, not computed in the view.
- **Epic.** Under its own section header (`Epic`, hand label `this week`), a routine-style row on the surface card: flag doodle in the disc, the title in full (it wraps like a routine title), pills for the reward range, `N days left` (`last day` on the final day, counted by `DayKey` from `Epic.lastDayKey`) and `extended 1/2`, a `⋯` menu (reroll / extend / replace / open link) and the 44 pt complete button. The 7 thin segments (days of the week elapsed, `dotEmpty` empty, `fill` filled) run along the bottom of the card. A tap on the card body expands the detail (`Day 5 of 7 · due Sun Oct 4`, extensions used of the maximum, the drawn value, the link) with a chevron that rotates; nothing is persisted and the body tap never completes.
- **Routines.** Full-width rows: doodle disc, title, pills (`+points`, `N strikes this week` from `Schedule.doneThisWeek`, overdue, lighter version), `⋯` menu, complete button. Auto-verified routines say so only to VoiceOver. Overdue shows a clay pill ("overdue · day 2", the halved payout). Done rows get strikethrough and the filled check.
- **Today's quests.** Full-width tinted rows with the routine row's structure: doodle disc, title, the drawn value as a caption, the range pill (`5–15`, the range only, never the word), a `⋯` menu (reroll / cancel / replace with Core prices, and `Open link` while the quest has one and is open) and the 44 pt complete button. Tint = difficulty; the disc is the pill veil over the tint. The same `QuestRowView` renders an open and a done quest, so a quest in the Completed stack looks like it did in its section. The hidden quest (its gate or the revealed row) sits under its own `Hidden` section header in lavender, and the micro-action group stays a wide mint card with its three ticks. The old two-column grid and its accessibility-size one-column branch are gone.
- **Open sections show only open items.** A card that is done leaves its section. When every item of a section is done the header stays with the hand label `cleared` and no cards (no empty card), so progress is still visible: `Epic · cleared`, `Routines · cleared`, `Hidden · cleared`. A section with something still open keeps `1 / 3 done`, counted over all its items (skipped rows count in the total, never as done). Core: `SectionProgress.handLabel`, `EpicCardState.sectionLabel`.
- **Completed (stacked cards).** One section after Today's quests / Hidden and before Ahead this week, hidden entirely when nothing is done. Header `Completed`, hand label `4 done · +160` (the sum of the points each row was paid, never recomputed). Collapsed: the most recent card with up to two slabs peeking behind it and `+N more`. A tap on the stack or the header fans it out (0.3 s spring; Reduce Motion: 0.2 s fade) into the normal done rows plus a `Collapse` button. Collapsed is the default and the state after a relaunch (`@State` in `TodayView`, not stored). Who is in it: today's completed random quests (they keep their tint), the hidden quest and a finished micro-action group, completed routines (due today, or finished late today), and the week's epic once done. Not in it: skipped, replaced and cancelled rows, routines done ahead (they stay under Ahead this week) and the backlog. Order: most recently completed first, by `completedAt` (every quest and routine occurrence carries one), ties by title. Core: `CompletedStackState`. Done rows have no menu and complete nothing; a tap does nothing except on the epic, which still expands. The stacking itself is `StackedCards`, generic over the rows and their slab colour, shared with Ahead this week.
- **Moving into the stack.** A card that has just been completed stays in its section for 0.9 s (`TodayView.settling`) so the check, the strikethrough and the floating `+N` finish where the tap was, then leaves its section (fade and slight shrink) while the stack grows (0.3 s; Reduce Motion: 0.2 s fade only). The confirm alert, the payout reveal and the haptic are untouched.
- **Ahead this week (stacked cards).** Under a section header like `Routines`, with the hand label `5 open` and, when Sunday's flexible settlement would charge something, a clay `−13 Sun night` beside it (`Overdue.weekly`, unchanged). The rows go through the same `StackedCards` as Completed: the first card on top, one or two peeking, `+N more`; a tap on the stack or the header fans it out into the list plus `Collapse`. The expand rules are unchanged (`aheadExpanded` / `aheadToggledOn`, open by default on Saturday and Sunday, a hand toggle wins for the day) and drive the stack through a binding. Rows: this week's open flexible routines and routines done ahead are ordinary routine rows (`Not done · due Wed Sep 30`, `Done ahead · counts for Sat Oct 3`), and each "Do now" candidate is a routine-style row with its payout range, `N strikes this week` (the routine pill's fact), `due today` / `due tomorrow` / `due in N days` (`PresentationText.dueIn`) and a light pill-shaped `Do now` button (44 pt target) that raises the usual confirm alert. Core: `AheadState`, `AheadCandidateState`. Which routines are ahead is still `Schedule`'s rule, and a routine done ahead stays here, not in Completed.
- Backlog keeps its plain record rows.

## Add and Replace sheets (slice 5)

`AdHocView` (add, replace a slot, replace a routine) and `EpicReplaceView` are canvas pages, not grouped lists. Cards, pills and doodle discs are the Today row language; nothing here is a rule, `AdHoc` and `Epic` still decide what qualifies and what a custom task pays.

- **Frame.** Inline title (`Add for today` / `Replace` / `Replace the epic`), `Cancel` in the toolbar, a scroll of cards, and one full-width `fill` capsule (`ConfirmBar`) pinned above the keyboard. It is dimmed until something is picked; the existing confirm alert still follows it.
- **Replaces card.** What is being swapped: its doodle disc, `Replaces`, the title struck through in `inkSecondary`, a pill (`medium`, `micro-actions`, `worth 15`, `epic`) and the rule text as a caption inside the card.
- **Source control.** `From library` / `Custom` is `PillSegmentedControl`, the capsule the ratings window uses (moved to `Components.swift` and shared).
- **Library rows.** Selectable cards: the routine's own doodle in a `pillFill` disc (`DoodleKey.resolve(iconKey: nil, text:)`), the title, a `+N` pill (what it pays today, `Scoring.routinePoints`) and a `low day` pill on a low tier. Selected = a 2 pt `ink` ring round the card and a filled check in place of the open ring, so colour is never the only signal. Routines already on the page sit under their own header with where they are and, when adding, a `Done · N` button.
- **Custom tab.** The text field lives in a card beside the doodle it will wear; difficulty is three pill choices tinted by tier (`Easy`, `Medium`, `Hard`, selected = tint plus an ink ring); `Pays N, the middle of the easy range.` underneath. The doodle picker is a card holding every `DoodleKey` as its drawing in a disc, the chosen one ringed; each button speaks `DoodleKey.title`. It follows `DoodleKey.forText(text)` while typing (hand label `suggested`) until one is tapped (`picked`). The key is passed as `AdHoc.Source.custom(text:difficulty:iconKey:)` and stored on the occurrence. `Similar in your library` stays a card with `Use this` / `Done · N` / `worth N` rows.
- **Where the doodle shows.** `RoutineOccurrence.doodle` feeds `RoutineRowState` (Routines, Ahead, Completed) and the day detail rows, so a chosen doodle appears everywhere the routine does. `AheadCandidateState` is a library routine, not an occurrence, so it keeps the keyword doodle.
- **Epic replace.** Same frame; library epics show their keyword doodle, a custom epic keeps the flag and has no picker.

## Calendar, day detail and ratings (slice 6)

- **Month grid.** One `lrCard`; weekday names in `sectionTitle`; Caveat month title (`handTitle`, 34 pt) between two 44 pt round chevrons on `tabPill`; a `This month` pill under the title while another month is shown. A month change fades the grid (the new month also slides 18 pt from its side; Reduce Motion: fade only, 0.2 s) and fires `Haptics.selection()`. The future month is unreachable (right chevron dimmed and disabled).
- **A day cell.** The number (today: a 2 pt `accent` ring), then up to three 6 pt dots, one per completed random quest, coloured by tier (`QuestTint`, easiest first, `DayMarks.randomTiers`; the cap keeps the three easiest), then a row with a small `ink` tick for "every routine done on time" (a tick, not a tier colour, so it never reads as a fourth difficulty) and a `tintHidden` star for the hidden quest. Future days are 35 % opacity and disabled, padding days 40 %. One VoiceOver element per cell (`Fri Oct 2, today`, value `2 quests done: easy, hard, routines cleared, epic week`).
- **Epic week.** A rounded band behind the row's seven cells in `QuestTint(.epic)` (the hardest tint, as everywhere) at 14 %; the legend chip shows it at 28 % so it stays visible on a small swatch. Which week is still `CalendarMarks.epicWeeks`.
- **Legend** is chips on `pillFill`: four tiers, Routines, Hidden, Epic week. **Ratings** is a surface row under it (tinted violet icon circle, chevron), not a toolbar item.
- **Accessibility size.** The grid card stops growing at `xxxLarge` (seven columns cannot hold larger numbers: weekday names wrapped letter by letter at AX3); everything else on the page scales fully.
- **Day detail.** Sheet on the canvas, inline title `Friday, October 2`; the `dayKey` is on the net-points card (`handDisplay` 52 pt Caveat, `ink` for a gain, `clay` for a loss, never sage on white, which fails contrast as text). Body is a card (tier and cycle as pills, a two-column adaptive grid of the readings). Routines and quests use `HistoryRowView`, the Today row frame without controls: the trailing 44 pt `HistoryMark` is a filled check (done, including late and ahead), an open ring (not done) or a ring with a dash (skipped, replaced, cancelled). Quests keep their tier tint and the doodle; the epic is a neutral routine-style card with the flag; a replaced quest is a neutral struck-through card; the micro-action group lists its three ticks. Pills carry the tier name (this replaces the old `E / M / H / T / ★` code), what it paid, a clay `-N` penalty and `Rated +N`. Ledger rows and other ratings are plain cards with dividers. Done rows are not struck through here (Today's meaning of strikethrough is "completed"; on a history page only replaced rows are).
- **Ratings.** Pill-capsule window picker (`pillFill` track, `fill` slider, 7 / 30 / 90 / All; two rows at accessibility sizes), rows as surface cards, the average as a pill: `tintTrivial` fill for positive, `clay` for negative, plain for zero (`PillLabel.Style.tint`).
- New type styles: `handTitle` (Caveat 600, 34, max 52) and `handDisplay` (Caveat 600, 52, max 72).

## Motion and haptics

Complete: button fills, check draws on (0.25 s ease-out), "+N" floats up, new level-dots fill in sequence, medium impact haptic. Press: scale 0.97 spring. Level up: success notification haptic; the existing level card moment stays. Squiggle draws on once at first appearance. With Reduce Motion on, every animation becomes a 0.2 s cross-fade. Bold Text raises each style one weight step.

## Accessibility

Contrast ≥ 4.5:1 for text (tested in Core), hit targets ≥ 44 pt, Dynamic Type through the largest accessibility size without truncating the title or points. Each row is one VoiceOver element ("Walk 8,000 steps, medium, 12 to 30 coins, not done") with the completion as a custom action; the collapsed Completed stack is one element ("Completed, 4 done, 160 coins", value "collapsed", hint "Shows every card") and its header is skipped, so nothing is read twice; expanded, the header is a heading with value "expanded" and the rows are the usual single elements; doodles are hidden from VoiceOver; the dot grid is hidden and the level card reads "Level 8, 312 coins to level 9". Colour is never the only signal: difficulty is also the pill's range, done is check + strikethrough + fill.

## Slices

Each slice is built by one owner, verified on the simulator (light, dark, largest accessibility text size; `verify` skill) and committed on its own. Core logic gets tests first; views only render.

### Done (branch `v0.1`)

| # | Slice | Commits |
|---|---|---|
| 1 | **Design system.** Core `Palette` (light/dark hex + contrast tests) and `DoodleKey`; app `DesignSystem/` (tokens, fonts, doodles, primitive components, gallery). | `2770976`, `9add522` |
| 2 | **Floating tab bar and Settings.** Four tabs (Today, Calendar, Rewards, Settings); Library, Debug, design gallery and export / restore live in Settings. | `e4212c8` |
| 3 | **Today reskin.** Core presentation values (`TodayPresentation`); level card, epic, routine rows, tinted quest tiles, `⋯` menus replacing swipe actions, one-VoiceOver-element cards. Level card about 120 pt so Routines and Today's quests start on the first screen; the epic was first a compact dark card and is now a routine-style card (this change). | `00e1713`, `9158b79` |
| 3c | **Today round 2.** Ahead this week as a section header over the shared `StackedCards`; quests as full-width tinted rows (one row implementation for open and done); the palette sheet (`diary_palette.xlsx`) as the one palette, with per-tint text colours, an accent, solid chips, dividers and card shadows. | uncommitted |
| 3b | **Completed stack on the real page.** The user compared a stacked-cards sample with a flat dimmed list in the gallery and chose the stack (2026-10-02). Done cards gather in the Completed section; open sections show only open items; `Settings → Design gallery → Completed stack` renders it collapsed, expanded, with one item and with only the epic. | uncommitted |
| 5 | **Add and Replace sheets.** Canvas pages in the card language with doodle discs, shared `PillSegmentedControl`, a doodle picker for custom tasks (`RoutineOccurrence.iconKey`, `SchemaV4`, export `schemaVersion` 4; v3 files still import) and `DoodleKey.resolve`. | uncommitted |
| 6 | **Calendar, day detail, ratings.** Core `DayMarks.randomTiers` (dots by tier); month grid in one card with an epic-week band, legend chips and a Ratings row; day detail as cards with Today's row frame (`HistoryRowView`); ratings with a pill window picker. | uncommitted |

Built differently from the first draft of this document: the tab bar is an overlay on the `TabView` (a bottom safe-area inset did not reach scroll views inside navigation stacks), each scroll view reserves its own bottom margin through `reservingTabBarSpace()`, and the bar fades out while the keyboard is up.

### Gate: use it on the phone first

Slices 1 to 3 were only checked on the simulator. Haptics, how the animations feel, real text sizes and whether the doodles and colours are right can only be judged on a device. Live with it for a few days, then collect fixes (layout, colours, doodle character, anything that feels slow) before slice 4, because every later screen reuses these components.

### Next, in this order

| # | Slice | Scope |
|---|---|---|
| 4 | **Payout reveal and moments.** Seen after every completion, so highest value. | Restyle `PointsRollView` (the roll and the rating card); turn the level-up and streak-milestone alerts into cards with a sparkle; restyle the Levels sheet. Tabular digits and a `CADisplayLink` number roll; `CAEmitterLayer`-style sparkle particles from the sparkle doodle (off with Reduce Motion, keep the number change and the haptic). |
| 7 | **Rewards.** | Reward cards with price, the savings-goal bar, blocked and negative-balance states in clay. |
| 8 | **Settings and Library.** | Restyle rows; Library rows with doodle and tint; surface the workout-calendar and keyword settings now buried in Debug as a real Settings section. |
| 9 | **Polish.** | Grow the keyword-to-doodle table so fewer quests fall back to the sparkle (and add more doodles if wanted); tune motion; VoiceOver, Reduce Motion and Bold Text passes on device; app icon and launch screen. |

Later, not scheduled:

- **Per-task doodle editing for the library.** `SchemaV4` only added `iconKey` to `RoutineOccurrence` (custom ad-hoc routines). Optional `iconKey` on `QuestTemplate` and `RoutineTask` (a further lightweight migration, carried by the export), a doodle picker in the Library detail, cards looking the icon up by `templateID` / `routineID` and falling back through `DoodleKey.resolve`; grow the keyword table.
- **Workout detection settings:** done (multi-select calendars).

Optional, only if wanted after use: a Hero-style page for the level track, perks, streak milestones and the savings goal. Today's level card already opens the Levels sheet.

### Known gaps carried forward

- Not verified so far: haptics, Reduce Motion, Bold Text, VoiceOver, the long-press context menu, the "+N" float and the dot stagger on a real level-up.
- The trivial-group tile (three micro-actions) only appears on low days, which the simulator cannot produce; it is checked in the gallery and unit tests only.
- Most quests currently show the generic sparkle doodle.
- The payout card, level-up alert, Levels sheet, Rewards, Library and Debug still use the old plain look.
