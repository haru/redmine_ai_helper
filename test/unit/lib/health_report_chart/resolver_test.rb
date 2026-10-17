# frozen_string_literal: true

require_relative "../../../test_helper"
require "redmine_ai_helper/health_report_chart/resolver"

class HealthReportChartResolverTest < ActiveSupport::TestCase
  METRICS = [
    {
      version_id: 12, version_name: "1.0.0",
      metrics: {
        issue_statistics: {
          by_status: { "New" => 3, "Resolved" => 2, "Closed" => 5 },
          by_tracker: { "Bug" => 2, "Feature" => 2, "Support" => 1 },
          by_priority: { "Low" => 1, "Normal" => 4, "High" => 5 },
          by_assigned_to: { "Alice" => 6, "Bob" => 2, "Carol" => 2 },
          open_issues: 10, closed_issues: 5
        },
        progress_metrics: {
          completion_distribution: { not_started: 3, in_progress: 2, completed: 5 }
        }
      }
    },
    {
      period_name: "Last 1 Week", period_description: "week", start_date: "2026-10-10", end_date: "2026-10-17",
      metrics: {
        issue_statistics: {
          by_status: { "New" => 1 }, by_tracker: { "Bug" => 1 }, by_priority: { "Normal" => 1 },
          by_assigned_to: { "Alice" => 1 }, open_issues: 1, closed_issues: 0
        },
        progress_metrics: { completion_distribution: { not_started: 1, in_progress: 0, completed: 0 } }
      }
    },
    {
      period_name: "Repository Activity (Last 1 Week)", period_description: "repo", start_date: "2026-10-10", end_date: "2026-10-17",
      metrics: { repository_metrics: { commits: 12 } }
    }
  ].to_json

  context "unavailable reasons" do
    should "report metrics_unavailable when the metrics are nil" do
      assert_equal :metrics_unavailable, resolve({ type: "status", target_kind: :version, target_value: "12" }, nil).reason
    end

    should "report metrics_unavailable when the JSON is broken, catching only JSON::ParserError" do
      assert_equal :metrics_unavailable, resolve({ type: "status", target_kind: :version, target_value: "12" }, "{not json").reason
    end

    should "report metrics_unavailable when the JSON is not an array" do
      assert_equal :metrics_unavailable, resolve({ type: "status", target_kind: :version, target_value: "12" }, { "a" => 1 }.to_json).reason
    end

    should "report invalid_arguments before unknown_type and metrics_unavailable" do
      resolver = RedmineAiHelper::HealthReportChart::Resolver.new(nil)
      directive = RedmineAiHelper::HealthReportChart::Directive.new(
        type: "burndown", target_kind: nil, target_value: nil, source: "s"
      )

      assert_equal :invalid_arguments, resolver.resolve(directive).reason
    end

    should "report unknown_type before metrics_unavailable" do
      assert_equal :unknown_type, resolve({ type: "burndown", target_kind: :version, target_value: "12" }, nil).reason
    end

    should "report metrics_unavailable before unknown_target" do
      assert_equal :metrics_unavailable, resolve({ type: "status", target_kind: :version, target_value: "999" }, nil).reason
    end

    should "report unknown_target for a version the metrics do not have" do
      assert_equal :unknown_target, resolve({ type: "status", target_kind: :version, target_value: "999" }).reason
    end

    should "report data_missing when the target exists but the type's values do not" do
      metrics = [ { version_id: 12, version_name: "1.0.0", metrics: { issue_statistics: {} } } ].to_json

      assert_equal :data_missing, resolve({ type: "status", target_kind: :version, target_value: "12" }, metrics).reason
    end

    should "report data_missing when the element has no metrics at all" do
      metrics = [ { version_id: 12, version_name: "1.0.0" } ].to_json

      assert_equal :data_missing, resolve({ type: "status", target_kind: :version, target_value: "12" }, metrics).reason
    end

    should "embed the type in the unknown_type message" do
      assert_equal 'Cannot draw the chart: Unknown chart type "burndown"',
                   resolve({ type: "burndown", target_kind: :version, target_value: "12" }).message
    end

    should "embed the target part of the source in the unknown_target message" do
      assert_equal "Cannot draw the chart: The target \"version=999\" is not included in this report's metrics data",
                   resolve({ type: "status", target_kind: :version, target_value: "999",
                             source: "{{ai_helper_chart(status, version=999)}}" }).message
    end

    should "prefix every message with the localized unavailable prefix" do
      assert resolve({ type: "status", target_kind: :version, target_value: "999" }).message.start_with?("Cannot draw the chart: ")
    end
  end

  context "target resolution (R-003)" do
    should "resolve a version by version_id and use the version name in the title" do
      chart = resolve({ type: "status", target_kind: :version, target_value: "12" })

      assert_instance_of RedmineAiHelper::HealthReportChart::Chart, chart
      assert_equal "Issues by Status - 1.0.0", chart.title
    end

    should "resolve each period key from its stored period_name" do
      { "last_week" => "Last 1 Week", "last_month" => "Last 1 Month",
        "all_time" => "All Time Analysis", "recent" => "Recent Activity" }.each do |key, name|
        metrics = [ { period_name: name, metrics: metrics_element } ].to_json
        chart = resolve({ type: "status", target_kind: :period, target_value: key }, metrics)

        assert_equal "Issues by Status - #{name}", chart.title
      end
    end

    should "not resolve repository periods" do
      metrics = [ { period_name: "Repository Activity (Last 1 Week)", metrics: metrics_element } ].to_json

      assert_equal :unknown_target,
                   resolve({ type: "status", target_kind: :period, target_value: "last_week" }, metrics).reason
    end
  end

  context "items (R-005)" do
    should "order variable items by count desc, then name asc, with formatted labels" do
      chart = resolve({ type: "status", target_kind: :version, target_value: "12" })

      assert_equal [ "Closed (5)", "New (3)", "Resolved (2)" ], chart.items.map(&:label)
      assert_equal [ 5, 3, 2 ], chart.items.map(&:value)
    end

    should "break count ties by name ascending" do
      chart = resolve({ type: "tracker", target_kind: :version, target_value: "12" })

      assert_equal [ "Bug (2)", "Feature (2)", "Support (1)" ], chart.items.map(&:label)
    end

    should "assign palette colors in order" do
      palette = RedmineAiHelper::HealthReportChart::Palette
      chart = resolve({ type: "status", target_kind: :version, target_value: "12" })

      assert_equal palette::COLORS[0], chart.items[0].rgb
      assert_equal palette::COLORS[1], chart.items[1].rgb
      assert_equal palette::COLORS[2], chart.items[2].rgb
    end

    should "group the 7th and following items into others when there are 8 or more" do
      metrics = [ { version_id: 12, version_name: "1.0.0",
                    metrics: { issue_statistics: { by_status: {
                      "a" => 10, "b" => 9, "c" => 8, "d" => 7, "e" => 6, "f" => 5, "g" => 4, "h" => 3
                    } } } } ].to_json
      chart = resolve({ type: "status", target_kind: :version, target_value: "12" }, metrics)

      assert_equal 7, chart.items.length
      assert_equal [ "a (10)", "b (9)", "c (8)", "d (7)", "e (6)", "f (5)", "Others (7)" ], chart.items.map(&:label)
      assert_equal [ 10, 9, 8, 7, 6, 5, 7 ], chart.items.map(&:value)
    end

    should "not group when there are exactly 7 items" do
      metrics = [ { version_id: 12, version_name: "1.0.0",
                    metrics: { issue_statistics: { by_status: {
                      "a" => 7, "b" => 6, "c" => 5, "d" => 4, "e" => 3, "f" => 2, "g" => 1
                    } } } } ].to_json
      chart = resolve({ type: "status", target_kind: :version, target_value: "12" }, metrics)

      assert_equal 7, chart.items.length
      assert_equal [ "a (7)", "b (6)", "c (5)", "d (4)", "e (3)", "f (2)", "g (1)" ], chart.items.map(&:label)
    end

    should "use the bar form for assignee and the doughnut form for the ratio types" do
      assert_equal :bar, resolve({ type: "assignee", target_kind: :version, target_value: "12" }).form
      assert_equal :doughnut, resolve({ type: "open_closed", target_kind: :version, target_value: "12" }).form
    end

    should "keep the fixed open/closed order and never group" do
      chart = resolve({ type: "open_closed", target_kind: :version, target_value: "12" })

      assert_equal [ "open (10)", "closed (5)" ], chart.items.map(&:label)
    end

    should "keep the fixed progress order" do
      chart = resolve({ type: "progress", target_kind: :version, target_value: "12" })

      assert_equal [ "Not started (3)", "In progress (2)", "Completed (5)" ], chart.items.map(&:label)
    end

    should "be no_data? when the values sum to 0" do
      metrics = [ { version_id: 12, version_name: "1.0.0",
                    metrics: { issue_statistics: { by_status: { "New" => 0 } } } } ].to_json
      chart = resolve({ type: "status", target_kind: :version, target_value: "12" }, metrics)

      assert chart.no_data?
    end

    should "report data_missing for open_closed when a count is missing" do
      metrics = [ { version_id: 12, version_name: "1.0.0",
                    metrics: { issue_statistics: { open_issues: 1 } } } ].to_json

      assert_equal :data_missing, resolve({ type: "open_closed", target_kind: :version, target_value: "12" }, metrics).reason
    end

    should "report data_missing for progress when a part is missing" do
      metrics = [ { version_id: 12, version_name: "1.0.0",
                    metrics: { progress_metrics: { completion_distribution: { not_started: 1 } } } } ].to_json

      assert_equal :data_missing, resolve({ type: "progress", target_kind: :version, target_value: "12" }, metrics).reason
    end
  end

  context "Resolver.comparison" do
    should "always resolve to the comparison reason" do
      resolver = RedmineAiHelper::HealthReportChart::Resolver.comparison

      assert_equal :comparison,
                   resolver.resolve(build_directive(type: "status", target_kind: :version, target_value: "12")).reason
      assert_equal :comparison,
                   resolver.resolve(build_directive(type: "burndown", target_kind: nil, target_value: nil)).reason
    end
  end

  context "#targets" do
    should "list versions and mapped periods, not repository periods" do
      targets = RedmineAiHelper::HealthReportChart::Resolver.new(METRICS).targets

      assert_equal({ "version=12" => "1.0.0", "period=last_week" => "Last 1 Week" },
                   targets.to_h { |target| [ target.identifier, target.display_name ] })
    end

    should "be empty without metrics" do
      assert_empty RedmineAiHelper::HealthReportChart::Resolver.new(nil).targets
    end
  end

  private

  def resolve(args, metrics_json = METRICS)
    resolver = RedmineAiHelper::HealthReportChart::Resolver.new(metrics_json)
    resolver.resolve(build_directive(**args))
  end

  def build_directive(type:, target_kind:, target_value:, source: "{{ai_helper_chart(#{type})}}")
    RedmineAiHelper::HealthReportChart::Directive.new(
      type: type, target_kind: target_kind, target_value: target_value, source: source
    )
  end

  # The metrics of one stored element, reused by the period-name tests.
  def metrics_element
    {
      issue_statistics: {
        by_status: { "New" => 1 }, by_tracker: { "Bug" => 1 }, by_priority: { "Normal" => 1 },
        by_assigned_to: { "Alice" => 1 }, open_issues: 1, closed_issues: 0
      },
      progress_metrics: { completion_distribution: { not_started: 1, in_progress: 0, completed: 0 } }
    }
  end
end
