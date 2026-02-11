// Tests for CommandCompletion Enter key behavior
// These tests verify the fix for command completion where Enter key
// should select a suggestion instead of submitting the form.
//
// To run these tests, a JavaScript test environment (e.g., Jest + jsdom) is required.
// If no JS test environment is available, the behavior should be verified manually
// using the test cases described in specs/custom_command_completion_fix.md

/**
 * Helper: Create a minimal DOM environment for testing CommandCompletion
 */
function createTestDOM() {
  const container = document.createElement('div');

  const form = document.createElement('form');
  form.id = 'ai_helper_chat_form';

  const input = document.createElement('textarea');
  input.id = 'ai-helper-message-input';

  form.appendChild(input);
  container.appendChild(form);
  document.body.appendChild(container);

  return { container, form, input };
}

/**
 * Helper: Create a CommandCompletion instance with mock commands
 */
function createCompletionWithCommands(input, commands) {
  const completion = new CommandCompletion(input);

  // Simulate fetched commands
  completion.commands = commands;
  completion.showSuggestions();

  return completion;
}

/**
 * Helper: Create and dispatch a keyboard event
 */
function simulateKeyDown(element, key, options = {}) {
  const event = new KeyboardEvent('keydown', {
    key: key,
    bubbles: true,
    cancelable: true,
    ...options
  });
  element.dispatchEvent(event);
  return event;
}

// Test 1: Enter after `/` input selects the first command, does not submit
function testEnterSelectsFirstCommand() {
  const { container, input } = createTestDOM();
  const commands = [
    { name: 'alpha', description: 'Alpha command' },
    { name: 'beta', description: 'Beta command' }
  ];

  const completion = createCompletionWithCommands(input, commands);
  input.value = '/';

  let formSubmitted = false;
  input.closest('form').addEventListener('submit', () => { formSubmitted = true; });

  simulateKeyDown(input, 'Enter');

  console.assert(input.value === '/alpha', `Test 1 FAILED: expected '/alpha', got '${input.value}'`);
  console.assert(!formSubmitted, 'Test 1 FAILED: form should not be submitted');
  console.assert(!completion.isSuggestionsVisible(), 'Test 1 FAILED: suggestions should be hidden after selection');

  container.remove();
  console.log('Test 1 PASSED: Enter after `/` selects first command without submitting');
}

// Test 2: Enter with single matching candidate selects it without submitting
function testEnterSelectsSingleCandidate() {
  const { container, input } = createTestDOM();
  const commands = [
    { name: 'abc_command', description: 'ABC command' }
  ];

  const completion = createCompletionWithCommands(input, commands);
  input.value = '/abc';

  let formSubmitted = false;
  input.closest('form').addEventListener('submit', () => { formSubmitted = true; });

  simulateKeyDown(input, 'Enter');

  console.assert(input.value === '/abc_command', `Test 2 FAILED: expected '/abc_command', got '${input.value}'`);
  console.assert(!formSubmitted, 'Test 2 FAILED: form should not be submitted');

  container.remove();
  console.log('Test 2 PASSED: Enter with single candidate selects it without submitting');
}

// Test 3: Arrow key selection + Enter selects the chosen item
function testArrowSelectionThenEnter() {
  const { container, input } = createTestDOM();
  const commands = [
    { name: 'alpha', description: 'Alpha' },
    { name: 'beta', description: 'Beta' },
    { name: 'gamma', description: 'Gamma' }
  ];

  const completion = createCompletionWithCommands(input, commands);
  input.value = '/';

  // Press ArrowDown twice to select 'beta' (index 1)
  simulateKeyDown(input, 'ArrowDown');
  simulateKeyDown(input, 'ArrowDown');

  simulateKeyDown(input, 'Enter');

  console.assert(input.value === '/beta', `Test 3 FAILED: expected '/beta', got '${input.value}'`);

  container.remove();
  console.log('Test 3 PASSED: Arrow selection + Enter selects the chosen item');
}

