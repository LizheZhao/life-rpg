# Journal prompts — draft for review

Status: in Core as `JournalPool` (`LifeRPGCore/Sources/LifeRPGCore/Rules/JournalPool.swift`), and a test keeps the code rows identical to the tables below. Edit a row here and the test says what to change in code.

**These rows are not shown to the user, and not shown to the model either.** An evaluation on the device model showed it copying any example it was given, word for word. The editor's "Ask me something" button sends the model the day's facts, what the user has written so far with an instruction to ask about one specific thing in it, and the questions already in the entry; the on-device model words one fresh question. The rows still do three jobs. `JournalAsk` picks up to three of them by the day (a low day gets the heavy rows, a routine given up on the skip rows, a quest rated 1 or more the good rows, otherwise the opening rows) and holds the answer against them, so a row coming back is rejected. They are the chip fallback and the day-question rows below. The prompt lists the questions already in the entry but not those of the last three entries: a small model copies from a list it is told to avoid, so those are only held against its answer. The facts carry no coins, and say "done before its day" or "N days before it was due" only where that is true. Core rejects wording that breaks a rule below or sits too close to an anchor row, to a question in the entry or to a recent question. An answer rejected only for being too close to one of those is asked for once more, with the prompt plus one sentence naming the rejected question and asking for something else from the facts (5 second limit). When the model is unavailable or its wording is rejected after that, the editor inserts a fixed prompt instead, in this order: favorite moment, grateful for, tomorrow, low energy felt like. Those four are the chips above the keyboard, and they are the only fixed prompts.

Borrowed question shapes (this is a journaling aid, not therapy): open questions and scaling (motivational interviewing), self-compassion and separating feeling from fact (CBT-style), savoring (positive psychology), values questions (ACT), exceptions and small steps (solution-focused).

Rules for every prompt, written by hand and for the model:

- One question at a time. No advice, no diagnosis.
- Never start with "why". Use "what got in the way", "what was it like".
- An open question: not one that can be answered yes or no. Do not restate the facts; just ask.
- No coins, points or numbers from the facts. "Early" or "ahead" only when a fact says so.
- No praise-or-guilt framing. The app already docks points; the voice must not pile on.
- No contrast staging ("not X, but Y"), no closing one-liner that repeats the point, no triads for rhythm.
- Placeholder: `{quest}` is the quest or routine text.

Language follows the system language (`zh-Hans` → Chinese, anything else → English). Each row carries both.

## Opening — the whole day (always asked first)

| id | en | zh-Hans |
|---|---|---|
| open.scale | If today were a number from 1 to 10, what would it be? What kept it from being lower? | 如果给今天打 1 到 10 分，你会打几分？是什么没让它更低？ |
| open.feel | The day is almost over. How do you feel right now? | 这一天快结束了，你现在感觉怎么样？ |
| open.keep | What from today do you want to remember? | 今天有什么事，你想记住？ |

## Heavy day — low rating, low energy, or lots done with little joy

| id | en | zh-Hans |
|---|---|---|
| heavy.done | You got a lot done today, and it doesn't sound like it felt good. What was it like? | 今天你做了不少事，但听起来感觉并不好。当时是什么样的？ |
| heavy.weight | Where did the day weigh on you most, in your body or in your mood? | 这一天压在你身上最重的地方在哪，是身体还是情绪？ |
| heavy.friend | If a friend had a day like this, what would you say to them? | 如果朋友过了这样的一天，你会对他说什么？ |
| heavy.body | Your body had less to give today. What did it ask for? | 今天身体能给的比平时少。它想要什么？ |

## Good day — something done today rated 1 or higher

| id | en | zh-Hans |
|---|---|---|
| good.moment | You rated {quest} high. Which moment was the best part? | 你给「{quest}」打了高分。哪一刻最好？ |
| good.repeat | If you did {quest} again, what would you keep exactly the same? | 如果再做一次「{quest}」，你想原样保留什么？ |
| good.who | Who or what made it better? | 是谁或是什么让它变得更好？ |

## Skipped or overdue — asked without blame

| id | en | zh-Hans |
|---|---|---|
| skip.block | {quest} didn't happen. What got in the way? | 「{quest}」没做成。是什么挡了一下？ |
| skip.exception | Was there a recent time this went more easily? What was different then? | 最近有没有哪次做这件事比较顺？那次有什么不一样？ |
| skip.small | What would make it 10% easier tomorrow? | 怎样能让它明天容易一成？ |

## From the day — asked when the model could not be used, filled with one thing from today

| id | en | zh-Hans |
|---|---|---|
| fact.early | {quest} got done ahead of time. What did finishing it feel like? | 「{quest}」提前完成了。完成那一刻是什么感觉？ |
| fact.hard | {quest} was a hard one. What was the toughest moment? | 「{quest}」不轻松。最难的是哪一刻？ |
| fact.open | {quest} is still open. What got in the way today? | 「{quest}」还没做。今天是什么挡了一下？ |
| fact.done | You finished {quest} today. What was it like? | 你今天完成了「{quest}」。当时是什么样的？ |

## Safety line (shown instead of any follow-up when the answer hits a self-harm or hopelessness keyword)

| id | en | zh-Hans |
|---|---|---|
| safety | That sounds heavy. This is only a journaling tool and can't help the way a person can. If you might hurt yourself, please reach out to someone you trust or a local crisis line. | 听起来很沉重。这只是个记日记的工具，帮不上真人能帮的忙。如果你有可能伤害自己，请联系信任的人，或当地的危机求助热线。 |
