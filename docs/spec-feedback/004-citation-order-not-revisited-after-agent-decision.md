# SF-004: Kept a citation order tied to the final answer after choosing a dedicated search agent

**Date**: 2026-10-12
**Feature**: specs/071-web-search-citations (branch `feature/071-web-search-citations`)
**Artifact**: spec.md
**Category**: other (a requirement was not re-checked after an earlier clarification changed the architecture it depended on)
**Related**: None

## Feedback

During `/speckit-clarify`, the user answered: "List every citation the web search agent obtained during the question, whether or not the leader agent used that information in the final answer (merge citations from multiple calls and remove duplicates)." Applying this answer required rewriting FR-009c, which the AI had already written.

## What the AI Wrote

> **FR-009c**: 同じ URL の出典は1回だけ表示しなければならない。表示順は、回答の中で最初に使われた順とする。

("Show each URL once. Order them by where they are first used in the answer.")

## Correction

FR-009c now orders citations by the order of the web search agent calls, and within one call by the order the provider returned them. A duplicate keeps its first position. FR-003e now states that every citation from every web search agent call in the question is listed, and that the LLM must not choose which ones to list.

## Root Cause

The AI wrote FR-009c in the first draft, before the architecture was decided. At that point it assumed the provider attaches citations to the text of the answer the user sees, so "first used in the answer" was a natural order. The first clarification round (`/speckit-specify`, Q1: A) then chose a dedicated web search agent. Its output reaches the user only through a separate LLM call by the leader agent, so provider citations attach to the agent's intermediate answer and have no position in the final answer text. The AI updated the FR-003 requirements for the new agent but did not re-read the citation requirements (FR-009 and its sub-items), which still depended on the old assumption. The contradiction surfaced only when a later clarify question asked how citations flow from the agent to the final answer.

## Prevention

After applying a clarification that changes where or how a value is produced (which agent, which LLM call, which layer), search the spec for every requirement that consumes that value (citations, tokens, settings, etc.), re-read each one, and rewrite any wording that assumes the old producer before moving on to the next question.

**Promoted to**: Not yet
