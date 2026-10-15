# UX/UI review — 2026-10-15

This review covers `LifeRPG/` on `v0.1`. It ran as two independent passes: a design review of the source, and an evidence pass of grep scans plus 18 Simulator screenshots on iPhone 17 Pro Max in light mode, dark mode and Accessibility XL text. The Impeccable detector can't read Swift, so nothing here was checked by a tool.

**Score: 22/40 (Acceptable).** Nothing below is fixed yet; each item is a task for later, with the suggested `/impeccable` command in brackets.

## Heuristic scores

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | System status | 3 | Tapping an empty past calendar day does nothing (`CalendarView.swift:190`) |
| 2 | Match real world | 2 | Internal values leak to screen (see P1-a) |
| 3 | User control | 2 | The rating card closes itself after 8 s, and tapping the dim counts as "Not yet" |
| 4 | Consistency | 2 | Two page-title systems, the + sits in different places, and AdHoc and Replan use a system alert instead of ConfirmBar |
| 5 | Error prevention | 3 | Every spend asks for confirmation, and prices stay visible |
| 6 | Recognition | 2 | The tab bar is icons only, and prices and actions hide behind ⋯ |
| 7 | Flexibility | 2 | A daily-use app with no widget or Shortcut entry |
| 8 | Minimalist | 3 | Today stacks 10 regions |
| 9 | Error recovery | 1 | About 30 banners show the raw `"\(error)"` |
| 10 | Help | 2 | Onboarding never explains penalties, overdue routines, streaks or levels |

## Worth keeping

- **One overlay at a time.** `TodayView.Overlay` makes sure a confirmation can never stack on top of another card, and the confirmation turns into the payout in place.
- **Accessibility.**
  - Each card is one VoiceOver element with its actions attached (`CardActions.swift:125-143`).
  - Reduce Motion is handled for the reel and the tab indicator.
  - State is never shown by colour alone.
  - All type is scaled with `UIFontMetrics`.
- **Honest costs.** Blocked menu rows still show their price. The Sunday charge is previewed on the row it belongs to. Penalties use clay, never alarm red.

## Priority issues

### P1-a — Internal data and raw errors on screen [clarify]
**Where:**
- Raw dayKeys: `RewardsView.swift:131,265,289` ("Missed 2026-10-12"), `AdHocView.swift:254-255,452`.
- "a different E": `TodayView.swift:980`.
- "veryLow" and Energy shown to 3 decimals: `DayDetailView.swift:235,244`.
- "3 random slots": `TodayPresentation.swift:388`.
- "−13 Sun night".
- About 30 banners show `"\(error)"`, e.g. `TodayView.swift:536,802,916,930,1010`, `RewardsView.swift:315-338`, `LibraryForms.swift:242`.

**Fix:**
- Format dates with `PresentationText.shortDate` and tiers with `Tier.dayText`.
- Show difficulty as a title.
- Map each error to one plain sentence plus a "Copy details" button.

**Done (2026-10-15), code only.** The device check is still open. One correction to the review: the ~30 `"\(error)"` banners were mostly not raw. Core's `Failure` types already had readable descriptions. The real problems were lower-case fragments, dayKeys inside them, "T group" and "E, M or H", and the raw text of any non-Core error (for example a SwiftData save).

What changed:
- **Errors.** Core's `ErrorText.message(_:otherwise:)` (`Design/ErrorText.swift`) makes a `UserFacingError` reason into a sentence, and gives one plain line for anything else. Every app banner uses it except Debug and the startup screens. DataTransfer and day generation pass their own `otherwise`. No "Copy details" button was added.
- **Dates.** Error descriptions, Rewards (freeze, ledger), AdHoc, FeedbackPanel and the "Added …" note go through `PresentationText.shortDate`. It has no year, which can be ambiguous in a ledger that spans years.
- **Tier.** `Tier.dayText` is now "Running low", "Low energy", "Normal energy" or "High energy". The new wording is used everywhere the old "very low day / normal day" was: the level card, the day sheet, and the journal chips.
- **Today labels.**
  - The slots pill reads "N quests today".
  - The bill pill reads "−N if not done by Sunday", on the row and on the Ahead stack.
  - The reroll prompt reads "a different easy quest", using `Difficulty.word`.
- **Body card** in Day detail:
  - It shows a tier-word pill and Energy to 2 decimals.
  - "Routines · quests" replaces "Routine load · random slots".

### P1-b — Onboarding sells only the gains [onboard]
**What's wrong:**
- `OnboardingPages.swift:131-143` promises "Every clear pays coins".
- Overdue charges, the Sunday settlement, the streak freeze and debt are never mentioned, so the first clay pill comes as a surprise.
- "Skip intro" jumps to page 5 of 6.

