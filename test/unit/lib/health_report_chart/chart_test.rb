# frozen_string_literal: true

require_relative "../../../test_helper"
require "redmine_ai_helper/health_report_chart/palette"
require "redmine_ai_helper/health_report_chart/chart"

class HealthReportChartChartTest < ActiveSupport::TestCase
  RED = [ 255, 99, 132 ].freeze

  context "Palette" do
    should "define the 6 colors of Redmine's issue report charts" do
      assert_equal [
        [ 255, 99, 132 ], [ 54, 162, 235 ], [ 255, 206, 86 ],
        [ 75, 192, 192 ], [ 153, 102, 255 ], [ 255, 159, 64 ]
      ], RedmineAiHelper::HealthReportChart::Palette::COLORS
    end

    should "use a fill alpha of 0.2" do
      assert_equal 0.2, RedmineAiHelper::HealthReportChart::Palette::FILL_ALPHA
    end

    should "wrap around to the first color from the 7th item on" do
      palette = RedmineAiHelper::HealthReportChart::Palette

      assert_equal palette::COLORS[0], palette.color_at(0)
      assert_equal palette::COLORS[5], palette.color_at(5)
      assert_equal palette::COLORS[0], palette.color_at(6)
      assert_equal palette::COLORS[1], palette.color_at(7)
    end
  end

  context "Palette immutability" do
    should "freeze every color triple so a returned rgb cannot repaint the palette" do
      RedmineAiHelper::HealthReportChart::Palette::COLORS.each { |rgb| assert_predicate rgb, :frozen? }
    end
  end

  context "Item" do
    should "build the fill and border colors from its rgb value" do
      item = RedmineAiHelper::HealthReportChart::Item.new(label: "New (3)", value: 3, rgb: RED)

      assert_equal "New (3)", item.label
      assert_equal 3, item.value
      assert_equal RED, item.rgb
      assert_equal "rgba(255, 99, 132, 0.2)", item.fill_color
      assert_equal "rgb(255, 99, 132)", item.border_color
    end

    should "raise ArgumentError when the value is negative" do
      assert_raises(ArgumentError) do
        RedmineAiHelper::HealthReportChart::Item.new(label: "New", value: -1, rgb: RED)
      end
    end

    should "raise ArgumentError when the value is not an Integer" do
      assert_raises(ArgumentError) do
        RedmineAiHelper::HealthReportChart::Item.new(label: "New", value: "3", rgb: RED)
      end
    end

    should "raise ArgumentError when the label is not a String" do
      assert_raises(ArgumentError) do
        RedmineAiHelper::HealthReportChart::Item.new(label: 3, value: 3, rgb: RED)
      end
    end

    should "raise ArgumentError when an rgb component is outside 0..255" do
      [ [ 256, 0, 0 ], [ 0, -1, 0 ] ].each do |rgb|
        assert_raises(ArgumentError) do
          RedmineAiHelper::HealthReportChart::Item.new(label: "New", value: 3, rgb: rgb)
        end
      end
    end

    should "keep a frozen copy of rgb so the palette cannot be changed through the item" do
      palette_color = RedmineAiHelper::HealthReportChart::Palette.color_at(0)
      item = RedmineAiHelper::HealthReportChart::Item.new(label: "New", value: 3, rgb: palette_color)

      assert_predicate item.rgb, :frozen?
      assert_raises(FrozenError) { item.rgb[0] = 0 }
      assert_equal [ 255, 99, 132 ], RedmineAiHelper::HealthReportChart::Palette.color_at(0)
    end

    should "raise ArgumentError when rgb is not three integers" do
      assert_raises(ArgumentError) do
        RedmineAiHelper::HealthReportChart::Item.new(label: "New", value: 3, rgb: [ 255, 99 ])
      end
    end
  end

  context "Chart" do
    should "accept a valid chart" do
      chart = RedmineAiHelper::HealthReportChart::Chart.new(title: "Issues by Status - 1.0", form: :doughnut, items: [ build_item ])

      assert_equal "Issues by Status - 1.0", chart.title
      assert_equal :doughnut, chart.form
      assert_equal 1, chart.items.length
      assert_not chart.no_data?
    end

    should "raise ArgumentError when the title is empty, nil or not a String" do
      [ "", nil, 12 ].each do |title|
        error = assert_raises(ArgumentError) do
          RedmineAiHelper::HealthReportChart::Chart.new(title: title, form: :doughnut, items: [])
        end
        assert_match(/title/, error.message)
      end
    end

    should "raise ArgumentError when the form is not :doughnut or :bar" do
      [ :pie, "doughnut", nil ].each do |form|
        assert_raises(ArgumentError) do
          RedmineAiHelper::HealthReportChart::Chart.new(title: "t", form: form, items: [])
        end
      end
    end

    should "raise ArgumentError when there are more than 7 items" do
      assert_raises(ArgumentError) do
        RedmineAiHelper::HealthReportChart::Chart.new(title: "t", form: :bar, items: Array.new(8) { build_item })
      end
    end

    should "raise ArgumentError when an item is not an Item" do
      assert_raises(ArgumentError) do
        RedmineAiHelper::HealthReportChart::Chart.new(title: "t", form: :bar, items: [ "New (1)" ])
      end
    end

    should "freeze its items so they cannot exceed the limit afterwards" do
      chart = RedmineAiHelper::HealthReportChart::Chart.new(title: "t", form: :bar, items: [ build_item ])

      assert_raises(FrozenError) { chart.items << build_item }
    end

    should "share the item limit with the resolver" do
      assert_equal 7, RedmineAiHelper::HealthReportChart::Chart::MAX_ITEMS
    end

    should "be no_data? when there are no items" do
      chart = RedmineAiHelper::HealthReportChart::Chart.new(title: "t", form: :doughnut, items: [])

      assert chart.no_data?
    end

    should "be no_data? when every value is 0" do
      chart = RedmineAiHelper::HealthReportChart::Chart.new(title: "t", form: :doughnut, items: [ build_item(0), build_item(0) ])

      assert chart.no_data?
    end

    should "not be no_data? when any value is positive" do
      chart = RedmineAiHelper::HealthReportChart::Chart.new(title: "t", form: :doughnut, items: [ build_item(0), build_item(2) ])

      assert_not chart.no_data?
    end
  end

  context "ChartType" do
    should "define the six FR-003 types with their chart forms" do
      types = RedmineAiHelper::HealthReportChart::ChartType

      assert_equal %w[assignee open_closed priority progress status tracker], types.keys.sort
      assert_equal :bar, types["assignee"][:form]
      assert_equal :doughnut, types["status"][:form]
      assert_equal :doughnut, types["tracker"][:form]
      assert_equal :doughnut, types["priority"][:form]
      assert_equal :doughnut, types["open_closed"][:form]
      assert_equal :doughnut, types["progress"][:form]
    end

    should "freeze each type definition" do
      RedmineAiHelper::HealthReportChart::ChartType.each_value { |definition| assert_predicate definition, :frozen? }
    end

    should "give every type a locale title key and a variable/fixed item mode" do
      RedmineAiHelper::HealthReportChart::ChartType.each do |key, definition|
        assert_match(/\Aai_helper\.health_report_chart\.types\.#{key}\z/, definition[:title_key])
        assert %i[variable fixed].include?(definition[:item_mode])
      end
    end
  end

  context "Unavailable" do
    should "hold a reason and a localized message" do
      unavailable = RedmineAiHelper::HealthReportChart::Unavailable.new(reason: :unknown_type, message: "msg")

      assert_equal :unknown_type, unavailable.reason
      assert_equal "msg", unavailable.message
    end

    should "accept every documented reason" do
      %i[comparison invalid_arguments unknown_type metrics_unavailable unknown_target data_missing].each do |reason|
        assert_equal reason, RedmineAiHelper::HealthReportChart::Unavailable.new(reason: reason, message: "m").reason
      end
    end

    should "raise ArgumentError for an undocumented reason" do
      [ :typo, "unknown_type", nil ].each do |reason|
        assert_raises(ArgumentError) { RedmineAiHelper::HealthReportChart::Unavailable.new(reason: reason, message: "m") }
      end
    end

    should "raise ArgumentError when the message is empty or not a String" do
      [ "", nil, :msg ].each do |message|
        assert_raises(ArgumentError) do
          RedmineAiHelper::HealthReportChart::Unavailable.new(reason: :unknown_type, message: message)
        end
      end
    end
  end

  private

  def build_item(value = 1)
    RedmineAiHelper::HealthReportChart::Item.new(label: "New (#{value})", value: value, rgb: RED)
  end
end
