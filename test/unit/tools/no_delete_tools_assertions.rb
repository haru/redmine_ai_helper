# frozen_string_literal: true

# Shared assertions that pin the "no destructive tool" rule of the project
# management tools (spec 084, FR-002, SC-004). Included by the tests of
# ProjectWriteTools, MemberTools, and CategoryTools.
module NoDeleteToolsAssertions
  DESTRUCTIVE_NAME = /delete|destroy|archive|purge|close/i
  # Every spelling of a record-removing or status-changing call.
  DESTRUCTIVE_CALL = /\.(?:destroy!?|destroy_all|destroy_by|delete|delete_all|delete_by|archive|close|reopen)\b|update_column\s*\(?\s*:status|\.status\s*=/

  # Source lines of the tool file without comments and blank lines.
  # @param tool_class [Class] The tool provider class.
  # @return [Array<String>] The code lines.
  def code_lines_of(tool_class)
    path = Pathname.new(RedmineAiHelper::Tools.const_source_location(tool_class.name.demodulize).first)
    lines = path.read.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    # Guard against a silently empty search region (CRF-033)
    assert_operator lines.grep(/define_function/).size, :>, 0, "no define_function found in #{path}"
    lines
  end

  # Assert that no generated tool name suggests a destructive operation.
  # @param tool_class [Class] The tool provider class.
  # @return [void]
  def assert_no_destructive_tool_names(tool_class)
    names = tool_class.tool_classes.map { |tc| tc.new.name }
    assert_operator names.size, :>, 0
    offenders = names.select { |name| name.split("--").last.match?(DESTRUCTIVE_NAME) }
    assert_empty offenders, "destructive-looking tool names: #{offenders.inspect}"
  end

  # Assert that the tool file contains destructive calls only on the allowed lines.
  # @param tool_class [Class] The tool provider class.
  # @param allowed [Array<String>] Exact stripped lines that may remain.
  # @return [void]
  def assert_destructive_calls_only(tool_class, allowed: [])
    found = code_lines_of(tool_class).grep(DESTRUCTIVE_CALL)
    assert_equal allowed.sort, found.sort
  end
end
