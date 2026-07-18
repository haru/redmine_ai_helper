require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/effort_estimation"

class RedmineAiHelper::EffortEstimationTest < ActiveSupport::TestCase
  context "EffortEstimation" do
    context "#suggest" do
      should "return available: false for an empty array" do
        result = RedmineAiHelper::EffortEstimation.suggest([])

        assert_equal false, result[:available]
      end

      should "return available: false when no similar issue has spent_hours" do
        similar_issues = [
          { id: 1, similarity_score: 90.0, spent_hours: nil },
          { id: 2, similarity_score: 80.0 }
        ]

        result = RedmineAiHelper::EffortEstimation.suggest(similar_issues)

        assert_equal false, result[:available]
      end

      should "return the spent_hours of the single issue when only one has data" do
        similar_issues = [
          { id: 1, similarity_score: 90.0, spent_hours: 4.0 }
        ]

        result = RedmineAiHelper::EffortEstimation.suggest(similar_issues)

        assert_equal true, result[:available]
        assert_equal 4.0, result[:suggested_hours]
        assert_equal 1, result[:based_on_count]
      end

      should "compute the weighted average of spent_hours by similarity_score" do
        similar_issues = [
          { id: 1, similarity_score: 90.0, spent_hours: 6.0 },
          { id: 2, similarity_score: 30.0, spent_hours: 2.0 }
        ]
        # (6.0 * 90.0 + 2.0 * 30.0) / (90.0 + 30.0) = 600.0 / 120.0 = 5.0
        result = RedmineAiHelper::EffortEstimation.suggest(similar_issues)

        assert_equal true, result[:available]
        assert_equal 5.0, result[:suggested_hours]
        assert_equal 2, result[:based_on_count]
      end

      should "round suggested_hours to 1 decimal" do
        similar_issues = [
          { id: 1, similarity_score: 100.0, spent_hours: 1.0 },
          { id: 2, similarity_score: 50.0, spent_hours: 2.0 }
        ]
        # (1.0 * 100.0 + 2.0 * 50.0) / (100.0 + 50.0) = 200.0 / 150.0 = 1.3333...
        result = RedmineAiHelper::EffortEstimation.suggest(similar_issues)

        assert_equal 1.3, result[:suggested_hours]
      end

      should "exclude issues with nil spent_hours from both the average and based_on_count" do
        similar_issues = [
          { id: 1, similarity_score: 90.0, spent_hours: 4.0 },
          { id: 2, similarity_score: 80.0, spent_hours: nil },
          { id: 3, similarity_score: 70.0 }
        ]

        result = RedmineAiHelper::EffortEstimation.suggest(similar_issues)

        assert_equal true, result[:available]
        assert_equal 4.0, result[:suggested_hours]
        assert_equal 1, result[:based_on_count]
      end

      should "exclude issues with zero spent_hours from both the average and based_on_count" do
        similar_issues = [
          { id: 1, similarity_score: 90.0, spent_hours: 4.0 },
          { id: 2, similarity_score: 60.0, spent_hours: 0 }
        ]

        result = RedmineAiHelper::EffortEstimation.suggest(similar_issues)

        assert_equal true, result[:available]
        assert_equal 4.0, result[:suggested_hours]
        assert_equal 1, result[:based_on_count]
      end

      should "return available: false when all issues have zero spent_hours" do
        similar_issues = [
          { id: 1, similarity_score: 90.0, spent_hours: 0 },
          { id: 2, similarity_score: 60.0, spent_hours: 0.0 }
        ]

        result = RedmineAiHelper::EffortEstimation.suggest(similar_issues)

        assert_equal false, result[:available]
      end
    end
  end
end
