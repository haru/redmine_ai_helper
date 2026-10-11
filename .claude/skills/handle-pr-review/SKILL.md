---
name: "handle-pr-review"
description: "Handle GitHub PR review findings (Copilot or human) end to end: fetch the review threads, judge whether each finding is valid, report the verdicts and wait for approval, fix only the valid ones, record them with record-code-review-feedback, then reply to every thread with the reason and resolve it. Use whenever the user mentions PR review comments, Copilot review findings, 'レビュー指摘', 'レビュー対応', asks whether review findings are valid, or asks to resolve review threads, even if they only give a PR number."
argument-hint: "PR number (defaults to the PR of the current branch)"
user-invocable: true
disable-model-invocation: false
---

# Handle PR Review Findings

Review findings are claims about the code, not orders. Some are right, some describe things that were already like that before the PR, and some are right in a way that spreads to files the reviewer never looked at. The job is to check each claim against the repository, fix what is genuinely wrong, and leave a written reason on every thread so the reviewer and later readers can see why it was closed.

Talk to the user in Japanese (project convention); write code, docs, commit-adjacent text and GitHub replies in English.

## Phase 1: Collect and verify (read-only)

1. Determine the PR: the argument, else `gh pr view --json number -q .number`.
2. Fetch the review summary and the inline comments:

   ```bash
   gh pr view <PR> --json title,headRefName,reviews,comments
   gh api repos/{owner}/{repo}/pulls/<PR>/comments --jq '.[] | {id, path, line, body, user: .user.login}'
   ```

   Ignore bot noise that is not a finding (e.g. Codecov), but mention coverage gaps if relevant.
3. For each finding, open the code or doc it points to and decide on evidence, not on the reviewer's wording:
   - Is the claim true in the current tree? (read the lines, grep the callers, run `git log`/`git show develop:<file>` when the claim is about something that predates the PR)
   - Did this PR introduce it, or was it already the practice on `develop`? Pre-existing practice is normally "not adopted in this PR" and a separate decision.
   - Does the same defect exist elsewhere that the reviewer did not flag? Grep for the old wording / API name; fixing only the flagged line leaves the same bug one file over.
   - Does a test actually exercise the branch? "Never exercised" claims are verified by grepping how the predicate is stubbed.

## Phase 2: Report verdicts and stop

Present a table: finding, verdict (valid / not needed), priority, and one or two sentences of evidence with `file:line` links. Say what the fix would be and whether it needs a feedback record. Then **wait**. The user's answer to a verdict report is not approval to start editing; proceed only on an explicit instruction such as "fix the valid ones". If a fix would change existing specified behaviour or shared behaviour, raise that before touching it.

## Phase 3: Fix the valid findings only

- Follow AGENTS.md conventions. For tests, use `bundle exec ruby -I"lib:test" plugins/redmine_ai_helper/test/...` from the Redmine root (never `rails test`, and do not migrate the test DB on your own).
- New guard or `raise` branches need a test that drives the condition to true and asserts the error; cover streaming and non-streaming paths if both exist. Never add rescue-and-return-empty fallbacks to make a finding go away.
- Doc fixes: update every place that states the old behaviour, including ones the reviewer missed. ADRs are append-only once merged, but an ADR added by the same unmerged PR may be corrected.
- Ruby files touched: run `rubocop --ignore-parent-exclusion <files>` and fix offenses.
- Run the affected test files and report the run/failure counts. If you did not verify something (e.g. that removing the guard makes the new test fail), say so.

## Phase 4: Record

For adopted findings that changed code, or docs that contradicted real behaviour, invoke the `record-code-review-feedback` skill with the PR number and a short list of what was adopted and what was not. Typo-only or wording-only fixes and findings not adopted are not recorded. If the new entry relates to earlier entries (same pattern again), propose where to promote the rule (e.g. AGENTS.md) with the exact text, and wait for approval.

## Phase 5: Reply and resolve every thread

Every thread gets a reply with its reason, fixed or not, and then gets resolved. A bare resolve leaves the reviewer guessing; a reply with a reason on an unfixed finding is what makes closing it legitimate.

Reply wording:
- Fixed: say what changed and where. If nothing is pushed yet, say "Will be included in the next push."
- Not adopted: say why (e.g. pre-existing practice on `develop`, out of scope for this PR, reviewer's claim is incorrect) and where it should be handled instead, if anywhere.

Get thread IDs, then reply and resolve:

```bash
gh api graphql -f query='query{repository(owner:"OWNER",name:"REPO"){pullRequest(number:PR){reviewThreads(first:50){nodes{id isResolved comments(first:1){nodes{databaseId path}}}}}}}' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | [.id, .isResolved, .comments.nodes[0].databaseId, .comments.nodes[0].path] | @tsv'

# per thread: <databaseId> is the comment id, <threadId> is PRRT_...
gh api repos/OWNER/REPO/pulls/PR/comments/<databaseId>/replies -f body="..."
gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<threadId>"}){thread{isResolved}}}'
```

Replies and resolves are visible to others and cannot be quietly undone, so only do them after the user has approved the verdicts in Phase 2 and asked for them (the user's instruction to fix and resolve covers it).

## Final report

Summarise in Japanese: files changed (as links), test/RuboCop results, what was not adopted and why, the recorded feedback entries, and any promotion proposal. Do not commit or push; tell the user the changes are uncommitted and offer to commit when they ask.