**Fix:** add one line about costs to the loot page, and show a one-time explainer the first time a clay pill appears.

**Done (2026-10-15), code only.**
- The loot page now also says "Routines left undone cost coins, and Sunday night settles the week."
- "Skip intro" is now "Skip to setup". It still goes to page 5 on purpose, because the reminders and Health/Calendar pages must be seen.
- Page changes respect Reduce Motion.
- Not done: the one-time explainer the first time a clay pill appears.

### P2-a — The payout peak is diluted, level-up has no ceremony, and the rating timeout fails VoiceOver users [delight]
**What's wrong:**
- The rating card closes itself after 8 s (`PointsRollView.swift:613,764-770`), which fails WCAG 2.2.1.
- Five thumbs appear right after the reel.
- A level-up is only "Reached level N." with a "Nice" button (`TodayView.swift:744-757`).
- A streak milestone is a single line of text.

**Fix:**
- Remove the timeout, or at least turn it off when VoiceOver is running.
- Make the rating a quiet optional row.
- Give level-up a real ceremony.

**Done (2026-10-15), code only, direction A.**
- The rating card no longer closes itself. A quiet "Skip" row sits under the thumbs, and a pick still closes the card after 0.5 s.
- Level-up and streak milestones now show a `MomentStamp` (`PointsRollView.swift`). The hand label ("level up" / "streak") sits above a big Caveat mark ("7 → 8" / "14 days") that lands like a rubber stamp: oversized and tilted, then pressed flat.
  - Unlocked perks and streak bonuses are listed under the mark with checkmarks.
  - The haptic is heavy for a level-up and rigid for a streak.
  - With Reduce Motion on, the mark fades in instead.
- It is still the shared centered card, not a separate full screen.

### P2-b — Page chrome is inconsistent (seen in the screenshots) [layout]
**What's wrong:**
- Today has no backdrop behind the status bar. When scrolled, the clock sits over the epic card, and at XL text it sits over "Today's quests".
- Rewards and Settings use the system `.navigationTitle` in SF (`RewardsView.swift:78`, `SettingsView.swift:188`).
- Calendar, Trends and Journal use the Jakarta `pageTitle` (`CalendarView.swift:90`, `TrendsView.swift:68`, `JournalEntriesView.swift:36`), and the title sits at a different height.
- The + on Rewards sits on its own row above the title. The + on Today is a 44pt circle (`TodayView.swift:350`).
- Content insets are 22 in some places and 16 in others (`RewardsView.swift:72`).

**Fix:**
- Build one `PageHeader` shared by all five tabs.
- Put a material or fade behind the top safe area.
- Pick one content inset.

**Done (2026-10-15), code only.**
- `PageHeader`, `HeaderIconButton` and `statusBarFade()` are new in `DesignSystem/Components.swift`.
- Calendar, Trends, Rewards and Settings all use `PageHeader`.
  - Rewards and Settings dropped the system `navigationTitle`.
  - Rewards' + is the same 44 pt circle as Today's.
  - Trends' period picker now sits under the title.
