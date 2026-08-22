// Tests for AiHelperAutoCompletion request lifecycle
// These tests verify the fix for GitHub issue #392, where in-flight completion
// requests were never aborted and piled up until the browser ran out of
// same-origin connections, freezing unrelated actions such as saving an issue.
//
// To run these tests, a JavaScript test environment (e.g., Jest + jsdom) is required.
// If no JS test environment is available, the behavior should be verified manually
// using the procedure described in
// specs/045-fix-autocompletion-request-pileup/quickstart.md
//
// Behaviour contracts covered here (C-1 .. C-7) are defined in
// specs/045-fix-autocompletion-request-pileup/contracts/completion-request-flow.md
//
// Assertions go through check(); runTest() prints PASSED only for a test that
// recorded no failure, and runAllTests() returns the number of failed
// assertions so a runner can turn it into an exit status.

// A failed assertion has to be visible: console.assert neither throws nor
// returns anything, so a test using it reported PASSED whatever it found. Every
// assertion below goes through check(), which counts failures, and runTest()
// prints PASSED only for a test that produced none.
let totalFailures = 0;
let currentTestFailures = 0;

// Captured before any test replaces console.error with a spy of its own.
const reportFailure = console.error.bind(console);

/**
 * Helper: Assert a condition, recording a failure instead of throwing.
 * @param {boolean} condition The condition that must hold
 * @param {string} message What went wrong, printed when it does not
 */
function check(condition, message) {
  if (!condition) {
    currentTestFailures++;
    totalFailures++;
    reportFailure(`FAILED: ${message}`);
  }
}

/**
 * Helper: Run one test, reporting its result and surviving an exception in it.
 * @param {string} name The contract id and description of the test
 * @param {Function} testFn The test body, sync or async
 */
async function runTest(name, testFn) {
  currentTestFailures = 0;
  try {
    await testFn();
  } catch (error) {
    currentTestFailures++;
    totalFailures++;
    reportFailure(`FAILED: ${name} threw ${error && error.stack ? error.stack : error}`);
  }
  if (currentTestFailures === 0) {
    console.log(`PASSED: ${name}`);
  }
}

/**
 * Helper: Create a minimal DOM environment for a single textarea instance.
 * @param {string} contextType 'description' | 'note' | 'wiki'
 */
function createTextareaDOM(contextType = 'description') {
  const checkboxIds = {
    description: 'ai-helper-autocompletion-description-toggle',
    note: 'ai-helper-autocompletion-notes-toggle',
    wiki: 'ai-helper-autocompletion-wiki-toggle'
  };
  const containerIds = {
    description: 'ai-helper-description-checkbox-container',
    note: 'ai-helper-notes-checkbox-container',
    wiki: 'ai-helper-wiki-checkbox-container'
  };

  const container = document.createElement('div');

  const textarea = document.createElement('textarea');
  textarea.id = `textarea-${contextType}`;
  container.appendChild(textarea);

  const checkboxContainer = document.createElement('div');
  checkboxContainer.id = containerIds[contextType];

  const checkbox = document.createElement('input');
  checkbox.type = 'checkbox';
  checkbox.id = checkboxIds[contextType];
  checkboxContainer.appendChild(checkbox);
  container.appendChild(checkboxContainer);

  document.body.appendChild(container);

  return { container, textarea, checkbox };
}

/**
 * Helper: Build an initialized AiHelperAutoCompletion instance in enabled state.
 * localStorage defaults the toggle to OFF, so enable it explicitly.
 */
function createCompletion(textarea, options = {}) {
  const completion = new AiHelperAutoCompletion(textarea, {
    endpoint: '/projects/1/ai_helper/issue/1/suggest_completion',
    debounceDelay: 0,
    minLength: 1,
    ...options
  });
  completion.init();
  completion.isEnabled = true;
  if (completion.checkbox) {
    completion.checkbox.checked = true;
  }
  return completion;
}

