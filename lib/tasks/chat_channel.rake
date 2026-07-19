# frozen_string_literal: true

namespace :redmine do
  namespace :plugins do
    namespace :ai_helper do
      namespace :chat_channel do
        desc "Start the chat channel gateway (resident process for Slack etc.)"
        task gateway: :environment do
          RedmineAiHelper::ChatChannel::Gateway.new.run
        rescue RedmineAiHelper::ChatChannel::Gateway::ConfigurationError => e
          # Configuration/credential errors must not be retried (ADR-006).
          # The message has already been logged by the gateway; exit 0 so
          # systemd's Restart=on-failure does not loop into the same failure.
          warn "chat_channel gateway: #{e.message}"
          exit 0
        end
      end
    end
  end
end
