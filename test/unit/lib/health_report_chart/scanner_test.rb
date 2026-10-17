# frozen_string_literal: true

require_relative "../../../test_helper"
require "redmine_ai_helper/health_report_chart/scanner"

class HealthReportChartScannerTest < ActiveSupport::TestCase
  DIRECTIVE_LINE = "{{ai_helper_chart(status, version=12)}}"

  context "Scanner.split" do
    should "return the whole body as a single string when no directive is present" do
      markdown = "Some text\n\nmore text\n"
      parts = RedmineAiHelper::HealthReportChart::Scanner.split(markdown)

      assert_equal [ markdown ], parts
      assert_equal markdown, parts.join
    end

    context "judgment table (contracts/chart-directive.md)" do
      should "a plain directive line becomes a Directive" do
        parts = split(DIRECTIVE_LINE)

        assert_directive_at(parts, 0, type: "status", target_kind: :version, target_value: "12",
                                 source: DIRECTIVE_LINE)
        assert_round_trip(parts, DIRECTIVE_LINE)
      end

      should "up to three leading spaces and trailing spaces are allowed" do
        line = "   {{ai_helper_chart(tracker,period=last_week)}}  "
        parts = split(line)

        assert_directive_at(parts, 0, type: "tracker", target_kind: :period, target_value: "last_week",
                                 source: "{{ai_helper_chart(tracker,period=last_week)}}")
      end

      should "four leading spaces are an indented code block, not a directive" do
        line = "    #{DIRECTIVE_LINE}"
        parts = split(line)

        assert_single_string(parts, line)
      end

      should "an unclosed directive line is a plain string" do
        line = "{{ai_helper_chart(status, version=12)"
        parts = split(line)

        assert_single_string(parts, line)
      end

      should "a directive inside inline code is a plain string" do
        line = "`#{DIRECTIVE_LINE}`"
        parts = split(line)

        assert_single_string(parts, line)
      end

      should "a directive inside a list item is a plain string" do
        line = "- #{DIRECTIVE_LINE}"
        parts = split(line)

        assert_single_string(parts, line)
      end

      should "a directive inside a block quote is a plain string" do
        line = "> #{DIRECTIVE_LINE}"
        parts = split(line)

        assert_single_string(parts, line)
      end

      should "a directive inside a backtick fence is a plain string" do
        markdown = "```\n#{DIRECTIVE_LINE}\n```"
        parts = split(markdown)

        assert_single_string(parts, markdown)
      end

      should "a tilde fence is not closed by a backtick fence line" do
        markdown = "~~~~\n{{ai_helper_chart(status, version=12)}}\n```\n{{ai_helper_chart(tracker, period=last_week)}}\n~~~~"
        parts = split(markdown)

        assert_single_string(parts, markdown)
      end

      should "a directive without a target is a Directive with invalid arguments" do
        parts = split("{{ai_helper_chart(status)}}")

        directive = assert_directive_at(parts, 0, type: "status", target_kind: nil, target_value: nil,
                                        source: "{{ai_helper_chart(status)}}")
        assert_not directive.valid_arguments?
        assert_round_trip(parts, "{{ai_helper_chart(status)}}")
      end

      should "a directive with a malformed version is a Directive with invalid arguments" do
        parts = split("{{ai_helper_chart(status, version=abc)}}")

        directive = assert_directive_at(parts, 0, type: "status", target_kind: nil, target_value: nil,
                                        source: "{{ai_helper_chart(status, version=abc)}}")
        assert_not directive.valid_arguments?
      end

      should "an unknown chart type is still a well-formed Directive" do
        parts = split("{{ai_helper_chart(burndown, version=12)}}")

        assert_directive_at(parts, 0, type: "burndown", target_kind: :version, target_value: "12",
                            source: "{{ai_helper_chart(burndown, version=12)}}")
      end

      should "text and a directive without blank lines split into three parts" do
        markdown = "text\n#{DIRECTIVE_LINE}\ntext"
        parts = split(markdown)

        assert_equal 3, parts.length
        assert_equal "text\n", parts[0]
        assert_directive_at(parts, 1, type: "status", target_kind: :version, target_value: "12",
                            source: DIRECTIVE_LINE)
        assert_equal "\ntext", parts[2]
        assert_round_trip(parts, markdown)
      end

      should "-like: a directive line after an unclosed fence stays a plain string" do
        markdown = "```\n#{DIRECTIVE_LINE}"
        parts = split(markdown)

        assert_single_string(parts, markdown)
      end
    end

    context "fenced code blocks" do
      should "treat lines as inside a fence that opens with an info string" do
        markdown = "```ruby\n#{DIRECTIVE_LINE}\n```"
        parts = split(markdown)

        assert_single_string(parts, markdown)
      end

      should "treat lines as inside an unclosed fence until the end of the body" do
        markdown = "~~~\n#{DIRECTIVE_LINE}\nmore"
        parts = split(markdown)

        assert_single_string(parts, markdown)
      end

      should "not close a fence with a shorter closing line" do
        markdown = "````\n#{DIRECTIVE_LINE}\n```\nmore\n````"
        parts = split(markdown)

        assert_single_string(parts, markdown)
      end

      should "allow up to three leading spaces on a fence line" do
        markdown = " ```\n#{DIRECTIVE_LINE}\n ```"
        parts = split(markdown)

        assert_single_string(parts, markdown)
      end

      should "keep the fence rule per character: tilde opens, tilde closes" do
        markdown = "~~~\ntext\n~~~\n#{DIRECTIVE_LINE}"
        parts = split(markdown)

        assert_equal 2, parts.length
        assert_equal "~~~\ntext\n~~~\n", parts[0]
        assert_kind_of RedmineAiHelper::HealthReportChart::Directive, parts[1]
        assert_round_trip(parts, markdown)
      end
    end

    context "multiple directives" do
      should "keep directives and strings in the original order" do
        markdown = "a\n#{DIRECTIVE_LINE}\nb\n{{ai_helper_chart(status)}}\nc"
        parts = split(markdown)

        assert_equal 5, parts.length
        assert_equal "a\n", parts[0]
        assert_kind_of RedmineAiHelper::HealthReportChart::Directive, parts[1]
        assert_equal "\nb\n", parts[2]
        assert_kind_of RedmineAiHelper::HealthReportChart::Directive, parts[3]
        assert_equal "\nc", parts[4]
        assert_round_trip(parts, markdown)
      end

      should "return a single newline chunk when a directive line is followed by a blank line" do
        markdown = "#{DIRECTIVE_LINE}\n\nafter"
        parts = split(markdown)

        assert_equal [ RedmineAiHelper::HealthReportChart::Directive, String ], parts.map(&:class)
        assert_equal "\n\nafter", parts[1]
        assert_round_trip(parts, markdown)
      end
    end
  end

  context "Directive" do
    should "accept a well-formed directive" do
      directive = build_directive(target_kind: :version, target_value: "12")

      assert_predicate directive, :valid_arguments?
    end

    should "not be valid_arguments? when target_kind is nil" do
      directive = build_directive(target_kind: nil, target_value: nil)

      assert_not_predicate directive, :valid_arguments?
    end

    should "expose the given attributes" do
      directive = build_directive(target_kind: :period, target_value: "last_week")

      assert_equal "status", directive.type
      assert_equal :period, directive.target_kind
      assert_equal "last_week", directive.target_value
      assert_equal DIRECTIVE_LINE, directive.source
    end

    should "raise ArgumentError when type is not a String" do
      assert_raises(ArgumentError) do
        build_directive(type: :status)
      end
    end

    should "raise ArgumentError when type is nil" do
      assert_raises(ArgumentError) do
        build_directive(type: nil)
      end
    end

    should "raise ArgumentError when source is not a String" do
      assert_raises(ArgumentError) do
        build_directive(source: 12)
      end
    end

    should "raise ArgumentError when target_kind is not nil, :version or :period" do
      assert_raises(ArgumentError) do
        build_directive(target_kind: :milestone, target_value: "12")
      end
    end

    should "raise ArgumentError when target_kind is nil but target_value is present" do
      assert_raises(ArgumentError) do
        build_directive(target_kind: nil, target_value: "12")
      end
    end
  end

  private

  def split(markdown)
    RedmineAiHelper::HealthReportChart::Scanner.split(markdown)
  end

  def build_directive(type: "status", target_kind: nil, target_value: nil, source: DIRECTIVE_LINE)
    RedmineAiHelper::HealthReportChart::Directive.new(
      type: type,
      target_kind: target_kind,
      target_value: target_value,
      source: source
    )
  end

  # Asserts that `parts[index]` is a Directive with the given attributes and
  # that the scanned region was actually found (the part list is non-empty).
  def assert_directive_at(parts, index, attributes)
    assert_not_empty parts, "the scanner should have produced at least one part"
    directive = parts[index]
    assert_kind_of RedmineAiHelper::HealthReportChart::Directive, directive,
                   "expected a Directive at index #{index}, got: #{parts.map(&:class).inspect}"
    assert_equal attributes[:type], directive.type
    if attributes[:target_kind].nil?
      assert_nil directive.target_kind
    else
      assert_equal attributes[:target_kind], directive.target_kind
    end
    if attributes[:target_value].nil?
      assert_nil directive.target_value
    else
      assert_equal attributes[:target_value], directive.target_value
    end
    assert_equal attributes[:source], directive.source
    directive
  end

  # Asserts that the whole body stayed one plain string (no directive found).
  def assert_single_string(parts, markdown)
    assert_equal [ markdown ], parts
    assert parts.all?(String), "expected only strings, got: #{parts.map(&:class).inspect}"
  end

  def assert_round_trip(parts, markdown)
    assert_equal markdown, parts.map { |part| part.is_a?(String) ? part : part.source }.join
  end
end