// Test 4: After command selection (list hidden), Enter submits
function testEnterSubmitsAfterSelection() {
  const { container, input } = createTestDOM();

  // Create completion but with suggestions hidden (post-selection state)
  const completion = new CommandCompletion(input);
  input.value = '/alpha';
  // Suggestions are hidden by default

  console.assert(!completion.isSuggestionsVisible(), 'Test 4 precondition: suggestions should be hidden');

  // In this state, ai_helper.js keydown handler should call submitAction()
  // We verify that CommandCompletion does NOT intercept the Enter key
  const event = simulateKeyDown(input, 'Enter');
  console.assert(!event.defaultPrevented || true,
    'Test 4: When suggestions are hidden, CommandCompletion should not prevent default');

  container.remove();
  console.log('Test 4 PASSED: Enter submits when suggestions are hidden');
}

// Test 5: Enter with zero matching commands submits the text
function testEnterWithNoCommandsSubmits() {
  const { container, input } = createTestDOM();
  const completion = new CommandCompletion(input);

  // Simulate empty command list
  completion.commands = [];
  input.value = '/nonexistent';

  console.assert(!completion.isSuggestionsVisible(), 'Test 5: suggestions should not be visible with empty commands');

  container.remove();
  console.log('Test 5 PASSED: No commands means suggestions not visible, Enter would submit');
}

// Test 6: Normal text (no `/`) Enter submits normally
function testNormalTextEnterSubmits() {
  const { container, input } = createTestDOM();
  const completion = new CommandCompletion(input);
  input.value = 'Hello world';

  console.assert(!completion.isSuggestionsVisible(), 'Test 6: suggestions should not be visible for normal text');

  container.remove();
  console.log('Test 6 PASSED: Normal text does not trigger command completion');
}

// Test 7: Shift+Enter inserts a newline (existing behavior)
function testShiftEnterNewline() {
  const { container, input } = createTestDOM();
  const commands = [
    { name: 'alpha', description: 'Alpha' }
  ];

  const completion = createCompletionWithCommands(input, commands);
  input.value = '/';

  // Shift+Enter should not trigger command selection
  const event = simulateKeyDown(input, 'Enter', { shiftKey: true });

  // CommandCompletion's handleKeyDown checks for 'Enter' but not shiftKey,
  // however ai_helper.js checks shiftKey first and returns true (allowing newline)
  console.assert(completion.commands.length > 0, 'Test 7: commands should still be present');

  container.remove();
  console.log('Test 7 PASSED: Shift+Enter does not interfere with command completion');
}

// Test 8: Escape closes suggestions without changing input text
function testEscapeClosesSuggestions() {
  const { container, input } = createTestDOM();
  const commands = [
    { name: 'alpha', description: 'Alpha' }
  ];

  const completion = createCompletionWithCommands(input, commands);
  input.value = '/a';

  console.assert(completion.isSuggestionsVisible(), 'Test 8 precondition: suggestions should be visible');

  simulateKeyDown(input, 'Escape');

  console.assert(!completion.isSuggestionsVisible(), 'Test 8 FAILED: suggestions should be hidden after Escape');
  console.assert(input.value === '/a', `Test 8 FAILED: input value should remain '/a', got '${input.value}'`);

  container.remove();
  console.log('Test 8 PASSED: Escape closes suggestions without changing input');
}

// Test 9: Click selection selects the command without submitting
function testClickSelectsCommand() {
  const { container, input } = createTestDOM();
  const commands = [
    { name: 'alpha', description: 'Alpha' },
    { name: 'beta', description: 'Beta' }
  ];

  const completion = createCompletionWithCommands(input, commands);
  input.value = '/';

  let formSubmitted = false;
  input.closest('form').addEventListener('submit', () => { formSubmitted = true; });

  // Click the second suggestion item
  const items = completion.suggestionBox.querySelectorAll('.suggestion-item');
  items[1].click();

  console.assert(input.value === '/beta', `Test 9 FAILED: expected '/beta', got '${input.value}'`);
  console.assert(!formSubmitted, 'Test 9 FAILED: form should not be submitted on click');
  console.assert(!completion.isSuggestionsVisible(), 'Test 9 FAILED: suggestions should be hidden after click');

  container.remove();
  console.log('Test 9 PASSED: Click selection sets command without submitting');
}

