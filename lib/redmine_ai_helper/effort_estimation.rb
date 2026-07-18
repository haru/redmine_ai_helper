# frozen_string_literal: true

# Top-level namespace for the Redmine AI Helper plugin.
module RedmineAiHelper
  # Service class for suggesting an issue's effort (spent hours) based on
  # similar issues already found by vector search. Pure computation only:
  # it does not perform any DB query or LLM call itself, it just aggregates
  # the similar issues data it is given.
  class EffortEstimation
    # Computes a suggested number of hours as the weighted average of the
    # spent_hours of the given similar issues, weighted by their
    # similarity_score. Issues without a positive spent_hours value are
    # ignored, matching the default-checked set of the effort checkboxes in
    # the similar issues view so the server-rendered suggestion agrees with
    # the client-side recalculation.
    #
    # @param similar_issues [Array<Hash>] Similar issues data, as returned by
    #   RedmineAiHelper::Llm#find_similar_issues. Each entry is expected to
    #   have :spent_hours and :similarity_score keys.
    # @return [Hash] { available: false } when there is not enough data,
    #   otherwise { available: true, suggested_hours: Float, based_on_count: Integer }
    def self.suggest(similar_issues)
      with_spent_hours = similar_issues.select { |issue| issue[:spent_hours].to_f > 0 }
      return { available: false } if with_spent_hours.empty?

      total_weight = with_spent_hours.sum { |issue| issue[:similarity_score].to_f }
      return { available: false } if total_weight.zero?

      weighted_sum = with_spent_hours.sum { |issue| issue[:spent_hours].to_f * issue[:similarity_score].to_f }

      {
        available: true,
        suggested_hours: (weighted_sum / total_weight).round(1),
        based_on_count: with_spent_hours.size
      }
    end
  end
end