/**
 * Helper: Replace global fetch with a stub that records every call and lets the
 * test settle each call individually.
 * @returns {{calls: Array, restore: Function}} calls have {url, options, resolve, reject}
 */
function installFetchStub() {
  const originalFetch = globalThis.fetch;
  const calls = [];

  globalThis.fetch = function (url, options) {
    const call = { url: url, options: options, resolve: null, reject: null };
    call.promise = new Promise((resolve, reject) => {
      call.resolve = (data) => resolve({ ok: true, status: 200, json: () => Promise.resolve(data) });
      call.reject = reject;
    });
    calls.push(call);
    return call.promise;
  };

  return {
    calls: calls,
    restore: () => { globalThis.fetch = originalFetch; }
  };
}

/**
 * Helper: Wrap global AbortController so that abort() calls can be counted.
 * Each created instance is recorded in the returned `instances` array.
 */
function installAbortControllerSpy() {
  const OriginalAbortController = globalThis.AbortController;
  const instances = [];

  globalThis.AbortController = class SpyAbortController extends OriginalAbortController {
    constructor() {
      super();
      this.abortCallCount = 0;
      instances.push(this);
    }

    abort() {
      this.abortCallCount++;
      super.abort();
    }
  };

  return {
    instances: instances,
    restore: () => { globalThis.AbortController = OriginalAbortController; }
  };
}

/**
 * Helper: Build a DOMException-like AbortError, matching what fetch rejects with
 * when its signal is aborted.
 */
function buildAbortError() {
  const error = new Error('The user aborted a request.');
  error.name = 'AbortError';
  return error;
}

/**
 * Helper: Let queued promise callbacks run.
 */
function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * Helper: Wait for a fixed number of milliseconds.
 */
function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// C-1: single in-flight request (FR-001, FR-002)
// ---------------------------------------------------------------------------

// Test: issuing a second request aborts the first one and passes a signal to fetch
async function testSecondRequestAbortsFirst() {
  const fetchStub = installFetchStub();
  const abortSpy = installAbortControllerSpy();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.callCompletionAPI('first text', 10, 1);
  const firstController = completion.abortController;

  check(firstController != null,
    'C-1 FAILED: abortController should be set after the first request');
  check(fetchStub.calls[0].options.signal === firstController.signal,
    'C-1 FAILED: fetch must receive the controller signal');

  completion.callCompletionAPI('second text', 11, 2);

  check(firstController.abortCallCount === 1,
    `C-1 FAILED: first controller should be aborted once, got ${firstController.abortCallCount}`);
  check(completion.abortController !== firstController,
    'C-1 FAILED: a new AbortController should be created for the second request');
  check(fetchStub.calls[1].options.signal === completion.abortController.signal,
    'C-1 FAILED: second fetch must receive the new controller signal');
  check(abortSpy.instances.length === 2,
    `C-1 FAILED: exactly two controllers expected, got ${abortSpy.instances.length}`);

  container.remove();
  fetchStub.restore();
  abortSpy.restore();
}

// Test: the in-flight request is released once the response settles
async function testControllerClearedAfterResponse() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'first text';
  completion.callCompletionAPI('first text', 10, ++completion.currentRequestId);
  fetchStub.calls[0].resolve({ suggestion: '' });
  await flushPromises();

  check(completion.abortController === null,
    'C-1 FAILED: abortController should be null once the response has settled (invariant I-2)');

  container.remove();
  fetchStub.restore();
}

// ---------------------------------------------------------------------------
// C-2: every teardown path aborts through clearSuggestion (FR-003)
// ---------------------------------------------------------------------------

// Test: clearSuggestion aborts the in-flight request
function testClearSuggestionAborts() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.callCompletionAPI('some text', 9, 1);
  const controller = completion.abortController;

  completion.clearSuggestion();

  check(controller.signal.aborted,
    'C-2 FAILED: clearSuggestion must abort the in-flight request');
  check(completion.abortController === null,
    'C-2 FAILED: clearSuggestion must release the controller');

  container.remove();
  fetchStub.restore();
}

