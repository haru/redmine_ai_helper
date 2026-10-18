# ADR-061: Draw the health report PDF body with Redmine's PDF renderer from the screen HTML

**Date**: 2026-10-18
**Status**: Accepted

## Context

The health report PDF drew the body with its own pipeline: a regular expression
looked for Markdown tables, `textilizable` and plain-text conversion handled the
rest, a hand-written table drawer laid out the cells, and a `rescue` fell back to
a simplified plain-text rendering when anything raised. Two tables separated by a
blank line were merged into one, separator rows were drawn as data, long cells
were truncated, and a failure in the table path printed the same content twice
(drawn tables plus the fallback text). The screen already renders the body once
through `md_to_html` (ADR-044), so the PDF and the screen followed two different
sets of conversion rules.

## Decision

- The PDF body is built from the same HTML as the screen. The conversion lives in
  one place, `AiHelperHelper#health_report_html_with_chart_markers`, which
  replaces chart directives with marker paragraphs and runs the whole body
  through `linkify_issue_references(md_to_html(...))` once. The screen
  (`render_health_report_markdown`) and the PDF both call it.
- `ProjectHealthPdfChartHelper#render_pdf_body` walks the top-level nodes of that
  HTML. Nodes between markers are drawn with Redmine core's
  `ITCPDF#RDMwriteFormattedCell` (the writer Redmine uses for issue and wiki
  PDFs), with an empty attachment list. Charts are drawn at their marker's
  position by the existing chart renderer, which is unchanged.
- The HTML is not adjusted before drawing, so elements look the way they do in
  Redmine's own PDFs.
- The fallback is removed. An exception from the conversion or the drawing
  propagates and the export fails, in line with the project rule against
  fallback error handling. The eleven helper methods of the old pipeline are
  deleted; `add_simple_paragraph_to_pdf` stays for the chart "unavailable" text.

## Consequences

- Tables, headings, lists, code, quotes and rules match the screen's element
  kinds, text and order; the text formatting setting does not change the result.
- The conversion rule is implemented once, so screen and PDF cannot drift apart.
- Appearance follows Redmine's PDF writer, not the screen's CSS: for example,
  inline code is not monospaced, quotes are only indented, and bullets repeat
  after three nesting levels. This is the same look as Redmine's own PDFs.
- Images are not fetched: with no attachments, rbpdf prints the file name instead
  of the image, and no external URL is requested.
- A body that makes the renderer raise now fails the export instead of producing
  a degraded PDF.

## Alternatives Considered

- **Fix the existing pipeline** (regular expression and `strip_tags`): would mean
  re-implementing GFM table rules in a regular expression, and headings, lists
  and quotes would still not follow the screen.
- **Walk the DOM and draw with `cell`/`multi_cell`**: needs custom wrapping, row
  heights, page breaks and nesting, all of which `writeHTMLCell` already has.
- **Call rbpdf `writeHTML` directly**: leaves table borders and `th` styling to be
  rebuilt; `RDMwriteFormattedCell` already supplies them as in Redmine's PDFs.
- **Pass the Markdown to `RDMwriteHTMLCell`**: it converts with
  `Setting.text_formatting`, so a Textile site would not read the body as
  Markdown (conflicts with ADR-044) and issue links would differ from the screen.
- **Adjust the HTML to resemble the screen** (bold `th`, monospaced `code`, a
  bar for quotes): possible in a prototype, but rejected; matching Redmine's own
  PDF output is the accepted look.
- **Convert each text part between charts separately**: reference-style link
  definitions across a chart would resolve differently from the screen, so the
  single shared conversion is used.