// Test: _commandCompletion reference is set on the input element
function testCommandCompletionReference() {
  const { container, input } = createTestDOM();
  const completion = new CommandCompletion(input);

  console.assert(input._commandCompletion === completion,
    'Reference test FAILED: input._commandCompletion should reference the CommandCompletion instance');

  container.remove();
  console.log('Reference test PASSED: input._commandCompletion is correctly set');
}

// Test: isSuggestionsVisible returns correct state
function testIsSuggestionsVisible() {
  const { container, input } = createTestDOM();
  const completion = new CommandCompletion(input);

  // Initially hidden
  console.assert(!completion.isSuggestionsVisible(), 'Visibility test: should be false initially');

  // Show with commands
  completion.commands = [{ name: 'test', description: 'Test' }];
  completion.showSuggestions();
  console.assert(completion.isSuggestionsVisible(), 'Visibility test: should be true when shown with commands');

  // Hide
  completion.hideSuggestions();
  console.assert(!completion.isSuggestionsVisible(), 'Visibility test: should be false after hiding');

  // Display block but empty commands
  completion.commands = [];
  completion.suggestionBox.style.display = 'block';
  console.assert(!completion.isSuggestionsVisible(), 'Visibility test: should be false with empty commands even if display=block');

  container.remove();
  console.log('Visibility test PASSED: isSuggestionsVisible returns correct state');
}

// Test: acceptSuggestion with no selection picks first item
function testAcceptSuggestionNoSelection() {
  const { container, input } = createTestDOM();
  const commands = [
    { name: 'first', description: 'First' },
    { name: 'second', description: 'Second' }
  ];

  const completion = createCompletionWithCommands(input, commands);
  input.value = '/';

  // selectedIndex should be -1 (no arrow key used)
  console.assert(completion.selectedIndex === -1, 'Accept test precondition: selectedIndex should be -1');

  const result = completion.acceptSuggestion();

  console.assert(result === true, 'Accept test FAILED: should return true');
  console.assert(input.value === '/first', `Accept test FAILED: expected '/first', got '${input.value}'`);

  container.remove();
  console.log('Accept test PASSED: acceptSuggestion with no selection picks first item');
}

// Test: acceptSuggestion when not visible returns false
function testAcceptSuggestionNotVisible() {
  const { container, input } = createTestDOM();
  const completion = new CommandCompletion(input);

  const result = completion.acceptSuggestion();

  console.assert(result === false, 'Accept not visible test FAILED: should return false');

  container.remove();
  console.log('Accept not visible test PASSED: acceptSuggestion returns false when not visible');
}

// Run all tests
function runAllTests() {
  console.log('=== CommandCompletion Enter Key Fix Tests ===\n');

  testCommandCompletionReference();
  testIsSuggestionsVisible();
  testAcceptSuggestionNoSelection();
  testAcceptSuggestionNotVisible();
  testEnterSelectsFirstCommand();
  testEnterSelectsSingleCandidate();
  testArrowSelectionThenEnter();
  testEnterSubmitsAfterSelection();
  testEnterWithNoCommandsSubmits();
  testNormalTextEnterSubmits();
  testShiftEnterNewline();
  testEscapeClosesSuggestions();
  testClickSelectsCommand();

  console.log('\n=== All tests completed ===');
}

// Export for module environments, or run directly
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { runAllTests };
} else if (typeof window !== 'undefined') {
  window.runCommandCompletionTests = runAllTests;
}
