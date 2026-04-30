# frozen_string_literal: true

module RedmineAiHelper
  module Mcp
    # Stateless per-request authentication strategy using Redmine API keys.
    #
    # Each HTTP request is independently authenticated via the
    # +X-Redmine-API-Key+ header. No session state is persisted between requests.
    class SessionStrategy
      class << self
        # Authenticates an incoming request by extracting and validating the
        # +X-Redmine-API-Key+ header against active Redmine users.
        #
        # @param request [ActionDispatch::Request] the incoming HTTP request
        # @return [User, nil] the authenticated active user, or nil on failure
        def authenticate(request)
          api_key = request.headers["X-Redmine-API-Key"]
          return nil if api_key.blank?

          user = User.find_by_api_key(api_key)
          return nil unless user&.active?

          user
        end
      end
    end

    # @deprecated Use {SessionStrategy} directly.
    StatelessAuthStrategy = SessionStrategy
  end
end
