/**
 * Moves the server-rendered (but hidden) AI Helper legend item into the
 * project list's existing legend paragraph (the one containing the
 * bookmarked-project icon), so the legend explains the AI Helper icon shown
 * in the project list. Does nothing when either element is absent, e.g. on
 * pages other than the logged-in projects#index (no legend paragraph) or
 * when the AI Helper module has no legend item queued.
 */
document.addEventListener('DOMContentLoaded', function() {
  const legendItem = document.getElementById('ai-helper-index-legend-item');
  if (!legendItem) {return;}

  const bookmarkIcon = document.querySelector('.icon-bookmarked-project');
  if (!bookmarkIcon) {return;}

  const legend = bookmarkIcon.parentElement;
  if (!legend) {return;}

  legendItem.hidden = false;
  legend.appendChild(legendItem);
});
