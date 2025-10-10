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
      end
    end

    # Class methods for User model
    module ClassMethods
    end
  end
end

unless User.included_modules.include?(RedmineAiHelper::UserPatch)
  User.send(:include, RedmineAiHelper::UserPatch)
end