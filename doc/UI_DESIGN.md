# Life RPG — UI design

Refined from `LifeRPG UI 设计规范与 UIKit Implementation Plan.md` (the original exploration, UIKit-based). **What was kept:** the visual language. **What changed:** everything that assumed UIKit, Core Data, an XP engine or attributes. The decisions below were made with the user on 2026-10-02 after comparing three throwaway variants of the Today page; variant **A (soft pastel, hand-drawn)** won.

## Decisions

| Topic | Decision |
|---|---|
| Framework | SwiftUI over the existing SwiftData + `LifeRPGCore`. No UIKit rewrite, no Core Data, no Combine, no Coordinator, no `XPEngine`. |
| Concept mapping | Home = Today. Coins / level / streak / savings goal live in the level card. Weekly **epic** = the dark card (it has no phases: its segments are the 7 days of the week). No attributes (STR/INT…) and no XP: colour follows **difficulty**. |
| Epic weight | The epic card is **compact** — one short card, not a hero. Routines and today's quests are the focus of the page. |
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
| `fill` / `onFill` | #18181B / #FFFFFF | #F4F1EE / #151517 | selected state, done complete-button, epic card |
| `dotEmpty` / `dotFill` | #DAD5D0 / #8ED1B4 | #3A3A40 / #7CC4A6 | level dot grid |
| `tintTrivial` | #BFE8D6 | #2F4A3F | trivial tile (mint) |
| `tintEasy` | #B9E3F4 | #2C4655 | easy tile (sky) |
| `tintMedium` | #F4E29A | #55482A | medium tile (butter) |
| `tintHard` | #F7D9DE | #573640 | hard tile (blush) |
| `tintHidden` | #D4D6FF | #3A3C5E | hidden quest (lavender) |
| `clay` / `clayBg` | #A8502F / #F3DDD2 | #E8A183 / #4A2E22 | overdue and negative balance — never alarm red |
| `avatarPink` | #F7C6D4 | #6B3F4C | avatar disc |

Type styles (Jakarta unless noted; each wraps `UIFontMetrics`): `displayGreeting` 32 Light with an ExtraBold emphasis word, `displayLevel` 52 Light, `titleCard` 22 Bold, `heading` 17 Bold, `bodyStrong` 15 SemiBold, `caption` 13 Regular, `pill` 12 SemiBold, `hand` Caveat 22 Medium. Radii: card 28, tile 26, row 24, pill 12, tab bar 34; all `.continuous`. Insets 22, section gap 14, grid gap 10. Only the floating tab bar has a shadow.

## Today page

Order: header (avatar, add, no export menu) → greeting (Caveat "day N · M day streak", Jakarta line with squiggle under the emphasis word) → level card → **compact epic** → Routines → Today's quests.

- **Level card.** Level number, coins, "N to Lv X", 20-dot grid = progress to the next level (each dot 5 %), tier / slot pills, savings-goal bar. The fraction is a Core function, not computed in the view.
- **Compact epic.** One card of about 88 pt: small flag doodle, one-line title, 7 thin segments (days of the week elapsed), reward range, a `⋯` menu (reroll / extend / replace). Dark-filled card in both appearances.
- **Routines.** Full-width rows: doodle disc, title, pills (`+points`, frequency, auto-verified, lighter version), complete button. Overdue shows a clay pill ("overdue · day 2", the halved payout). Done rows get strikethrough and the filled check.
- **Today's quests.** Two-column grid of tinted tiles, tint = difficulty. The pill shows the **range only** (`5–15`), not the word. Hidden quest and the trivial group are full-width tiles. At accessibility text sizes the grid becomes one column.
- Backlog, "do ahead" and the Sunday bill keep their current content, restyled as rows.

## Motion and haptics

Complete: button fills, check draws on (0.25 s ease-out), "+N" floats up, new level-dots fill in sequence, medium impact haptic. Press: scale 0.97 spring. Level up: success notification haptic; the existing level card moment stays. Squiggle draws on once at first appearance. With Reduce Motion on, every animation becomes a 0.2 s cross-fade. Bold Text raises each style one weight step.

## Accessibility

Contrast ≥ 4.5:1 for text (tested in Core), hit targets ≥ 44 pt, Dynamic Type through the largest accessibility size without truncating the title or points. Each tile and row is one VoiceOver element ("Walk 8,000 steps, medium, 12 to 30 coins, not done") with the completion as a custom action; doodles are hidden from VoiceOver; the dot grid is hidden and the level card reads "Level 8, 312 coins to level 9". Colour is never the only signal: difficulty is also the pill's range, done is check + strikethrough + fill.

## Slices

1. **Design system** — Core `Palette` + `DoodleKey` with tests; app `DesignSystem/` (tokens, fonts, typography, doodles, primitive components, gallery preview).
2. **Settings and the tab bar** — floating tab bar, Settings (Debug, Library, export / restore).
3. **Today reskin** — level card, compact epic, routine rows, quest tiles, menus replacing swipe actions, motion.
4. Later: Calendar, Rewards, Settings polish, the Library page, a Hero-style page for the level track if wanted.

Verify each slice on the simulator in light, dark and the largest accessibility text size (`verify` skill).
