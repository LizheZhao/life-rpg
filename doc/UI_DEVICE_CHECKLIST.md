# UI revamp — checks to do on the phone

Everything here was built and looked at on the simulator only. These are the things a simulator cannot show or that were never tried. Tick them off with the phone in your hand; write what looks wrong next to the item and send me the list.

Order: setup → first look → the daily flows → haptics → accessibility → things the simulator could not produce → judgement calls.

## 0. Before installing (5 min)

- [ ] **Back up first.** Settings → Data → *Output records to JSON*, save the file somewhere off the app (Files / AirDrop). This build moves the store to `SchemaV4` (one new optional column, tested on a copy of old data, but this is your real history).
- [ ] In Xcode, set the two things I can't set for you (`project.pbxproj`):
  - Target → General → App Icons → **App Icon = AppIcon**
  - A `UILaunchScreen` dictionary with `UIColorName = LaunchBackground` and `UIImageName = LaunchLogo` (Info tab, or point the target's `INFOPLIST_FILE` at `doc/launch-screen.plist`).
- [ ] Build to the phone. If it fails with *cannot find 'X' in scope*, the file isn't in the target: check `WorkoutDetectionView.swift`, `StackedCards.swift`, `PointsRollView.swift` are listed in the project navigator.
- [ ] Open the app once: the existing history is all there (Calendar, Rewards balance, Library notes). Level and coins match what you had.
- [ ] Delete the app icon from the home screen and reinstall if the icon or launch screen still shows the old look: iOS caches both.

## 1. First look

- [ ] **Icon** on the home screen: light, then dark (Control Center → dark mode), then *Customise → Tinted*. Is the sparkle readable at that size? Does tinted look right?
- [ ] **Launch screen**: force-quit and reopen. Cream with the sparkle in light, dark canvas with a light sparkle in dark. No white flash before it. It hands over to Today without a jump.
- [ ] Today in **light and dark**, outdoors if you can: are the five tier colours, the beige routine and the umber epic still distinguishable in daylight? (Routine beige vs amber and epic umber vs crimson are close in lightness, only hue separates them.)
- [ ] The Caveat labels (`cleared`, `this week`, `0 / 3 done`, the date line, coins) are not clipped on their last letter.

## 2. The daily flows (use them for real for a day)

Complete things the way you normally would and watch for friction.

- [ ] **Quest**: tap the circle → one card on a dimmed page, `?` box, `Complete` / `Not yet` → the number rolls and lands → rating row → `Done`. Does the sequence feel quick enough for something you do several times a day? Does the reel feel like a reveal or like a delay?
- [ ] `Not yet` and a tap on the dark area both leave without doing anything.
- [ ] Tapping the dark area **while rolling** skips to the landed number.
- [ ] **Routine**: fixed `+N` under the title (no `?` box), `Complete` → straight to `+N`, `paid` and the rating row.
- [ ] **Epic**: ask card, roll, rating. The done circle on the umber card reads clearly (white disc, dark tick).
- [ ] **Ahead → Do now** (a routine for later this week).
- [ ] **⋯ menu** on a quest and a routine: card popover with prices. Pick *Reroll*: popover closes, then the spend card appears (no flicker, nothing swallowed).
- [ ] **Long-press** a card: the system context menu still offers the same actions.
- [ ] **Add (+)** → From library: search field filters, picking a hidden row keeps the hint chip, `Add` works. **Custom**: type text, the doodle suggestion changes, pick another, add it, it shows on Today and later in Calendar's day detail.
- [ ] **Replace** a quest and a routine, and **Replace the epic**: same page, library search works.
- [ ] **Rewards**: balance card, the goal card, `Redeem` → card → `Not yet`; one real redeem if you want to. Edit a reward, toggle *Saving for this*.
- [ ] **Calendar**: step through months with the arrows (slide + haptic), tap a day, the day detail cards; the *Did not finish* card under the legend when a month has given-up routines; Ratings page.
- [ ] **Library** (Settings): tiers collapse and expand and remember their state; search expands matches; Routines show their weekday strips; open one routine's *Schedule* card.
- [ ] **Workout detection** (Settings): pick calendars, keywords, tap *Check for workouts now*. With a real calendar event whose title contains a keyword, the *Last check* card says it matched, and an auto-verify item on Today ticks itself.
- [ ] **Levels sheet** (tap the level card on Today).
- [ ] **Restore from JSON** — only if you are happy to replace the history with the backup you made in step 0: the centered card lists the numbers, `Not yet` leaves everything as it was.

## 3. Haptics (never felt so far)

Settings → Sounds & Haptics → System Haptics must be on; they don't fire in some Low Power / silent combinations.

- [ ] Complete a quest: a firm tap on `Complete`, a rigid tap when the number lands, a softer one for a bonus (a hidden quest or a lucky roll).
- [ ] Rating buttons: a light selection tick on each pick.
- [ ] Calendar month change: a selection tick.
- [ ] Library tier header toggle: a selection tick.
- [ ] Workout check: success buzz when something got verified, a plain tick otherwise.
- [ ] Level-up: the dots stagger, the `+N` float and a haptic. (Needs a real level-up: you may have to wait for one.)
- [ ] Are any of them too strong, too frequent, or missing where you'd expect one?

## 4. Accessibility

Do each pass for a few minutes on Today, one popup flow, Rewards and Settings.

**VoiceOver** (Settings → Accessibility → VoiceOver; triple-click the side button as a shortcut)
- [ ] Each card on Today is **one** element and reads title, what it pays, state. The actions (Complete, ⋯ items) are in the rotor's *Actions*.
- [ ] When the popup card appears, focus lands on the main button (`Complete` / `Spend N` / `OK`); *Not yet* is reachable; a two-finger scrub (escape) dismisses it. The page behind is not read.
- [ ] The roll announces `Paid 18 coins` (or `Paid 10 coins` for a routine) once it lands.
- [ ] Rating buttons say what they are (*Liked it*, etc.) and which is picked.
- [ ] Library tier headers say expanded / collapsed; the weekday strip is not read letter by letter.
- [ ] Calendar days read the date and what happened; the legend reads as a sentence.
- [ ] Add: the doodle picker reads each doodle's name and which one is picked; the library search field's *Clear* is reachable.
- [ ] Settings rows read as one element with a hint; the About line is not a trap.

**Reduce Motion** (Settings → Accessibility → Motion)
- [ ] The popup card: no scrolling reel and no sparkles; the number simply appears and the card fades between phases. Haptics still fire.
- [ ] Month change in Calendar: a fade, no slide.
- [ ] Nothing important depends on an animation.

**Bold Text** (Settings → Display & Brightness)
- [ ] Today, the popup card, Rewards, Library: no clipped or overlapping text; Caveat labels stay readable.

**Larger Text** (Settings → Accessibility → Display & Text Size → Larger Text, max size)
- [ ] Today cards, the popup card (ask and rate), Add page, Rewards cards, Library rows, Calendar. The month grid stops growing at a cap by design; everything else should wrap and scroll, never clip.
- [ ] Add → the segmented control and library rows at the largest size (two-line wrap is known).
- [ ] Add's one-line text field truncates a long title at big sizes (known, tell me if it bothers you).

**Contrast / Smart Invert / Increase Contrast** (optional)
- [ ] Anything unreadable with Increase Contrast on.

## 5. Things the simulator could not produce

- [ ] **A low-energy day** (`low` or `veryLow` tier): the three-micro-action tile, a routine's lighter version (`Use light` / `Do original`), and the *Did the original / Did a lighter version* ask when doing one ahead.
- [ ] **`Can't reroll`**: reroll until the pool is empty; the same card turns into the explanation.
- [ ] **Negative balance** (e.g. after penalties): the balance card turns clay with the debt message, `Redeem` is blocked with *Clear the debt first*.
- [ ] **A failed import**: try restoring a deliberately broken JSON (copy your backup and delete its last line): the red banner row appears and nothing changes.
- [ ] **Workout detection's calendar list** with real calendars (the simulator only had one state).
- [ ] **Health permission denied** / revoked: Settings still opens, the debug sensor report says so.
- [ ] **Every-N-days, monthly and every-N-weeks routines** if you have any: their Library group, strip and *Schedule* card.
- [ ] A long **reward name** in the editor (truncates in the one-line field, known).

## 6. Judgement calls, only your eyes can settle

Mark each: keep / change.

- [ ] The five tier colours + beige routine + umber epic as a set.
- [ ] The doodles: twenty of them now. Are the new ten (headphones, camera, paw, fork and knife, moon, heart, speech bubble, map pin, screen, broom) as readable as the old ones at row size? Any quest still showing the sparkle that deserves its own?
- [ ] The app icon (the sparkle on cream) at home-screen size next to your other apps.
- [ ] The reel: nice moment or one beat too long?
- [ ] The `?` box before Complete: clear that it is a surprise, or confusing?
- [ ] Popovers use the system's translucent arrow style (cannot be changed). OK?
- [ ] Anything that still looks like the old plain look: tell me which screen.

## 7. Send me

A list in this form is enough:

```
screen / step — what happened — expected — light or dark — text size
```

Or just the item numbers that failed and a screenshot.
