---
title: Session Conversation ID Persistence
type: component
sources: [S062]
updated: 2026-11-17
---

# Session Conversation ID Persistence

The chat remembers the displayed conversation in `session[:ai_helper][:conversation_id]`.
`AiHelperController#set_conversation_id` writes it from `chat` and `conversation`;
`call_llm` reads it back on the next request (S062).

## The gotcha: nested session hashes must be reassigned

Writing `session[:ai_helper][:conversation_id] = id` mutates the nested hash in place.
With a change-detecting store such as activerecord-session_store 2.3.0, that write is
lost (S062):

- `get_session` returns the loaded record's `data` as is, and `write_session` skips the
  save unless `record.changed?` (S062).
- `ActionDispatch::Request::Session` copies only the top level, so the nested hash is
  the same object as the record's `@data`. Old and new values compare equal and nothing
  is saved (S062).
- The symptom (issue #568): `chat` creates a conversation, but `call_llm` sees an empty
  `ai_helper` and fails. It reproduced with both the marshal and json serializers (S062).
- Redmine's default `cookie_store` serializes the whole session on every response, so
  the bug is invisible there (S062).

## Fix

`set_conversation_id` reassigns the top-level key with a new hash:
`session[:ai_helper] = session[:ai_helper].merge(conversation_id: id)`, with an English
comment giving the reason. The session structure is unchanged (S062).

- `create_session` (a `before_action` on every action except `api_create_health_report`)
  guarantees `session[:ai_helper]` is a hash for both callers. A `nil` raises
  `NoMethodError` rather than being absorbed (S062).
- Under the json serializer the loaded value is a `HashWithIndifferentAccess`, and
  `merge` keeps it that way, so `[:conversation_id]` still reads (S062).

## Rejected alternatives

- `session[:ai_helper].to_h.merge(...)`: `.to_h` silently turns `nil` into `{}`, against
  the no-absorbing-unexpected-values rule (S062).
- Moving the ID to a separate top-level key: the clear and delete paths would change, and
  the displayed conversation would drop right after an update (S062).
- Mutate, then `session[:ai_helper] = session[:ai_helper].dup`: two lines hiding the
  intent; `merge` does it in one (S062).

## Testing

A functional test (`ActionController::TestCase`) cannot reproduce this, because
`@request.session` is one object across requests and in-place writes persist (S062).
The regression test is an integration test that swaps `CookieStore` for a minimal
change-detecting store defined in the test file (no new gem), driving login →
`chat_form` → `chat` → `call_llm` with the LLM stubbed (S062). Assert on the messages
saved in the database, because streaming makes in-block variable assertions unreliable
(S062).

No ADR was written and no docs/README describe session handling (S062).

## Related

[AI Chat Sidebar](./chat-sidebar.md) · [Plugin Overview](./plugin-overview.md)
