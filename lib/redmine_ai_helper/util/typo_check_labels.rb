# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Builds the label Hash consumed by the typo checker overlay from the
    # +ai_helper.typo_check.+ i18n keys. Shared by the issue, wiki and journal
    # edit form typo check UIs so their texts stay identical.
    module TypoCheckLabels
      # Returns the typo check labels for the current locale.
      #
      # @return [Hash<Symbol, String>] the labels used by the typo checker
      def self.labels
        {
          suggestionsTitle: I18n.t("ai_helper.typo_check.suggestions_title"),
          noSuggestions: I18n.t("ai_helper.typo_check.no_suggestions"),
          checkButton: I18n.t("ai_helper.typo_check.check_button"),
          checking: I18n.t("ai_helper.typo_check.checking"),
          acceptSuggestion: I18n.t("ai_helper.typo_check.accept_suggestion"),
          dismissSuggestion: I18n.t("ai_helper.typo_check.dismiss_suggestion"),
          acceptAll: I18n.t("ai_helper.typo_check.accept_all"),
          dismissAll: I18n.t("ai_helper.typo_check.dismiss_all"),
          errorOccurred: I18n.t("ai_helper.typo_check.error_occurred"),
          correctionTooltip: I18n.t("ai_helper.typo_check.correction_tooltip"),
          applyFailed: I18n.t("ai_helper.typo_check.apply_failed")
        }
      end
    end
  end
end
