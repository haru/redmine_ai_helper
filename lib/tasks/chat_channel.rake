# frozen_string_literal: true

namespace :redmine do
  namespace :plugins do
    namespace :ai_helper do
      namespace :chat_channel do
        desc "Start the chat channel gateway (resident process for Slack etc.)"
        task gateway: :environment do
          RedmineAiHelper::ChatChannel::Gateway.new.run
        end
      end
    end
  end
end