// Test: turning the checkbox off aborts the in-flight request
function testDisablingCheckboxAborts() {
  const fetchStub = installFetchStub();
  const { container, textarea, checkbox } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.callCompletionAPI('some text', 9, 1);
  const controller = completion.abortController;

  checkbox.checked = false;
  checkbox.dispatchEvent(new Event('change'));

  check(controller.signal.aborted,
    'C-2 FAILED: disabling autocompletion must abort the in-flight request');

  container.remove();
  fetchStub.restore();
}

// Test: losing focus aborts the in-flight request
async function testBlurAborts() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.callCompletionAPI('some text', 9, 1);
  const controller = completion.abortController;

  completion.onBlur();
  await wait(150);

  check(controller.signal.aborted,
    'C-2 FAILED: blur must abort the in-flight request');

  container.remove();
  fetchStub.restore();
}

// Test: accepting a suggestion aborts the in-flight request
function testAcceptSuggestionAborts() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'some text';
  completion.currentSuggestion = { text: ' completed', cursorPosition: 9 };
  completion.callCompletionAPI('some text', 9, 1);
  const controller = completion.abortController;

  completion.acceptSuggestion();

  check(controller.signal.aborted,
    'C-2 FAILED: accepting a suggestion must abort the in-flight request');

  container.remove();
  fetchStub.restore();
}

// Test: dismissing with Esc aborts the in-flight request
function testEscapeAborts() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.currentSuggestion = { text: ' completed', cursorPosition: 9 };
  completion.callCompletionAPI('some text', 9, 1);
  const controller = completion.abortController;

  completion.onKeyDown({ key: 'Escape', preventDefault: () => {} });

  check(controller.signal.aborted,
    'C-2 FAILED: Esc must abort the in-flight request');

  container.remove();
  fetchStub.restore();
}

// Test: destroy() aborts the in-flight request (page navigation edge case)
function testDestroyAborts() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.callCompletionAPI('some text', 9, 1);
  const controller = completion.abortController;

  completion.destroy();

  check(controller.signal.aborted,
    'C-2 FAILED: destroy must abort the in-flight request');

  container.remove();
  fetchStub.restore();
}

// ---------------------------------------------------------------------------
// C-3: aborting is a normal outcome, never an error (FR-004)
// ---------------------------------------------------------------------------

// Test: an AbortError rejection produces no console output and no error UI
async function testAbortErrorIsSilent() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  const originalConsoleError = console.error;
  const errorCalls = [];
  console.error = (...args) => errorCalls.push(args);

  completion.callCompletionAPI('some text', 9, ++completion.currentRequestId);
  fetchStub.calls[0].reject(buildAbortError());
  await flushPromises();

  console.error = originalConsoleError;

  check(errorCalls.length === 0,
    `C-3 FAILED: AbortError must not be logged, got ${errorCalls.length} console.error call(s)`);
  check(completion.currentSuggestion === null,
    'C-3 FAILED: AbortError must not produce a suggestion');

  container.remove();
  fetchStub.restore();
}

// Test: non-abort errors are still reported, as before
async function testOtherErrorsStillLogged() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  const originalConsoleError = console.error;
  const errorCalls = [];
  console.error = (...args) => errorCalls.push(args);

  completion.callCompletionAPI('some text', 9, ++completion.currentRequestId);
  fetchStub.calls[0].reject(new Error('HTTP error! status: 500'));
  await flushPromises();

  console.error = originalConsoleError;

  check(errorCalls.length === 1,
    `C-3 FAILED: non-abort errors must still be logged, got ${errorCalls.length}`);

  container.remove();
  fetchStub.restore();
}

// ---------------------------------------------------------------------------
// C-4: late responses are discarded (FR-005)
// ---------------------------------------------------------------------------

