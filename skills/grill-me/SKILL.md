---
name: grill-me
description: "Invoke when the user says grill me, interrogate me, or ask me questions first - or when the task is phrased such that you cannot honestly write a done sentence from it: the goal is clear in words, but what would verify it and what is out of scope are not. Invoke before define-done, not instead of it. Do not invoke when the task is clear and done writes itself, and do not invoke as a substitute for reading the code: anything the repository can tell you comes from the repository, not from the user."
---

# grill-me — interrogate until the understanding is shared

Origin: `grilling` from [mattpocock/skills](https://github.com/mattpocock/skills), MIT.
The tree-and-rounds mechanic comes from there; the rules about language, the
round ceiling and the exit condition are ours.

## Output of this skill

**One "done" sentence for [define-done], confirmed by the user in words.** Not a
summary, not a list of questions, not a document. Until that sentence exists the
interrogation is not finished; once it exists and is confirmed, it is, even if
there was more that could have been asked.

## Mechanics

**Decisions form a tree, not a list.** Hanging off each decision are the ones that
only make sense after it. "Which language do we write the menu in" and "how do we
translate ingredient names" are not two questions in a row; the second grows out
of the first.

**The frontier is every decision whose prerequisites are already settled.** Those
are exactly the questions you can ask **now** without guessing at answers you have
not heard yet.

**A question whose answer depends on another open question in the same round
does not belong in that round.** It goes in the next one. Breaking this rule is
the main reason an interrogation turns into a questionnaire: half the answers are
invalidated by the first one.

**A round is the whole frontier in one message.** Number the questions, give
**your own recommended answer** to each, then wait. Not one question per message —
that exhausts the user and stretches the work over ten passes instead of three.

```
**Q1 — <heading>**: <the question; several paragraphs and options are fine>

Recommended: <my recommended answer and briefly why>

---

**Q2 — <heading>**: <…>

Recommended: <…>
```

**The user's answers rebuild the tree:** settled decisions push the frontier
outward and open what depended on them. Recompute the frontier, ask the next round.

**It ends when the frontier is empty:** every branch walked, nothing left silently
assumed.

## Rules, without which this skill does harm

**1. Five questions per round, maximum.** More than that, cut by importance and
carry the rest to the next round. The user may not be a programmer; twelve
questions at once reads as a refusal to work, not as thoroughness.

**2. Plain language.** No file names, no flags, no jargon in the question. If a
term is needed, explain it first and put the term in brackets after. A question
the user did not understand is worse than one never asked: it gets answered at
random, and the random answer ends up inside "done".

**3. I find the facts, the user makes the decisions.** Anything sitting in code, a
database, logs or documents is my work, not a question. Asking "do our recipes
store portions?" instead of running the query is handing my job to the user.
The order is: notice a question needs a fact from the environment -> send an agent
to find it (invoke [agent-spec] first) -> **do not wait for it**, ask the rest of
the frontier. An unfinished search leaves only the branch that depends on it open.

**4. A recommendation on every question.** A question with no answer of your own
is handing over the decision, not interrogating. No recommendation means a
missing fact, see rule 3.

**5. No action until confirmation.** No code edits, no plan file, until the user
says the understanding is shared. The interrogation is preparation, not the start
of the work.

## Excuses

| the thought | what is actually true |
|---|---|
| "the task is clear, I'll ask as I go" | questions asked along the way get paid for in rework. "Done" is written before the start, and there is nothing to write it from |
| "I'll ask everything at once, in one pass" | questions from deeper in the tree depend on unanswered ones — half the answers will be void |
| "one question at a time is more careful" | more careful and ten times slower. A round is the whole frontier, not one question |
| "let the user tell me how the code works" | that is my search, not theirs. Rule 3 |
| "I have no recommendation, it's an open question" | then a fact is missing. Find the fact, then ask |
| "I have asked enough, I'll start" | the end is an empty frontier and a confirmed sentence, not a feeling of sufficiency |

## Related skills

- Immediately after — [define-done]: the confirmed sentence becomes the first line of the plan.
- Fact-finding by agent — [agent-spec] (kind of work, model, acceptance of the answer).

[define-done]: ../define-done/SKILL.md
[agent-spec]: ../agent-spec/SKILL.md
