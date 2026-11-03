# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/typo_check_labels"

class RedmineAiHelper::Util::TypoCheckLabelsTest < ActiveSupport::TestCase
  context "TypoCheckLabels.labels" do
    expected_keys = %i[
      suggestionsTitle
      noSuggestions
      checkButton
      checking
      acceptSuggestion
      dismissSuggestion
      acceptAll
      dismissAll
      errorOccurred
      correctionTooltip
      applyFailed
    ]

    should "return the 11 typo check labels for the :en locale" do
      I18n.with_locale(:en) do
        labels = RedmineAiHelper::Util::TypoCheckLabels.labels
        assert_equal expected_keys.sort, labels.keys.sort
        assert_equal I18n.t("ai_helper.typo_check.suggestions_title"), labels[:suggestionsTitle]
        assert_equal I18n.t("ai_helper.typo_check.no_suggestions"), labels[:noSuggestions]
        assert_equal I18n.t("ai_helper.typo_check.check_button"), labels[:checkButton]
        assert_equal I18n.t("ai_helper.typo_check.checking"), labels[:checking]
        assert_equal I18n.t("ai_helper.typo_check.accept_suggestion"), labels[:acceptSuggestion]
        assert_equal I18n.t("ai_helper.typo_check.dismiss_suggestion"), labels[:dismissSuggestion]
        assert_equal I18n.t("ai_helper.typo_check.accept_all"), labels[:acceptAll]
        assert_equal I18n.t("ai_helper.typo_check.dismiss_all"), labels[:dismissAll]
        assert_equal I18n.t("ai_helper.typo_check.error_occurred"), labels[:errorOccurred]
        assert_equal I18n.t("ai_helper.typo_check.correction_tooltip"), labels[:correctionTooltip]
        assert_equal I18n.t("ai_helper.typo_check.apply_failed"), labels[:applyFailed]
      end
    end

    should "return the 11 typo check labels for the :ja locale" do
      I18n.with_locale(:ja) do
        labels = RedmineAiHelper::Util::TypoCheckLabels.labels
        assert_equal expected_keys.sort, labels.keys.sort
        assert_equal I18n.t("ai_helper.typo_check.suggestions_title"), labels[:suggestionsTitle]
        assert_equal I18n.t("ai_helper.typo_check.no_suggestions"), labels[:noSuggestions]
        assert_equal I18n.t("ai_helper.typo_check.check_button"), labels[:checkButton]
        assert_equal I18n.t("ai_helper.typo_check.checking"), labels[:checking]
        assert_equal I18n.t("ai_helper.typo_check.accept_suggestion"), labels[:acceptSuggestion]
        assert_equal I18n.t("ai_helper.typo_check.dismiss_suggestion"), labels[:dismissSuggestion]
        assert_equal I18n.t("ai_helper.typo_check.accept_all"), labels[:acceptAll]
        assert_equal I18n.t("ai_helper.typo_check.dismiss_all"), labels[:dismissAll]
        assert_equal I18n.t("ai_helper.typo_check.error_occurred"), labels[:errorOccurred]
        assert_equal I18n.t("ai_helper.typo_check.correction_tooltip"), labels[:correctionTooltip]
        assert_equal I18n.t("ai_helper.typo_check.apply_failed"), labels[:applyFailed]
      end
    end

    should "differ between the :en and :ja locales" do
      en = I18n.with_locale(:en) { RedmineAiHelper::Util::TypoCheckLabels.labels }
      ja = I18n.with_locale(:ja) { RedmineAiHelper::Util::TypoCheckLabels.labels }
      assert_not_equal en, ja
    end
  end
end
