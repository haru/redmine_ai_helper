/**
 * Chat popup: moves the sidebar chat (#aihelper-sidebar) into a fixed,
 * non-modal, movable and resizable popup and back (ADR-064). The pure layout
 * rules live in ai_helper_chat_popup_layout.js (AiHelperChatPopupLayout).
 *
 * The element itself is moved, never cloned, so every ID the chat scripts
 * rely on stays unique and the conversation, the input value and the
 * streaming state are kept as they are.
 */
const AiHelperChatPopup = (() => {
  const DEFAULT_OFFSET = 24;
  const NARROW_QUERY = '(max-width: 899px)';
  const ANIMATION_MS = 200;
  const LAYOUT_KEY = 'aihelper-popup-layout';
  const OPEN_KEY = 'aihelper-popup-open';
  const DRAFT_KEY = 'aihelper-popup-draft';
  const INPUT_ID = 'ai-helper-message-input';
  const OPPOSITE_BUTTON = { 'aihelper-popup-open': 'aihelper-popup-close', 'aihelper-popup-close': 'aihelper-popup-open' };
  const Layout = AiHelperChatPopupLayout;

  let mediaQuery = null;
  let animationToken = 0;
  let closing = false;
  let sidebarHeight = 0;
  let drag = null;

  /**
   * Look up an element that the sidebar ERB renders.
   * @param {string} id - Element ID.
   * @returns {HTMLElement} The element.
   */
  function requiredElement(id) {
    const element = document.getElementById(id);
    if (!element) {
      throw new Error(`AiHelperChatPopup: #${id} not found`);
    }
    return element;
  }

  /**
   * Get the chat element that is shown in the sidebar or as the popup.
   * @returns {HTMLElement} The #aihelper-sidebar element.
   */
  function chatElement() {
    return requiredElement('aihelper-sidebar');
  }

  /**
   * Build a per-user storage key.
   * @param {string} name - Key prefix, e.g. LAYOUT_KEY.
   * @returns {string} The key including the current user ID.
   */
  function storageKey(name) {
    return `${name}_${ai_helper.userId}`;
  }

  /**
   * Tell whether this tab is in popup mode (the saved open state), whatever
   * the current screen width is.
   * @returns {boolean} True when the open state is saved for this tab and user.
   */
  function isPopupState() {
    return sessionStorage.getItem(storageKey(OPEN_KEY)) === 'true';
  }

  /**
   * Tell whether the chat is currently shown as the popup.
   * @returns {boolean} True when the chat element is in popup mode.
   */
  function isPopup() {
    return chatElement().classList.contains('aihelper-popup-mode');
  }

  /**
   * Tell whether Redmine has moved the sidebar into its flyout menu, where
   * the popup is not offered (FR-001, R-009).
   * @returns {boolean} True on a narrow screen.
   */
  function isNarrow() {
    return mediaQuery.matches;
  }

  /**
   * Get the visible viewport size.
   * @returns {{width: number, height: number}} The viewport.
   */
  function viewport() {
    return { width: document.documentElement.clientWidth, height: document.documentElement.clientHeight };
  }

  /**
   * Compute the default layout from the sidebar chat's measured box: the
   * same size, shifted slightly down and to the left (FR-014). The foldable
   * area is shown for the measurement, so a folded sidebar chat gives its
   * expanded height (R-008); its inline display is restored at once.
   * @returns {{left: number, top: number, width: number, height: number}} The default layout.
   */
  function defaultLayout() {
    const area = requiredElement('aihelper-foldable-area');
    const inlineDisplay = area.style.display;
    area.style.display = '';
    const rect = chatElement().getBoundingClientRect();
    area.style.display = inlineDisplay;
    return {
      left: rect.left - DEFAULT_OFFSET,
      top: rect.top + DEFAULT_OFFSET,
      width: rect.width,
      height: rect.height,
    };
  }

  /**
   * Read the saved layout. Only the JSON SyntaxError is handled; storage
   * errors surface.
   * @returns {{left: number, top: number, width: number, height: number}|null} The saved layout, or null when missing, unparsable or invalid.
   */
  function savedLayout() {
    const raw = localStorage.getItem(storageKey(LAYOUT_KEY));
    if (raw === null) {
      return null;
    }
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (error) {
      if (!(error instanceof SyntaxError)) {
        throw error;
      }
      return null;
    }
    return Layout.isValid(parsed) ? parsed : null;
  }

  /**
   * Read the layout to open with. A missing or invalid saved value is replaced
   * by the default layout, which is saved (R-008) unless it is unusable, for
   * example because the sidebar has no box; then it is only displayed, fitted
   * to the minimum size.
   * @returns {{left: number, top: number, width: number, height: number}} The layout to use.
   */
  function readLayout() {
    const saved = savedLayout();
    if (saved !== null) {
      return saved;
    }
    const layout = defaultLayout();
    if (Layout.isValid(layout)) {
      localStorage.setItem(storageKey(LAYOUT_KEY), JSON.stringify(layout));
    }
    return layout;
  }

  /**
   * Apply a layout to the chat element as inline pixel styles.
   * @param {{left: number, top: number, width: number, height: number}} layout - Layout to apply.
   */
  function applyLayout(layout) {
    const style = chatElement().style;
    style.left = `${layout.left}px`;
    style.top = `${layout.top}px`;
    style.width = `${layout.width}px`;
    style.height = `${layout.height}px`;
  }

  /**
   * Read the layout currently applied to the chat element.
   * @returns {{left: number, top: number, width: number, height: number}} The applied layout.
   */
  function currentLayout() {
    const style = chatElement().style;
    return {
      left: parseFloat(style.left),
      top: parseFloat(style.top),
      width: parseFloat(style.width),
      height: parseFloat(style.height),
    };
  }

  /**
   * Run a DOM move of the chat element and restore focus and the scroll
   * position of the conversation (its end). Moving an element drops its
   * focus; when the focused element was the open or close button, which is
   * hidden after the move, the other button takes the focus.
   * @param {() => void} move - Callback that moves the chat element.
   */
  function keepingFocusAndScroll(move) {
    const element = chatElement();
    const focused = element.contains(document.activeElement) ? document.activeElement : null;
    move();
    if (focused) {
      const target = OPPOSITE_BUTTON[focused.id] ? document.getElementById(OPPOSITE_BUTTON[focused.id]) : focused;
      target.focus();
    }
    const conversation = requiredElement('aihelper-chat-conversation');
    conversation.scrollTop = conversation.scrollHeight;
  }

  /**
   * Move the chat to the body as the popup. The layout is applied inside the
   * move so the conversation is scrolled with its final height.
   * @param {boolean} animate - Move from the sidebar position to the layout over 200ms (FR-018).
   */
  function show(animate) {
    const element = chatElement();
    const from = element.getBoundingClientRect();
    sidebarHeight = from.height;
    const layout = Layout.clamp(readLayout(), viewport());
    keepingFocusAndScroll(() => {
      document.body.appendChild(element);
      element.classList.add('aihelper-popup-mode');
      applyLayout(animate ? { ...layout, left: from.left, top: from.top } : layout);
    });
    if (!animate) {
      return;
    }
    const token = ++animationToken;
    element.classList.add('aihelper-popup-animating');
    // Force a reflow so the transition starts from the sidebar position.
    void element.offsetWidth;
    applyLayout(layout);
    setTimeout(() => {
      if (token === animationToken) {
        element.classList.remove('aihelper-popup-animating');
      }
    }, ANIMATION_MS);
  }

  /**
   * Move the chat back to the top of the sidebar at once. Ends a running
   * animation, so a pending close timer does nothing afterwards.
   */
  function hide() {
    const element = chatElement();
    const wrapper = requiredElement('sidebar-wrapper');
    drag = null;
    closing = false;
    animationToken += 1;
    keepingFocusAndScroll(() => {
      wrapper.insertBefore(element, wrapper.firstChild);
      element.classList.remove('aihelper-popup-mode', 'aihelper-popup-animating');
      element.style.left = '';
      element.style.top = '';
      element.style.width = '';
      element.style.height = '';
    });
  }

  /**
   * Open the popup from the icon (FR-002). Does nothing on a narrow screen
   * or when the popup is already open. The open state is saved only after
   * the popup is shown, so a failure leaves no state that would hide the chat
   * on every later page.
   */
  function open() {
    if (isNarrow() || isPopup()) {
      return;
    }
    show(true);
    sessionStorage.setItem(storageKey(OPEN_KEY), 'true');
  }

  /**
   * Close the popup (FR-003, FR-019): the saved open state and draft are
   * removed at once, the position and size change to the sidebar slot over
   * 200ms, and then the chat returns to the sidebar. The input value stays as
   * it is. A second call during the animation does nothing.
   */
  function close() {
    if (!isPopup() || closing) {
      return;
    }
    const slot = requiredElement('sidebar-wrapper').getBoundingClientRect();
    closing = true;
    drag = null;
    sessionStorage.removeItem(storageKey(OPEN_KEY));
    sessionStorage.removeItem(storageKey(DRAFT_KEY));
    const element = chatElement();
    const token = ++animationToken;
    element.classList.add('aihelper-popup-animating');
    // Force a reflow so the transition starts from the popup layout.
    void element.offsetWidth;
    applyLayout({ left: slot.left, top: slot.top, width: slot.width, height: sidebarHeight });
    setTimeout(() => {
      if (token === animationToken) {
        hide();
      }
    }, ANIMATION_MS);
  }

  /**
   * Make the chat match the saved open state and the screen width: the popup
   * when open on a wide screen, the sidebar otherwise.
   */
  function applyState() {
    const wanted = isPopupState() && !isNarrow();
    if (wanted && !isPopup()) {
      show(false);
    } else if (!wanted && isPopup()) {
      hide();
    }
  }

  /**
   * Start dragging the popup by its header, or resizing it by a handle.
   * @param {PointerEvent} event - The pointerdown event.
   * @param {string|null} edge - Handle edge, or null when the header is dragged.
   */
  function startDrag(event, edge) {
    if (event.button !== 0 || drag || closing || !isPopup()) {
      return;
    }
    if (event.target.closest('a, .aihelper-hamburger, .aihelper-dropdown-menu')) {
      return;
    }
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    drag = { pointerId: event.pointerId, edge, x: event.clientX, y: event.clientY, start: currentLayout(), moved: false };
  }

  /**
   * Update the layout while dragging. Nothing is saved until the drag ends.
   * @param {PointerEvent} event - The pointermove event.
   */
  function moveDrag(event) {
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }
    const delta = { x: event.clientX - drag.x, y: event.clientY - drag.y };
    drag.moved = true;
    applyLayout(drag.edge === null ? Layout.moved(drag.start, delta, viewport()) : Layout.resized(drag.start, drag.edge, delta, viewport()));
  }

  /**
   * Build the layout to save after a drag that moved. The displayed position
   * is kept, but an axis the user did not change keeps its saved size, so a
   * window that is currently small does not overwrite the original layout.
   * @param {string|null} edge - Handle edge, or null when the header was dragged.
   * @returns {{left: number, top: number, width: number, height: number}} The layout to save.
   */
  function layoutToSave(edge) {
    const current = currentLayout();
    const saved = savedLayout();
    if (saved === null) {
      return current;
    }
    return {
      left: current.left,
      top: current.top,
      width: edge !== null && /[ew]/.test(edge) ? current.width : saved.width,
      height: edge !== null && /[ns]/.test(edge) ? current.height : saved.height,
    };
  }

  /**
   * Finish a drag on pointerup. The layout is saved once, and only when the
   * pointer actually moved.
   * @param {PointerEvent} event - The pointerup event.
   */
  function endDrag(event) {
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }
    const finished = drag;
    drag = null;
    if (finished.moved) {
      localStorage.setItem(storageKey(LAYOUT_KEY), JSON.stringify(layoutToSave(finished.edge)));
    }
  }

  /**
   * Abandon a drag (pointercancel or lost pointer capture): the layout from
   * before the drag is shown again and nothing is saved (R-007).
   * @param {PointerEvent} event - The pointercancel or lostpointercapture event.
   */
  function cancelDrag(event) {
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }
    const start = drag.start;
    drag = null;
    applyLayout(start);
  }

  /**
   * Make an element a drag source: header (edge null) or resize handle.
   * @param {HTMLElement} element - The element that receives the pointer events.
   * @param {string|null} edge - Handle edge, or null for the header.
   */
  function enableDrag(element, edge) {
    element.addEventListener('pointerdown', (event) => startDrag(event, edge));
    element.addEventListener('pointermove', moveDrag);
    element.addEventListener('pointerup', endDrag);
    element.addEventListener('pointercancel', cancelDrag);
    element.addEventListener('lostpointercapture', cancelDrag);
  }

  /**
   * Fit the popup to the current viewport. The fitted layout is not saved,
   * so a larger window brings the saved layout back. A drag in progress is
   * abandoned, because its start layout no longer matches the viewport. With
   * no usable saved layout the popup stays as it is.
   */
  function fitToViewport() {
    if (!isPopup()) {
      return;
    }
    drag = null;
    const saved = savedLayout();
    if (saved !== null) {
      applyLayout(Layout.clamp(saved, viewport()));
    }
  }

  /**
   * Restore the unsent draft after the chat form is loaded (FR-016). Only a
   * tab in popup mode carries a draft, and text already typed is kept.
   * The draft is assigned as a value, never as HTML.
   */
  function restoreDraft() {
    const input = requiredElement(INPUT_ID);
    const draft = sessionStorage.getItem(storageKey(DRAFT_KEY));
    if (!isPopupState() || input.value !== '' || draft === null) {
      return;
    }
    input.value = draft;
  }

  /**
   * Make the input show the stored draft after the page is restored from the
   * back/forward cache, where the page still holds the text from before it
   * was cached. In popup mode the stored draft is the newest; no draft means
   * an empty input. An input that has not loaded yet is left alone.
   */
  function syncDraft() {
    const input = document.getElementById(INPUT_ID);
    if (!isPopupState() || !input) {
      return;
    }
    const draft = sessionStorage.getItem(storageKey(DRAFT_KEY));
    input.value = draft === null ? '' : draft;
  }

  /**
   * Save the unsent text when the page is left (R-004). The draft is kept for
   * the next page only in popup mode; an empty input (for example after a
   * send) leaves no draft, and an input that has not loaded yet leaves the
   * previous draft untouched.
   */
  function saveDraft() {
    const key = storageKey(DRAFT_KEY);
    const input = document.getElementById(INPUT_ID);
    if (!isPopupState()) {
      sessionStorage.removeItem(key);
      return;
    }
    if (!input) {
      return;
    }
    if (input.value === '') {
      sessionStorage.removeItem(key);
    } else {
      sessionStorage.setItem(key, input.value);
    }
  }

  /**
   * Show the page again after the back/forward cache restored it (R-010):
   * the mode, the saved layout and the draft are taken from storage, and a
   * drag that was cut off by leaving the page is dropped.
   */
  function restoreFromCache() {
    drag = null;
    applyState();
    fitToViewport();
    syncDraft();
  }

  /**
   * Wire the open and close controls, follow the screen width, and restore
   * the popup that this tab had on the previous page (FR-012). Whatever
   * happens, the chat is revealed afterwards by removing
   * `aihelper-popup-pending`, so an error never leaves it hidden (R-005).
   */
  function init() {
    try {
      mediaQuery = window.matchMedia(NARROW_QUERY);
      mediaQuery.addEventListener('change', applyState);
      requiredElement('aihelper-popup-open').addEventListener('click', (event) => {
        event.preventDefault();
        open();
      });
      requiredElement('aihelper-popup-close').addEventListener('click', (event) => {
        event.preventDefault();
        close();
      });
      enableDrag(chatElement().querySelector('.aihelper-header'), null);
      chatElement().querySelectorAll('.aihelper-popup-resize').forEach((handle) => enableDrag(handle, handle.dataset.edge));
      window.addEventListener('resize', fitToViewport);
      window.addEventListener('pagehide', saveDraft);
      window.addEventListener('pageshow', (event) => {
        if (event.persisted) {
          restoreFromCache();
        }
      });
      applyState();
    } finally {
      document.documentElement.classList.remove('aihelper-popup-pending');
    }
  }

  return {
    init,
    open,
    close,
    restoreDraft,
  };
})();

window.AiHelperChatPopup = AiHelperChatPopup;
