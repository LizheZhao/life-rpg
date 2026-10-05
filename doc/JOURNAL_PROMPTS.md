# Journal prompts — draft for review

Status: in Core as `JournalPool` (`LifeRPGCore/Sources/LifeRPGCore/Rules/JournalPool.swift`), and a test keeps the code rows identical to the tables below. Edit a row here and the test says what to change in code.

**These rows are not shown to the user.** They only serve as style anchors. The editor's "Ask me something" button sends the day's facts and up to three rows of the kind that fits the day as style anchors (see `JournalAsk`: a low day gets the heavy rows, a routine given up on the skip rows, a quest rated 1 or more the good rows, otherwise the opening rows), and the on-device model words one fresh question. Core rejects wording that breaks a rule below or sits too close to an anchor or to a recent question. When the model is unavailable or its wording is rejected, the editor inserts a fixed prompt instead, in this order: favorite moment, grateful for, tomorrow, low energy felt like. Those four are the chips above the keyboard, and they are the only fixed prompts. Each row also carries an `approach` tag in code (scale, self-compassion, savoring, values, exceptions, reflection, open); the tags live only there.

Borrowed question shapes (this is a journaling aid, not therapy): open questions and scaling (motivational interviewing), self-compassion and separating feeling from fact (CBT-style), savoring (positive psychology), values questions (ACT), exceptions and small steps (solution-focused). Reflective listening is the glue: a follow-up first restates the user's own words, then asks one question.

Rules for every prompt, written by hand and for the model:

- One question at a time. No advice, no diagnosis.
- Never start with "why". Use "what got in the way", "what was it like".
- No praise-or-guilt framing. The app already docks points; the voice must not pile on.
- Reuse the user's words in a follow-up; do not paraphrase them into something fancier.
- No contrast staging ("not X, but Y"), no closing one-liner that repeats the point, no triads for rhythm.
- Placeholders: `{quest}` quest text, `{item}` what the user chose, `{phrase}` a short quote from their last answer.

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

## Choice and noticing — photo quests, picking an object, "look at" quests

| id | en | zh-Hans |
|---|---|---|
| choice.photo | Of the photos you took, which is your favorite? What pulled you to it? | 你拍的照片里，最喜欢哪一张？它哪里吸引了你？ |
| choice.item | You picked {item}. What made it the one? | 你选了{item}。是什么让它成为那个？ |
| choice.notice | What did you notice today that you would normally walk past? | 今天你注意到了什么，是平时会直接走过的？ |

## Skipped or overdue — asked without blame

| id | en | zh-Hans |
|---|---|---|
| skip.block | {quest} didn't happen. What got in the way? | 「{quest}」没做成。是什么挡了一下？ |
| skip.exception | Was there a recent time this went more easily? What was different then? | 最近有没有哪次做这件事比较顺？那次有什么不一样？ |
| skip.small | What would make it 10% easier tomorrow? | 怎样能让它明天容易一成？ |

## Follow-ups — after the user answers (Core fills `{phrase}` with a quote of the answer)

| id | en | zh-Hans |
|---|---|---|
| follow.stand | You said "{phrase}". What stands out to you about that? | 你说到「{phrase}」。关于这一点，你最在意的是什么？ |
| follow.more | Say more about "{phrase}". | 再多说一点「{phrase}」吧。 |
| follow.need | What does "{phrase}" tell you about what you need right now? | 「{phrase}」让你看到自己现在需要什么？ |

## Closing

| id | en | zh-Hans |
|---|---|---|
| close.more | Anything else you want to put down before you close the day? | 合上今天之前，还有什么想写下来的吗？ |
| close.carry | Is there one thing you want to carry into tomorrow? | 有没有一件事，你想带进明天？ |

## Safety line (shown instead of any follow-up when the answer hits a self-harm or hopelessness keyword)

| id | en | zh-Hans |
|---|---|---|
| safety | That sounds heavy. This is only a journaling tool and can't help the way a person can. If you might hurt yourself, please reach out to someone you trust or a local crisis line. | 听起来很沉重。这只是个记日记的工具，帮不上真人能帮的忙。如果你有可能伤害自己，请联系信任的人，或当地的危机求助热线。 |
