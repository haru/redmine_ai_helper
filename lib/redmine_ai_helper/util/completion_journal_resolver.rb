# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Validates the +journal_id+ of a suggest_completion request and resolves
    # the journal being edited. The checks mirror Redmine's own rules for
    # showing and opening a comment edit form (Journal.visible and
    # Journal#editable_by?), so a comment the user could not open cannot feed
    # its content or its author's position into a completion.
    module CompletionJournalResolver
      include RedmineAiHelper::Logger

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

        return reject(:invalid_journal_id, :bad_request, data, issue, user) unless journal_id.is_a?(Integer)
        return reject(:journal_requires_note, :bad_request, data, issue, user) unless context_type == "note"

        journal = Journal.visible(user).find_by(id: journal_id)
        unless journal && journal.journalized == issue
          return reject(:journal_not_in_issue, :bad_request, data, issue, user)
        end

        return reject(:journal_not_editable, :forbidden, data, issue, user) unless journal.editable_by?(user)

        [ journal, nil, nil ]
      end

      # Log a rejected request (a probe for someone else's comment or a client
      # sending a wrong id would otherwise leave no trace) and build the error
      # result.
      #
      # @param key [Symbol] The ai_helper.completion_errors i18n key
      # @param status [Symbol] The HTTP status symbol
      # @param data [Hash] The parsed JSON request body
      # @param issue [Issue, nil] The issue the completion belongs to
      # @param user [User] The user requesting the completion
      # @return [Array(nil, String, Symbol)] The error result tuple
      def self.reject(key, status, data, issue, user)
        message = I18n.t("ai_helper.completion_errors.#{key}")
        ai_helper_logger.warn "Rejected completion journal request: journal_id=#{data['journal_id'].inspect}, " \
                              "issue_id=#{issue&.id}, user=#{user.id}, error=#{key}"
        [ nil, message, status ]
      end
      private_class_method :reject
    end
  end
end