// Test: a response that arrives after the request id advanced is not displayed
async function testStaleResponseByRequestIdIsDiscarded() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'some text';
  const staleRequestId = ++completion.currentRequestId;
  completion.callCompletionAPI('some text', 9, staleRequestId);

  // A newer request supersedes it (this is what abort races with)
  completion.cancelPendingRequest();

  fetchStub.calls[0].resolve({ suggestion: ' late suggestion' });
  await flushPromises();

  check(completion.currentSuggestion === null,
    'C-4 FAILED: a superseded response must not be displayed');

  container.remove();
  fetchStub.restore();
}

// Test: a response is discarded when the text changed since the request was sent
async function testStaleResponseByTextChangeIsDiscarded() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'some text';
  const requestId = ++completion.currentRequestId;
  completion.callCompletionAPI('some text', 9, requestId);

  textarea.value = 'some text edited';

  fetchStub.calls[0].resolve({ suggestion: ' late suggestion' });
  await flushPromises();

  check(completion.currentSuggestion === null,
    'C-4 FAILED: a response for outdated text must not be displayed');

  container.remove();
  fetchStub.restore();
}

// ---------------------------------------------------------------------------
// C-7: instances are independent
// ---------------------------------------------------------------------------

// Test: aborting one textarea's request leaves the other's request untouched
function testInstancesDoNotShareAbortController() {
  const fetchStub = installFetchStub();
  const description = createTextareaDOM('description');
  const notes = createTextareaDOM('note');

  const descriptionCompletion = createCompletion(description.textarea, { contextType: 'description' });
  const notesCompletion = createCompletion(notes.textarea, { contextType: 'note' });

  descriptionCompletion.callCompletionAPI('description text', 16, 1);
  notesCompletion.callCompletionAPI('notes text', 10, 1);

  const descriptionController = descriptionCompletion.abortController;
  const notesController = notesCompletion.abortController;

  check(descriptionController !== notesController,
    'C-7 FAILED: instances must not share an AbortController');

  descriptionCompletion.clearSuggestion();

  check(descriptionController.signal.aborted,
    'C-7 FAILED: the description request should be aborted');
  check(notesController.signal.aborted === false,
    'C-7 FAILED: the notes request must not be affected');
  check(notesCompletion.abortController === notesController,
    'C-7 FAILED: the notes controller must remain in flight');

  description.container.remove();
  notes.container.remove();
  fetchStub.restore();
}

// ---------------------------------------------------------------------------
// C-5: no request when nothing changed (FR-011)
// ---------------------------------------------------------------------------

