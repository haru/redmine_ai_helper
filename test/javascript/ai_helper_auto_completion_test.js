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
  const originalFetch = global.fetch;
  const calls = [];

  global.fetch = function (url, options) {
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
    restore: () => { global.fetch = originalFetch; }
  };
}

/**
 * Helper: Wrap global AbortController so that abort() calls can be counted.
 * Each created instance is recorded in the returned `instances` array.
 */
function installAbortControllerSpy() {
  const OriginalAbortController = global.AbortController;
  const instances = [];

  global.AbortController = class SpyAbortController extends OriginalAbortController {
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
    restore: () => { global.AbortController = OriginalAbortController; }
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

  console.assert(firstController != null,
    'C-1 FAILED: abortController should be set after the first request');
  console.assert(fetchStub.calls[0].options.signal === firstController.signal,
    'C-1 FAILED: fetch must receive the controller signal');

  completion.callCompletionAPI('second text', 11, 2);

  console.assert(firstController.abortCallCount === 1,
    `C-1 FAILED: first controller should be aborted once, got ${firstController.abortCallCount}`);
  console.assert(completion.abortController !== firstController,
    'C-1 FAILED: a new AbortController should be created for the second request');
  console.assert(fetchStub.calls[1].options.signal === completion.abortController.signal,
    'C-1 FAILED: second fetch must receive the new controller signal');
  console.assert(abortSpy.instances.length === 2,
    `C-1 FAILED: exactly two controllers expected, got ${abortSpy.instances.length}`);

  container.remove();
  fetchStub.restore();
  abortSpy.restore();
  console.log('C-1 PASSED: a new request aborts the previous in-flight request');
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

  console.assert(completion.abortController === null,
    'C-1 FAILED: abortController should be null once the response has settled (invariant I-2)');

  container.remove();
  fetchStub.restore();
  console.log('C-1 PASSED: abortController is released after the response settles');
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

  console.assert(controller.signal.aborted,
    'C-2 FAILED: clearSuggestion must abort the in-flight request');
  console.assert(completion.abortController === null,
    'C-2 FAILED: clearSuggestion must release the controller');

  container.remove();
  fetchStub.restore();
  console.log('C-2 PASSED: clearSuggestion aborts the in-flight request');
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

  console.assert(controller.signal.aborted,
    'C-2 FAILED: disabling autocompletion must abort the in-flight request');

  container.remove();
  fetchStub.restore();
  console.log('C-2 PASSED: disabling the checkbox aborts the in-flight request');
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

  console.assert(controller.signal.aborted,
    'C-2 FAILED: blur must abort the in-flight request');

  container.remove();
  fetchStub.restore();
  console.log('C-2 PASSED: blur aborts the in-flight request');
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

  console.assert(controller.signal.aborted,
    'C-2 FAILED: accepting a suggestion must abort the in-flight request');

  container.remove();
  fetchStub.restore();
  console.log('C-2 PASSED: accepting a suggestion aborts the in-flight request');
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

  console.assert(controller.signal.aborted,
    'C-2 FAILED: Esc must abort the in-flight request');

  container.remove();
  fetchStub.restore();
  console.log('C-2 PASSED: Esc aborts the in-flight request');
}

// Test: destroy() aborts the in-flight request (page navigation edge case)
function testDestroyAborts() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea);

  completion.callCompletionAPI('some text', 9, 1);
  const controller = completion.abortController;

  completion.destroy();

  console.assert(controller.signal.aborted,
    'C-2 FAILED: destroy must abort the in-flight request');

  container.remove();
  fetchStub.restore();
  console.log('C-2 PASSED: destroy aborts the in-flight request');
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

  console.assert(errorCalls.length === 0,
    `C-3 FAILED: AbortError must not be logged, got ${errorCalls.length} console.error call(s)`);
  console.assert(completion.currentSuggestion === null,
    'C-3 FAILED: AbortError must not produce a suggestion');

  container.remove();
  fetchStub.restore();
  console.log('C-3 PASSED: AbortError is handled silently');
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

  console.assert(errorCalls.length === 1,
    `C-3 FAILED: non-abort errors must still be logged, got ${errorCalls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-3 PASSED: non-abort errors are still logged');
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

  console.assert(completion.currentSuggestion === null,
    'C-4 FAILED: a superseded response must not be displayed');

  container.remove();
  fetchStub.restore();
  console.log('C-4 PASSED: responses with a stale request id are discarded');
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

  console.assert(completion.currentSuggestion === null,
    'C-4 FAILED: a response for outdated text must not be displayed');

  container.remove();
  fetchStub.restore();
  console.log('C-4 PASSED: responses for changed text are discarded');
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

  console.assert(descriptionController !== notesController,
    'C-7 FAILED: instances must not share an AbortController');

  descriptionCompletion.clearSuggestion();

  console.assert(descriptionController.signal.aborted,
    'C-7 FAILED: the description request should be aborted');
  console.assert(notesController.signal.aborted === false,
    'C-7 FAILED: the notes request must not be affected');
  console.assert(notesCompletion.abortController === notesController,
    'C-7 FAILED: the notes controller must remain in flight');

  description.container.remove();
  notes.container.remove();
  fetchStub.restore();
  console.log('C-7 PASSED: instances keep independent AbortControllers');
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
  console.assert(fetchStub.calls.length === 1,
    `C-5 precondition FAILED: the first request should be sent, got ${fetchStub.calls.length}`);

  completion.requestSuggestion();
  console.assert(fetchStub.calls.length === 1,
    `C-5 FAILED: an unchanged repeat must not be sent, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: identical text and cursor produce no second request');
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
  console.assert(fetchStub.calls.length === 2,
    `C-5 FAILED: a new cursor position is a new request, got ${fetchStub.calls.length}`);

  completion.requestSuggestion();
  console.assert(fetchStub.calls.length === 2,
    `C-5 FAILED: repeating the same position must not resend, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: each text/cursor combination is requested at most once');
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

  console.assert(fetchStub.calls.length === 1,
    `C-5 FAILED: Ctrl+Space must not bypass the unchanged check, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: the manual trigger respects the unchanged check');
}

// Test: accepting a suggestion does not itself start a new request
async function testAcceptSuggestionDoesNotTriggerNewRequest() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea, { debounceDelay: 5 });

  textarea.value = 'some text';
  textarea.setSelectionRange(9, 9);
  completion.currentSuggestion = { text: ' completed', cursorPosition: 9 };

  completion.acceptSuggestion();
  await wait(40);

  console.assert(fetchStub.calls.length === 0,
    `C-5 FAILED: accepting a suggestion must not start a request, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: accepting a suggestion starts no new request');
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

  console.assert(fetchStub.calls.length === 1,
    `C-5 FAILED: an answered state must not be re-requested, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: an answered text/cursor pair is not requested again');
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

  console.assert(fetchStub.calls.length === 2,
    `C-5 FAILED: an aborted request must be retriable at the same position, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: an aborted request can be retried at the same position');
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

  console.assert(fetchStub.calls.length === 2,
    `C-5 FAILED: a failed request must be retriable at the same position, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: a failed request can be retried at the same position');
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

  console.assert(completion.lastTextSnapshot === 'second text',
    `C-5 FAILED: a stale failure must not clear the newer snapshot, got ${completion.lastTextSnapshot}`);

  completion.requestSuggestion();
  console.assert(fetchStub.calls.length === 2,
    `C-5 FAILED: the newer state is still in flight and must not be resent, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-5 PASSED: a stale failure leaves the newer snapshot intact');
}

// ---------------------------------------------------------------------------
// C-6: a scheduled completion is cancelled when it becomes ineligible (FR-012)
// ---------------------------------------------------------------------------

// Test: disabling autocompletion cancels the already scheduled completion
async function testScheduledCompletionCancelledWhenDisabled() {
  const fetchStub = installFetchStub();
  const { container, textarea } = createTextareaDOM();
  const completion = createCompletion(textarea, { debounceDelay: 30 });

  textarea.value = 'long enough text';
  textarea.setSelectionRange(16, 16);
  completion.scheduleCompletion();

  completion.isEnabled = false;
  completion.scheduleCompletion();

  await wait(80);

  console.assert(fetchStub.calls.length === 0,
    `C-6 FAILED: the scheduled completion must be cancelled, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-6 PASSED: disabling cancels the scheduled completion');
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

  console.assert(fetchStub.calls.length === 0,
    `C-6 FAILED: the scheduled completion must be cancelled, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-6 PASSED: dropping below the minimum length cancels the scheduled completion');
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

  console.assert(fetchStub.calls.length === 1,
    `C-6 FAILED: an eligible completion must still be requested, got ${fetchStub.calls.length}`);

  container.remove();
  fetchStub.restore();
  console.log('C-6 PASSED: an eligible scheduled completion still fires');
}

// Run all tests
async function runAllTests() {
  console.log('=== AiHelperAutoCompletion request lifecycle tests ===\n');

  await testSecondRequestAbortsFirst();
  await testControllerClearedAfterResponse();
  testClearSuggestionAborts();
  testDisablingCheckboxAborts();
  await testBlurAborts();
  testAcceptSuggestionAborts();
  testEscapeAborts();
  testDestroyAborts();
  await testAbortErrorIsSilent();
  await testOtherErrorsStillLogged();
  await testStaleResponseByRequestIdIsDiscarded();
  await testStaleResponseByTextChangeIsDiscarded();
  testInstancesDoNotShareAbortController();
  testNoRequestWhenTextAndCursorUnchanged();
  testCursorMoveAloneIsRequestedOnce();
  testManualTriggerDoesNotBypassSnapshot();
  await testAcceptSuggestionDoesNotTriggerNewRequest();
  await testAnsweredStateStillSuppressesRepeat();
  await testAbortedRequestCanBeRetried();
  await testFailedRequestCanBeRetried();
  await testStaleFailureKeepsNewerSnapshot();
  await testScheduledCompletionCancelledWhenDisabled();
  await testScheduledCompletionCancelledWhenTooShort();
  await testEligibleScheduleStillFires();

  console.log('\n=== All tests completed ===');
}

// Export for module environments, or run directly
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { runAllTests };
} else if (typeof window !== 'undefined') {
  window.runAutoCompletionTests = runAllTests;
}
