# CRF-019: Test stripped script blocks from HTML with a regular expression

**Date**: 2026-10-12
**Source**: GitHub CodeQL (PR #505)
**Feature**: branch `feature/071-web-search-citations` / PR #505
**Files**: test/functional/ai_helper_controller_test.rb
**Category**: test-gap
**Related**: None

## Feedback

CodeQL flagged the same line twice: "Incomplete multi-character sanitization" (the string may still contain `<script`) and "Bad HTML filtering regexp" (the pattern does not match upper-case `<SCRIPT>` tags).
See <https://github.com/haru/redmine_ai_helper/security/code-scanning/77> and <https://github.com/haru/redmine_ai_helper/security/code-scanning/78>.

## Original Code

```ruby
assert_no_match(/#{Regexp.escape(I18n.t(:label_ai_helper_citations))}/, response.body.sub(/<script.*?<\/script>/m, ""))
```

## Fix

Parse the response with Nokogiri, remove every `script` element, and assert on the remaining text:

```ruby
doc = Nokogiri::HTML(response.body)
doc.css("script").remove
assert_not_includes doc.text, I18n.t(:label_ai_helper_citations)
```

## Root Cause

The AI wanted to exclude inline JavaScript from a "text is absent" assertion and reached for a quick regex idiom. `sub` removes only the first script block (the chat partial renders several), and the pattern is case-sensitive and tag-shape dependent, so the assertion did not check what it claimed. It was not a vulnerability because the result is never rendered, but the assertion was weaker than intended. The AI did not consider that Nokogiri (already available through Rails' `assert_select`) parses HTML properly.

## Prevention

In tests, never transform or filter HTML with regular expressions. To assert on part of a response, use `assert_select` or parse with `Nokogiri::HTML` and select/remove nodes with CSS selectors.

**Promoted to**: Not yet
