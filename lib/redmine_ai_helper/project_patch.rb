# frozen_string_literal: true

module RedmineAiHelper
  # Patch for Project model to add AI Helper associations
  module ProjectPatch
    # Hook to extend Project model
    # @param base [Class] The Project class
    def self.included(base)
      base.class_eval do
        has_many :ai_helper_channel_bindings, class_name: "AiHelperChannelBinding", dependent: :destroy
      end
    end
  end
end

unless Project.included_modules.include?(RedmineAiHelper::ProjectPatch)
  Project.include RedmineAiHelper::ProjectPatch
end
