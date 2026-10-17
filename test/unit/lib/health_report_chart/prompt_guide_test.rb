# frozen_string_literal: true

require_relative "../../../test_helper"
require "redmine_ai_helper/health_report_chart/resolver"
require "redmine_ai_helper/health_report_chart/prompt_guide"

class HealthReportChartPromptGuideTest < ActiveSupport::TestCase
  PromptGuide = RedmineAiHelper::HealthReportChart::PromptGuide
  Resolver = RedmineAiHelper::HealthReportChart::Resolver

  METRICS = [
    { version_id: 12, version_name: "1.0.0", metrics: {} },
    { period_name: "Last 1 Month", metrics: {} },
    { period_name: "Repository Activity (Last 1 Month)", metrics: {} }
  ].to_json

  context "PromptGuide.build" do
    should "describe the syntax and the placement rules" do
      guide = PromptGuide.build(Resolver.new(METRICS))

      assert_includes guide, "{{ai_helper_chart(<type>, version=<id>)}}"
      assert_includes guide, "{{ai_helper_chart(<type>, period=<key>)}}"
      assert_includes guide, "single line"
      assert_includes guide, "blank lines"
      assert_includes guide, "tables, lists, or code blocks"
      assert_includes guide, "do not copy the numbers"
    end

    should "ask for a one or two sentence reading of each chart" do
      guide = PromptGuide.build(Resolver.new(METRICS))

      assert_includes guide, "one or two sentences"
      assert_includes guide, "before or after each chart"
      assert_includes guide, "skew, a bottleneck, or the progress made"
      assert_includes guide, "only the figures needed for the reading"
    end

    should "not tell the model which form a chart is drawn in" do
      guide = PromptGuide.build(Resolver.new(METRICS))

      %w[doughnut pie stacked tile bar\ chart].each { |word| assert_not_includes guide.downcase, word }
    end

    should "list every chart type with its key and English title" do
      guide = PromptGuide.build(Resolver.new(METRICS))

      assert_includes guide, "- status: Issues by Status"
      assert_includes guide, "- tracker: Issues by Tracker"
      assert_includes guide, "- priority: Issues by Priority"
      assert_includes guide, "- assignee: Issues by Assignee"
      assert_includes guide, "- open_closed: Open vs Closed Issues"
      assert_includes guide, "- progress: Progress Distribution"
    end

    should "list the versions and periods of the metrics but not repository periods" do
      guide = PromptGuide.build(Resolver.new(METRICS))

      assert_includes guide, "- version=12 (1.0.0)"
      assert_includes guide, "- period=last_month (Last 1 Month)"
      assert_not_includes guide, "Repository"
    end

    should "stay English whatever the user's locale is" do
      guide = I18n.with_locale(:ja) { PromptGuide.build(Resolver.new(METRICS)) }

      assert_includes guide, "- status: Issues by Status"
      assert_includes guide, "(Last 1 Month)"
    end

    should "tell the model not to write directives when there are no targets" do
      [ nil, "{not json", [].to_json ].each do |metrics|
        guide = PromptGuide.build(Resolver.new(metrics))

        assert_includes guide, "Do not write any chart directives"
        assert_not_includes guide, "{{ai_helper_chart("
      end
    end

    should "raise ArgumentError for anything but a Resolver" do
      assert_raises(ArgumentError) { PromptGuide.build(nil) }
      assert_raises(ArgumentError) { PromptGuide.build(METRICS) }
    end
  end
end
