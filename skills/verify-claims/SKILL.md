---
name: verify-claims
description: "Verify file:line citations in a document by reading the actual files. For each cited location, return CONFIRMED, STALE_LINE or HALLUCINATED, with the code that is actually there. Use BEFORE committing any plan, spec or audit document that references code. Automates the rule verify, do not recall."
---

# Verify claims

Run this skill when:
- You are about to commit a document that cites code (`file.java:42 says X`, `function Y at line N`).
- You are reviewing someone else's plan, spec or audit for accuracy.
- You suspect a document was written from memory, the symptom is vague hedging: "probably", "likely", "should be".

Do NOT use for:
- Documents with no code citations (architectural narrative, decision records without specifics).
- A document you just wrote with citations you verified as you went.

## What it does

Spawns one agent that walks every `file:line` citation in the target document,
opens each file, and checks whether the claim is literally true today.

## How to invoke

Ask the user for the **target document path**.

Then dispatch one agent with this prompt structure:

> Read `<target-doc-path>`. For every claim that cites a file path, a line number
> and a statement about the code, open the cited file at the cited lines and
> verify the claim is literally true today. Give one of three verdicts per claim:
> - **CONFIRMED**, the cited code exists at the cited location and matches the claim. Quote one or two lines.
> - **STALE_LINE**, the claim is true but the line numbers drifted. Give the correct ones.
> - **HALLUCINATED**, the cited code does not exist, or the claim is false. Quote what is actually there.
>
> Output format: a markdown table with columns Claim / Verdict / Note. Do not
> write "probably", verify by reading. After the table, list any claims where the
> surrounding ANALYSIS (not just the quote) looks wrong given the actual code.
> If a cited file does not exist, write NOT_FOUND and the path you tried, do not guess.

## After the agent returns

For each STALE_LINE, fix the line numbers in the document.
For each HALLUCINATED, investigate: was the file refactored, or was the claim
invented? Remove it or rewrite it from the actual code.
For each "the analysis looks wrong" note, take a fresh look at that specific claim.

## Cost

One to three minutes, 10-30K tokens depending on document size and citation count.

## Origin

A remediation document was written partly from memory. A re-audit found the
citations were about 85% accurate, and the proposed FIXES about 50% accurate.
One of them would have broken production: it revoked a database grant that a
repository class was actively using. The citations being mostly right is what
made the document persuasive. Verifying before the commit costs minutes.
