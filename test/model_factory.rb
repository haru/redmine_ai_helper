require "factory_bot"

FactoryBot::SyntaxRunner.class_eval do
  include ActionDispatch::TestProcess
  include ActiveSupport::Testing::FileFixtures
end

FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "Project #{n}" }
    sequence(:identifier) { |n| "project-#{n}" }
    description { "Project description" }
    homepage { "http://example.com" }
    is_public { true }
  end

  factory :ai_helper_chat_adapter_setting do
    channel_type { "slack" }
    enabled { false }
  end

  factory :ai_helper_channel_binding do
    channel_type { "slack" }
    sequence(:channel_id) { |n| "C#{n.to_s.rjust(7, '0')}" }
    channel_name { "#general" }
    project
  end

  factory :ai_helper_conversation do
    sequence(:title) { |n| "Conversation #{n}" }
    user { User.find(1) }
  end

  factory :ai_helper_channel_conversation do
    channel_type { "slack" }
    sequence(:thread_key) { |n| "C0000001:1700000000.#{n.to_s.rjust(6, '0')}" }
    association :conversation, factory: :ai_helper_conversation
  end
end