// Test: a second request for identical text and cursor is not sent
function testNoRequestWhenTextAndCursorUnchanged() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);

  completion.requestSuggestion();
  check(fetchStub.calls.length === 1,
    `C-5 precondition FAILED: the first request should be sent, got ${fetchStub.calls.length}`);

  completion.requestSuggestion();
  check(fetchStub.calls.length === 1,
    `C-5 FAILED: an unchanged repeat must not be sent, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: moving the cursor without editing text does issue a request only once per position
function testCursorMoveAloneIsRequestedOnce() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);
  completion.requestSuggestion();

  textarea.setSelectionRange(4, 4);
  completion.requestSuggestion();
  check(fetchStub.calls.length === 2,
    `C-5 FAILED: a new cursor position is a new request, got ${fetchStub.calls.length}`);

  completion.requestSuggestion();
  check(fetchStub.calls.length === 2,
    `C-5 FAILED: repeating the same position must not resend, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: the manual Ctrl+Space trigger does not bypass the unchanged check
function testManualTriggerDoesNotBypassSnapshot() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);
  completion.requestSuggestion();

  textarea.dispatchEvent(new KeyboardEvent('keydown', {
    code: 'Space',
    ctrlKey: true,
    bubbles: true,
    cancelable: true
  }));

  check(fetchStub.calls.length === 1,
    `C-5 FAILED: Ctrl+Space must not bypass the unchanged check, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: accepting a suggestion leads into exactly one follow-on request
async function testAcceptSuggestionRequestsTheNextCompletion() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea, { debounceDelay: 5 });

  textarea.value = 'some text';
  textarea.setSelectionRange(9, 9);
  completion.currentSuggestion = { text: ' completed', cursorPosition: 9 };

  completion.acceptSuggestion();
  await wait(40);

  // Accepting inserted text, so the next completion has to follow. The input,
  // keyup and click events accepting sets off must collapse into a single one.
  check(fetchStub.calls.length === 1,
    `C-5 FAILED: accepting must start exactly one follow-on request, got ${fetchStub.calls.length}`);
  const sentText = JSON.parse(fetchStub.calls[0].options.body).text;
  check(sentText === 'some text completed',
    `C-5 FAILED: the follow-on request must carry the accepted text, got ${sentText}`);

  container.remove();
  fetchStub.restore();
}

// Test: a repeat is still suppressed once the request has actually been answered
async function testAnsweredStateStillSuppressesRepeat() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);

  completion.requestSuggestion();
  fetchStub.calls[0].resolve({ suggestion: ' more' });
  await flushPromises();

  completion.requestSuggestion();

  check(fetchStub.calls.length === 1,
    `C-5 FAILED: an answered state must not be re-requested, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: dismissing an answered suggestion with Esc leaves it re-requestable
async function testDismissedSuggestionCanBeRequestedAgain() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);

  completion.requestSuggestion();
  fetchStub.calls[0].resolve({ suggestion: ' more' });
  await flushPromises();

  // The user reads the suggestion and turns it down without editing anything
  completion.onKeyDown({ key: 'Escape', preventDefault: () => {} });

  completion.requestSuggestion();

  check(fetchStub.calls.length === 2,
    `C-5 FAILED: a dismissed suggestion must be requestable again, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: losing focus on an answered suggestion leaves it re-requestable
async function testBlurredSuggestionCanBeRequestedAgain() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);

  completion.requestSuggestion();
  fetchStub.calls[0].resolve({ suggestion: ' more' });
  await flushPromises();

  // onBlur defers its teardown by 100ms
  completion.onBlur();
  await new Promise((resolve) => setTimeout(resolve, 150));

  completion.requestSuggestion();

  check(fetchStub.calls.length === 2,
    `C-5 FAILED: a suggestion dropped on blur must be requestable again, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: clearing must not clear a snapshot that belongs to a newer request
async function testClearKeepsUnrelatedSnapshot() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'first text';
  textarea.setSelectionRange(10, 10);
  completion.requestSuggestion();
  fetchStub.calls[0].resolve({ suggestion: ' more' });
  await flushPromises();

  // The user types on, so the snapshot now describes the newer state
  textarea.value = 'second text';
  textarea.setSelectionRange(11, 11);
  completion.requestSuggestion();

  // Clearing while the cursor sits somewhere else must leave that snapshot be
  textarea.value = 'first text';
  textarea.setSelectionRange(10, 10);
  completion.clearSuggestion();

  check(completion.lastTextSnapshot === 'second text',
    `C-5 FAILED: clearing must not clear an unrelated snapshot, got ${completion.lastTextSnapshot}`);

  container.remove();
  fetchStub.restore();
}

// Test: a response with nothing to show leaves the position re-requestable
async function testEmptyResponseCanBeRequestedAgain() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  // '' is what a completion timeout returns: the controller answers 200 with an
  // empty suggestion by design (ADR-018), and '   ' is a model that produced
  // only whitespace. Neither puts anything on screen.
  for (const emptyAnswer of [ '', '   ' ]) {
    textarea.value = `unchanged text ${emptyAnswer.length}`;
    textarea.setSelectionRange(16, 16);
    const before = fetchStub.calls.length;

    completion.requestSuggestion();
    fetchStub.calls[before].resolve({ suggestion: emptyAnswer });
    await flushPromises();

    check(completion.currentSuggestion === null,
      `C-5 FAILED: ${JSON.stringify(emptyAnswer)} must not be displayed`);

    completion.requestSuggestion();
    check(fetchStub.calls.length === before + 2,
      `C-5 FAILED: ${JSON.stringify(emptyAnswer)} must leave the position requestable, got ${fetchStub.calls.length - before} request(s)`);
  }

  container.remove();
  fetchStub.restore();
}

