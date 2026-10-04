# frozen_string_literal: true

module RedmineAiHelper
  # Patch for User model to add AI Helper associations
  module UserPatch
    # Hook to extend User model
    # @param base [Class] The User class
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        has_many :ai_helper_conversations, class_name: "AiHelperConversation", dependent: :destroy
        before_destroy :reassign_edited_health_reports_to_anonymous, prepend: true
      end
    end

    # Keep the "edited" status of health reports when their last editor is
    # deleted by attributing the edits to the anonymous user.
    # @return [void]
    def reassign_edited_health_reports_to_anonymous
      AiHelperHealthReport.where(last_edited_by_id: id).update_all(last_edited_by_id: User.anonymous.id) # rubocop:disable Rails/SkipsModelValidations
    end

    # Class methods for User model
    module ClassMethods
    end
  end
end

unless User.included_modules.include?(RedmineAiHelper::UserPatch)
  User.include RedmineAiHelper::UserPatch
end
