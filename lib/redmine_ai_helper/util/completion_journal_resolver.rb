# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Validates the +journal_id+ of a suggest_completion request and resolves
    # the journal being edited. The checks mirror Redmine's own rules for
    # showing and opening a comment edit form (Journal.visible and
    # Journal#editable_by?), so a comment the user could not open cannot feed
    # its content or its author's position into a completion.
    module CompletionJournalResolver
      # Resolve and validate the journal being edited.
      #
      # @param data [Hash] The parsed JSON request body
      # @param context_type [String] The requested context type
      # @param issue [Issue, nil] The issue the completion belongs to
      # @param user [User] The user requesting the completion
      # @return [Array(Journal, nil, Symbol, nil)] The journal (nil for a new
      #   comment), the i18n error message (nil when valid), and the HTTP
      #   status symbol for that error (nil when valid)
      def self.resolve(data, context_type, issue, user)
        journal_id = data["journal_id"]
        return [ nil, nil, nil ] if journal_id.nil?

        return [ nil, I18n.t("ai_helper.completion_errors.invalid_journal_id"), :bad_request ] unless journal_id.is_a?(Integer)
        return [ nil, I18n.t("ai_helper.completion_errors.journal_requires_note"), :bad_request ] unless context_type == "note"

        journal = Journal.visible.find_by(id: journal_id)
        unless journal && journal.journalized == issue
          return [ nil, I18n.t("ai_helper.completion_errors.journal_not_in_issue"), :bad_request ]
        end

        unless journal.editable_by?(user)
          return [ nil, I18n.t("ai_helper.completion_errors.journal_not_editable"), :forbidden ]
        end

        [ journal, nil, nil ]
      end
    end
  end
end