- Every tab fades content under the status bar.
- Page insets use `LR.Spacing.inset` (22, as this doc's design says) instead of hard-coded 16.

### P2-c — IA, touch targets and contrast [audit]
**IA:**
- The journal, used every night, has no tab. Before 20:00 it is only a book icon in the top bar (`TodayView.swift:349`).
- Trends takes a whole tab yet stays locked for a new user's first 7 days (`TrendsView.swift:59-74`).
- The Library is buried in Settings (`SettingsView.swift:100`).
- Debug and the Design gallery ship to the device (`SettingsView.swift:155-171`).
- **Fix:**
  - Turn the Trends tab into a Journal tab that holds the entries and Trends.
  - Wrap Debug and the Design gallery in `#if DEBUG`.

**Touch targets under 44pt:**
- Trends stepper at 36 (`TrendsView.swift:120,128`) and period picker at 36 (`:524`).
- `PillSegmentedControl` at 36 (`Components.swift:443`).
- The remove-question ✕ at 32×24 and 70% opacity (`JournalEditorView.swift:135-139`).
- The prompt-bar pills at 38 (`JournalPromptBar.swift:58`, `JournalAskPill.swift:33`).
- **Fix:** give each a 44pt minimum hit area with `contentShape` and a frame.

**Contrast below 4.5:1 (already known in `PaletteTests`):**
- White on tintHidden: 3.77.
- White on tintEasy: 4.11.
- Accent hand labels on the page: 3.96.
- sectionTitle: 4.17–4.32.
- Today's date in the calendar: light blue on a gray brush.

**Partly done (2026-10-15), code only.**
- **IA:** kept as it is, by decision.
- **Debug and Design gallery:** folded into one collapsed Developer section. `#if DEBUG` would not hide them, because the app is installed as a Debug build.
- **Touch targets:** every hit area listed above is now 44 pt, with the visual size unchanged.
- **Contrast: correction.** These pairs are documented in `UI_DESIGN.md` as deliberate choices. `sectionTitle` and the accent hand labels are large text, so 3:1 is their bar, and they pass. Only white on tintEasy (4.11) and white on tintHidden (3.77), behind 15 pt titles, really miss 4.5. The fix `UI_DESIGN.md` named is now applied: tintEasy #4179A7 (white 4.65), tintHidden #9386B9 with dark ink in light (4.67) and white in dark (4.63, a new `onTintHidden` token). `knownBelowAA` is empty.

## Persona red flags

**First-timer:**
- "normal day · 3 random slots" and "−13 Sun night" mean nothing to them.
- The tab bar has no labels.
- Trends is locked.
- The Hidden lock is never explained.
- The + reads "Add for today" but logs extra work (`AdHocView.swift:134`).

**VoiceOver / Dynamic Type:**
- The 8 s rating timeout.
- Tab icons are a fixed 22pt with no Large Content Viewer (`FloatingTabBar.swift:102`).
- The calendar grid is capped at xxxLarge (`CalendarView.swift:185`), and the legend's dot and swatch symbols don't scale.
- At XL text, "All journal entries" sits under the tab bar.
- The ±1 and ±2 thumbs differ only by fill (`PointsRollView.swift:8-12`).
- 44 `.font(.system(size:))` icons don't scale.

**One-handed use:** the + and Levels on Today, the + on Rewards, and the journal's Done all sit at the top of the screen.

## Minor

- `UI_DESIGN.md:13` says four tabs, but the code has five. The calendar doc describes dots, but the code draws rings.
- Choosing a ⋯ action waits a fixed 350 ms (`CardActions.swift:53`).
- The Erase dialog's cancel button reads "Not yet". Erase never suggests exporting first.
- The Redeem confirmation shows the price but not the balance after (`RewardsView.swift:286-288`).
- The empty journal editor has no placeholder.
- The day-detail sheet has no visible close button.
- These animations don't check Reduce Motion:
  - Onboarding page changes (`OnboardingView.swift:33,52,65,87`)
  - `AdHocView.swift:765`
  - `JournalEditorView.swift:62`
  - `SaveToLibraryCard.swift:37`
- These use `lineLimit(1)` with no text shrink, so they risk truncation at large text sizes: `SettingsView.swift:60`, `LibraryView.swift:840`, `CalendarView.swift:214`, `JournalPromptBar.swift:20,51`.
- The epic card expands through `.onTapGesture` rather than a Button (`TodayCards.swift:337`).

**Done (2026-10-15):**
- The Redeem confirmation says what is left.
- The empty journal editor shows "What happened today?".
- Erase suggests exporting first, and its cancel reads "Keep my records".
- Onboarding page changes respect Reduce Motion.

## Open questions

1. With 5–10 completions confirmed a day, would a 5 s undo be kinder than "Mark as done?"?
2. A 5-coin quest gets a slot machine, while a level-up gets "Nice". Which moment should be the peak?
3. ~~RPG tone~~ — decided, see below.

## Decision: RPG tone (2026-10-15)

**Direction A: keep the journal look, and add ceremony only at a few moments.** The pastel journal world stays as it is: paper, pastels, Caveat hand labels and the doodles. We considered two other directions and rejected both:
- **B**, a solo-leveling system window: dark blue, square frames, all-caps system voice.
- **C**, a hybrid that uses dark system panels for level, perks and balance.

The RPG feel comes from a few marked moments, not from a second visual layer:
- **Level-up** becomes a full-page "stamp" moment: an old → new level change, the perk it unlocks, and a stronger haptic. It replaces the current "Reached level N." notice with a "Nice" button (`TodayView.swift:744-757`).
- **Streak milestones** get a smaller version of the same ceremony, instead of a single line of text.
- **Everything else stays quiet.** In particular, the quest payout reel should not compete with level-up. That is why P2-a also moves the rating card to a quiet optional row.

These moments are built in the journal look's own vocabulary: ink, paper and Caveat. Do not add glow, neon or system-panel styling. Every motion needs a Reduce Motion fallback.

## Suggested order

1. `/impeccable clarify` — P1-a
2. `/impeccable onboard` — P1-b
3. `/impeccable delight` — P2-a, using direction A (level-up and milestone ceremony)
4. `/impeccable layout` — P2-b
5. `/impeccable audit` — P2-c
6. `/impeccable polish`
