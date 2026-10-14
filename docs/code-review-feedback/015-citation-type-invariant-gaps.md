# CRF-015: Web citation types left invariants unenforced at their edges

**Date**: 2026-10-12
**Source**: Local AI review (`/speckit-review-run`, types and errors agents)
**Feature**: branch `feature/071-web-search-citations`
**Files**: lib/redmine_ai_helper/web_citation.rb, app/models/ai_helper_message.rb, lib/redmine_ai_helper/agents/web_search_agent.rb, lib/redmine_ai_helper/agents/leader_agent.rb
**Category**: convention-violation
**Related**: CRF-009

## Feedback

- `WebCitation` was documented as immutable but stored the caller's strings by reference and was not frozen.
- `WebCitation.from_h` did not check for a Hash (nil → `NoMethodError`, Array → `TypeError`).
- `WebCitation.from_ruby_llm` used `citation.url.to_s.strip`, letting `to_s` absorb unexpected types (CRF-009).
- `AiHelperMessage#web_citations=(nil)` raised `NoMethodError` instead of the documented `ArgumentError`, and the raw serialized `citations=` could store any shape, which only failed later when rendering.
- `WebSearchAgent#citations` (`attr_reader`) exposed the internal array to mutation.
- `LeaderAgent#@citations` was not reset at the start of `perform_user_request`, so a reused instance kept the previous request's sources.

## Original Code

```ruby
@url = url
@title = title&.strip&.empty? ? nil : title
...
return nil if citation.url.nil? || citation.url.to_s.strip.empty?
...
def from_h(hash)
  new(url: hash["url"], title: hash["title"])
end
```

## Fix

`WebCitation` dups and freezes its strings and itself; `from_h` raises `ArgumentError` for a non-Hash; `from_ruby_llm` checks the String type explicitly before the blank check. `web_citations=` raises `ArgumentError` for a non-Array, and `AiHelperMessage` validates that stored `citations` is nil or an array of hashes with a String `"url"`. `WebSearchAgent#citations` returns a frozen copy. `LeaderAgent#perform_user_request` resets `@citations`. Each branch has a test.

## Root Cause

The AI applied CRF-009 to the main constructor (`initialize`) but not to the secondary entry points (`from_h`, `from_ruby_llm`, the model setter, the raw serialized attribute) or to the object's exposure (`attr_reader` of a mutable array, unfrozen value object). The comment "immutable" was written from intent, not checked against the code. The per-request reset was skipped because the only caller currently builds a new instance per request.

## Prevention

For a value object or typed attribute, apply the invariant checks to every way a value can enter (constructor, every `from_*` factory, model setters, the raw persisted attribute via a validation) and every way it leaves (return frozen copies, freeze the object if it is documented immutable). Instance state that describes "the last request" is reset at the start of the request method, regardless of how callers currently use the instance.

**Promoted to**: Not yet
