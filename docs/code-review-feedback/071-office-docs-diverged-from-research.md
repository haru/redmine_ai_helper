# CRF-071: Office attachment docs and YARD diverged from research and the logger's behaviour

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, simplify)
**Feature**: branch `080-office-attachment-markdown`
**Files**: docs/adr/062-office-attachments-sent-as-redmine-markdown-preview.md, docs/office_document_attachments.md, lib/redmine_ai_helper/util/attachment_file_helper.rb
**Category**: doc-comment
**Related**: CRF-011, CRF-016, CRF-032, CRF-043

## Feedback

comments review: ADR-062's alternatives did not match research R-001–R-003 (dropped FR-001, added a reason from another alternative, reworded the FR-012/FR-003 reasons); the admin doc said logs "go to `log/ai_helper.log`", but `CustomLogger` writes to Rails.logger without a `logger` section and to `logger[:file]` when set; "runs inside the request" ignored vector indexing; "indicates a damaged cache file" stated a cause research only called likely; `text_attachment?` YARD did not say that Office documents return true, `llm_attachment_source` @param said "a supported attachment", and the `HTML_IMAGE_PATTERN` comment asserted Pandoc behaviour research R-008 marks as not verified.

## Original Code

```markdown
- Adding `docx`/`xlsx`/… to the plugin's extension list: ignores whether Pandoc
  is available and its version, and sends formats the LLM APIs reject.
...
Messages go to `log/ai_helper.log`:
```

## Fix

ADR alternatives rewritten from R-001–R-004 with the research reasons and section numbers; log destination described from `CustomLogger.log_file_path`; scope widened to vector indexing; cause softened to "typically"; YARD/comments corrected and R-008 cited.

## Root Cause

The ADR was summarised from memory of the research rather than copied from the cited sections (CRF-032's rule, not applied). The log sentence was copied from earlier docs' convention without reading `CustomLogger`. Comments described the call site the AI had in mind rather than every input the method accepts.

## Prevention

When an ADR lists alternatives, open the cited R-NNN sections and copy each alternative's reason, with the section number next to it. Any doc sentence naming a file, destination or scope is checked against the code that decides it (here `CustomLogger.log_file_path`) in the same step.

**Promoted to**: Not yet