// Test: a displayed suggestion survives an event that changed nothing
async function testNoOpEventKeepsDisplayedSuggestion() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);
  completion.requestSuggestion();
  fetchStub.calls[0].resolve({ suggestion: ' more' });
  await flushPromises();

  // Releasing Shift, or clicking where the caret already is, reaches
  // onTextChange with the very state the suggestion was computed for
  textarea.dispatchEvent(new KeyboardEvent('keyup', { key: 'Shift', bubbles: true }));
  textarea.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  await wait(20);

  check(completion.currentSuggestion !== null,
    'C-5 FAILED: an event that changed nothing must not clear the displayed suggestion');
  check(fetchStub.calls.length === 1,
    `C-5 FAILED: an event that changed nothing must issue no request, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: taking a displayed suggestion off screen frees its position again
async function testDisablingFreesTheSnapshot() {
  const fetchStub = installFetchStub();
  const { container, textarea, checkbox } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);
  completion.requestSuggestion();
  fetchStub.calls[0].resolve({ suggestion: ' more' });
  await flushPromises();

  // clearSuggestion is reached directly here, without going through Esc or blur
  checkbox.checked = false;
  checkbox.dispatchEvent(new Event('change'));

  check(completion.currentSuggestion === null,
    'C-5 FAILED: disabling must clear the displayed suggestion');

  completion.isEnabled = true;
  completion.requestSuggestion();

  check(fetchStub.calls.length === 2,
    `C-5 FAILED: a suggestion cleared without being used must be requestable again, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: an aborted request leaves the position re-requestable
async function testAbortedRequestCanBeRetried() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);

  completion.requestSuggestion();
  // Losing focus (or Esc, or accepting) aborts through clearSuggestion
  completion.clearSuggestion();
  fetchStub.calls[0].reject(buildAbortError());
  await flushPromises();

  completion.requestSuggestion();

  check(fetchStub.calls.length === 2,
    `C-5 FAILED: an aborted request must be retriable at the same position, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: a failed request leaves the position re-requestable
async function testFailedRequestCanBeRetried() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  const originalConsoleError = console.error;
  console.error = () => {};

  textarea.value = 'unchanged text';
  textarea.setSelectionRange(14, 14);

  completion.requestSuggestion();
  fetchStub.calls[0].reject(new Error('HTTP error! status: 500'));
  await flushPromises();

  completion.requestSuggestion();

  console.error = originalConsoleError;

  check(fetchStub.calls.length === 2,
    `C-5 FAILED: a failed request must be retriable at the same position, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: a late failure must not clear the snapshot a newer request already set
async function testStaleFailureKeepsNewerSnapshot() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'first text';
  textarea.setSelectionRange(10, 10);
  completion.requestSuggestion();

  textarea.value = 'second text';
  textarea.setSelectionRange(11, 11);
  completion.requestSuggestion();

  // The first request only now reports that it was aborted
  fetchStub.calls[0].reject(buildAbortError());
  await flushPromises();

  check(completion.lastTextSnapshot === 'second text',
    `C-5 FAILED: a stale failure must not clear the newer snapshot, got ${completion.lastTextSnapshot}`);

  completion.requestSuggestion();
  check(fetchStub.calls.length === 2,
    `C-5 FAILED: the newer state is still in flight and must not be resent, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: a late failure must not release the controller of the request that replaced it
async function testStaleFailureKeepsNewerController() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  textarea.value = 'first text';
  textarea.setSelectionRange(10, 10);
  completion.requestSuggestion();

  textarea.value = 'second text';
  textarea.setSelectionRange(11, 11);
  completion.requestSuggestion();
  const secondController = completion.abortController;

  // The first request only now reports that it was aborted
  fetchStub.calls[0].reject(buildAbortError());
  await flushPromises();

  check(completion.abortController === secondController,
    'C-1 FAILED: a stale settlement must not release the newer request (invariant I-2)');

  // Which is what keeps the next request aborting the one still in flight —
  // the connection exhaustion of issue #392 comes straight back otherwise
  textarea.value = 'third text';
  textarea.setSelectionRange(10, 10);
  completion.requestSuggestion();

  check(secondController.signal.aborted,
    'C-1 FAILED: the request still in flight must be aborted by the next one');

  container.remove();
  fetchStub.restore();
}

// ---------------------------------------------------------------------------
// C-6: a scheduled completion is cancelled when it becomes ineligible (FR-012)
// ---------------------------------------------------------------------------

// Test: disabling autocompletion cancels the already scheduled completion
async function testScheduledCompletionCancelledWhenDisabled() {
  const fetchStub = installFetchStub();
  const { container, textarea, checkbox } = createTextareaDOM();
  const completion = createCompletion(textarea, { debounceDelay: 30 });

  textarea.value = 'long enough text';
  textarea.setSelectionRange(16, 16);
  completion.scheduleCompletion();

  // The application's own path: unticking the box never reschedules, so the
  // scheduled completion has to be dropped by the teardown itself
  checkbox.checked = false;
  checkbox.dispatchEvent(new Event('change'));

  await wait(80);

  check(fetchStub.calls.length === 0,
    `C-6 FAILED: the scheduled completion must be cancelled, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: falling below the minimum length cancels the already scheduled completion
async function testScheduledCompletionCancelledWhenTooShort() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea, { debounceDelay: 30, minLength: 5 });

  textarea.value = 'long enough text';
  textarea.setSelectionRange(16, 16);
  completion.scheduleCompletion();

  textarea.value = 'ab';
  textarea.setSelectionRange(2, 2);
  completion.scheduleCompletion();

  await wait(80);

  check(fetchStub.calls.length === 0,
    `C-6 FAILED: the scheduled completion must be cancelled, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: losing focus cancels the already scheduled completion
async function testScheduledCompletionCancelledOnBlur() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  // The debounce has to outlast onBlur's own 100ms delay, as it does in the
  // application (500ms for issues, 300ms for wiki pages)
  const completion = createCompletion(textarea, { debounceDelay: 300 });

  textarea.value = 'long enough text';
  textarea.setSelectionRange(16, 16);
  completion.scheduleCompletion();

  completion.onBlur();
  await wait(400);

  check(fetchStub.calls.length === 0,
    `C-6 FAILED: leaving the field must not leave a request behind, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Test: destroy() detaches the listeners it registered
async function testDestroyDetachesListeners() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.destroy();

  textarea.value = 'typed after the instance was destroyed';
  textarea.setSelectionRange(37, 37);
  textarea.dispatchEvent(new Event('input', { bubbles: true }));
  await wait(20);

  check(fetchStub.calls.length === 0,
    `C-6 FAILED: a destroyed instance must not react to input, got ${fetchStub.calls.length} request(s)`);

  container.remove();
  fetchStub.restore();
}

// Test: an eligible schedule still fires
async function testEligibleScheduleStillFires() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea, { debounceDelay: 10 });

  textarea.value = 'long enough text';
  textarea.setSelectionRange(16, 16);
  completion.scheduleCompletion();

  await wait(60);

  check(fetchStub.calls.length === 1,
    `C-6 FAILED: an eligible completion must still be requested, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
}

// Run all tests
async function runAllTests() {
  console.log('=== AiHelperAutoCompletion request lifecycle tests ===\n');

  totalFailures = 0;

  await runTest('C-1: a new request aborts the previous in-flight request', testSecondRequestAbortsFirst);
  await runTest('C-1: abortController is released after the response settles', testControllerClearedAfterResponse);
  await runTest('C-2: clearSuggestion aborts the in-flight request', testClearSuggestionAborts);
  await runTest('C-2: disabling the checkbox aborts the in-flight request', testDisablingCheckboxAborts);
  await runTest('C-2: blur aborts the in-flight request', testBlurAborts);
  await runTest('C-2: accepting a suggestion aborts the in-flight request', testAcceptSuggestionAborts);
  await runTest('C-2: Esc aborts the in-flight request', testEscapeAborts);
  await runTest('C-2: destroy aborts the in-flight request', testDestroyAborts);
  await runTest('C-3: AbortError is handled silently', testAbortErrorIsSilent);
  await runTest('C-3: non-abort errors are still logged', testOtherErrorsStillLogged);
  await runTest('C-4: responses with a stale request id are discarded', testStaleResponseByRequestIdIsDiscarded);
  await runTest('C-4: responses for changed text are discarded', testStaleResponseByTextChangeIsDiscarded);
  await runTest('C-7: instances keep independent AbortControllers', testInstancesDoNotShareAbortController);
  await runTest('C-5: identical text and cursor produce no second request', testNoRequestWhenTextAndCursorUnchanged);
  await runTest('C-5: each text/cursor combination is requested at most once', testCursorMoveAloneIsRequestedOnce);
  await runTest('C-5: the manual trigger respects the unchanged check', testManualTriggerDoesNotBypassSnapshot);
  await runTest('C-5: accepting a suggestion requests the next completion', testAcceptSuggestionRequestsTheNextCompletion);
  await runTest('C-5: an answered text/cursor pair is not requested again', testAnsweredStateStillSuppressesRepeat);
  await runTest('C-5: a dismissed suggestion can be requested again', testDismissedSuggestionCanBeRequestedAgain);
  await runTest('C-5: a suggestion dropped on blur can be requested again', testBlurredSuggestionCanBeRequestedAgain);
  await runTest('C-5: clearing leaves an unrelated snapshot intact', testClearKeepsUnrelatedSnapshot);
  await runTest('C-5: a response with nothing to show can be requested again', testEmptyResponseCanBeRequestedAgain);
  await runTest('C-5: an event that changed nothing keeps the suggestion', testNoOpEventKeepsDisplayedSuggestion);
  await runTest('C-5: a suggestion cleared unused can be requested again', testDisablingFreesTheSnapshot);
  await runTest('C-5: an aborted request can be retried at the same position', testAbortedRequestCanBeRetried);
  await runTest('C-5: a failed request can be retried at the same position', testFailedRequestCanBeRetried);
  await runTest('C-5: a stale failure leaves the newer snapshot intact', testStaleFailureKeepsNewerSnapshot);
  await runTest('C-1: a stale settlement leaves the newer controller in flight', testStaleFailureKeepsNewerController);
  await runTest('C-6: disabling cancels the scheduled completion', testScheduledCompletionCancelledWhenDisabled);
  await runTest('C-6: blur cancels the scheduled completion', testScheduledCompletionCancelledOnBlur);
  await runTest('C-6: a destroyed instance stops reacting to input', testDestroyDetachesListeners);
  await runTest('C-6: dropping below the minimum length cancels the scheduled completion', testScheduledCompletionCancelledWhenTooShort);
  await runTest('C-6: an eligible scheduled completion still fires', testEligibleScheduleStillFires);

  console.log(totalFailures === 0
    ? '\n=== All tests passed ==='
    : `\n=== ${totalFailures} assertion(s) FAILED ===`);

  return totalFailures;
}

// Export for module environments, or run directly
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { runAllTests };
} else if (typeof window !== 'undefined') {
  window.runAutoCompletionTests = runAllTests;
}
