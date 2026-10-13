# SF-009: Discord reaction error claimed to come from the official docs without checking them

**Date**: 2026-10-13
**Feature**: specs/072-restore-slack-processing-reaction (branch `072-restore-slack-processing-reaction`)
**Artifact**: research.md (R-004), contracts/processing_reaction.md, tasks.md, quickstart.md
**Category**: unconfirmed-assumption
**Related**: SF-008

## Feedback

A local review found that the Discord adapter ignored `404` + code `10014` on `clear_processing`, with a comment saying 10014 meant "the reaction is already gone". The user asked: "Check the official Discord documentation too." The AI then checked the docs and showed two options. The user chose option A: remove the ignored error and correct the spec.

## What the AI Wrote

- research.md R-004: "`DELETE` with no own reaction will be 404 (JSON code 10014 Unknown Emoji); ignore only `status == 404 && code == 10014`. **This behaviour is an assumption based on the official documentation**; real-device confirmation is in the quickstart."
- research.md R-004 also said: "The reaction `PUT` is idempotent and returns 2xx even when already present."
- contracts §4: "Ignored error: removal `DiscordRequestError` with `status == 404` and `code == 10014` (Unknown Emoji)."
- tasks T021 / T023 / T027 and quickstart §3 step 6 tested, implemented and checked that rule.

## Correction

- R-004 now cites the official pages ([Message resource](https://docs.discord.com/developers/resources/message), [Opcodes and Status Codes](https://docs.discord.com/developers/topics/opcodes-and-status-codes)). Both `PUT` and `DELETE` return 204 on success. Nothing is documented for an existing or missing reaction. 10014 is documented as the error for an emoji that is not URL-encoded. Discord therefore has no ignored error: 10014, 10008 and 403 are all raised to the gateway and logged.
- Contracts §4 and §5, tasks T021 / T023 / T027 / T041 and quickstart §3 step 6 were updated to match. The quickstart now expects 204 for a `DELETE` on a message with no ⏳. If it gets anything else, the result is recorded and discussed with the user.
- Code, tests, ADR-053 and the wiki page were updated in the same change.

## Root Cause

The AI wrote the Discord error behaviour from memory and labelled it "based on the official documentation" without opening the documentation. It reasoned by analogy with Slack's `no_reaction`: it expected Discord to have a matching "not reacted" error and picked a reaction-related code (10014 "Unknown Emoji") from the error-code list. It never looked up what that code means. The real-device check it scheduled (T041) was left until after implementation, so the guess went into the code and the tests unchallenged. Its idempotency claim for `PUT` is also not stated in the docs.

## Prevention

When a spec or research note says an external API behaves in a certain way (status code, error code, idempotency), open the official documentation in that step and cite the page. If the docs do not cover the case, write "not documented" and do not label the claim "based on the documentation". Never design an ignored-error rule around an undocumented response; raise it (and log it) until the behaviour has been confirmed.

**Promoted to**: AGENTS.md
