---
title: Health Report Charts Gotchas
type: component
sources: [S051, S052]
updated: 2026-11-21
---

# Health Report Charts Gotchas

Gotchas when working on report charts. Split from [Health Report Charts](./health-report-charts.md).

## Gotchas

- Redmine 6.0.x has no importmap at all and 6.1.x has one without a `chart.js`
  pin: `ai_helper_chart_heads` must check `respond_to?(:importmap)` and is
  also needed on the project overview partial (S052).
- rbpdf's snake_case methods (`add_page`) are aliases bound to the original
  method, so a `prepend`ed recorder only sees them if it wraps the alias too
  (S052).
- On the project overview a MutationObserver re-adds the POST-based export
  links during generation; the swap must remove them, otherwise charts are
  exported as "no metrics" (S052).
- `renderWithin(node)` on an observer's added node must also test the node
  itself; in Ruby `array[index - 1]` wraps at index 0 (S052).
- `ProjectHealthPdfChartHelper` draws the whole PDF body, not only the charts:
  the HTML that the shared conversion produces between the markers is written
  with Redmine's `RDMwriteFormattedCell`, and the module raises when a marker
  paragraph did not survive as a top-level `<p>` or when the body carries an
  `<img>` (feature 079). The module was split from `ProjectHealthPdfHelper` to
  stay under RuboCop's module length (S051).
- rbpdf's PDF look diverges from the screen in documented ways: a blockquote is
  indentation only (`openHTMLTagHandler`/`closeHTMLTagHandler` move the margin
  by `listindent`), inline `<code>` keeps the current font because the tag
  handlers have no `code` case, and unordered bullets repeat
  disc/circle/square every three nesting levels (`putHtmlListBullet`:
  `deftypes[(listdepth - 1) % 3]`) (feature 079, ADR-061).
- rbpdf drops an `<img>` whose `src` matches no attachment without an error:
  `ITCPDF#get_image_filename` (`lib/redmine/export/pdf.rb`) returns nil and
  rbpdf's `proc_image_file` rescues its own error and draws nothing. The PDF
  export therefore raises when the body contains `<img>` instead of losing the
  image silently (feature 079).

## Related

- [Health Report Charts](./health-report-charts.md) — the main page.
