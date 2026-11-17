# frozen_string_literal: true

require_relative "../test_helper"

# Verifies that the conversation ID survives across requests when the session
# store only persists a session whose content changed (GitHub issue #568).
# The default cookie store has no change detection: it writes the whole session
# back whenever the session was loaded, so it cannot reveal the problem.
# The test assumes Redmine's default cookie store is configured, because the
# store is swapped in place of it.
class AiHelperSessionPersistenceTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members,
           :member_roles, :enabled_modules, :trackers

  # Minimal session store that models activerecord-session_store 2.3.0, which
  # skips the write unless its record changed: the value handed out by
  # find_session is remembered, and write_session skips the write when the
  # value written back equals it. Rack copies only the top-level hash when it
  # loads a session, so nested hashes are shared with the remembered value and
  # mutating one in place is not detected as a change.
  class ChangeDetectingStore < ActionDispatch::Session::AbstractSecureStore
    # Request env key holding the value returned by find_session.
    LOADED_KEY = "ai_helper_test.loaded_session"

    class << self
      # Deep copies of the session data keyed by private session ID.
      # @return [Hash{String => Hash}] the stored sessions
      def storage
        @storage ||= {}
      end

      # Remove every stored session.
      # @return [void]
      def reset!
        @storage = {}
      end
    end

    # Load the session, remembering the loaded value for change detection.
    # @param request [ActionDispatch::Request] the current request
    # @param sid [Rack::Session::SessionId, nil] the session ID from the cookie
    # @return [Array(Rack::Session::SessionId, Hash)] the session ID and the session data
    def find_session(request, sid)
      stored = sid && self.class.storage[sid.private_id]
      data = stored ? stored.deep_dup : {}
      sid ||= generate_sid
      # Without this entry write_session finds nil, treats the session as changed and writes it.
      request.env[LOADED_KEY] = data
      [ sid, data ]
    end

    # Persist the session only when it differs from the loaded value.
    # @param request [ActionDispatch::Request] the current request
    # @param sid [Rack::Session::SessionId] the session ID
    # @param session [Hash] the session data to write
    # @param _options [Hash] unused
    # @return [Rack::Session::SessionId] the session ID
    def write_session(request, sid, session, _options)
      return sid if request.env[LOADED_KEY] == session

      self.class.storage[sid.private_id] = session.to_hash.deep_dup
      sid
    end

    # Remove the session, as reset_session does on login.
    # @param _request [ActionDispatch::Request] unused
    # @param sid [Rack::Session::SessionId] the session ID
    # @param options [Hash] session options
    # @return [Rack::Session::SessionId, nil] a new session ID unless dropped
    def delete_session(_request, sid, options)
      self.class.storage.delete(sid.private_id)
      generate_sid unless options[:drop]
    end
  end

  # Build the Rails application with the change detecting session store in
  # place of the cookie store. The built stack bypasses Rails::Application#call,
  # which normally adds Rails.application.env_config (secret key base, cookie
  # settings) to the env, so the wrapper merges it in.
  # @return [#call] the Rack application
  def app
    @app ||= begin
      stack = Rails.application.middleware.dup
      stack.swap ActionDispatch::Session::CookieStore, ChangeDetectingStore, **Rails.application.config.session_options
      built = stack.build(Rails.application.routes)
      lambda do |env|
        env.merge!(Rails.application.env_config)
        built.call(env)
      end
    end
  end

  setup do
    ChangeDetectingStore.reset!
    @project = Project.find(1)
    EnabledModule.find_or_create_by!(project_id: @project.id, name: "ai_helper")
    @answered_conversation_ids = []
    ids = @answered_conversation_ids
    llm = Object.new
    llm.define_singleton_method(:chat) do |conversation, _stream_proc, _option|
      ids << conversation.id
      AiHelperMessage.new(role: "assistant", content: "Answer for conversation #{conversation.id}")
    end
    RedmineAiHelper::Llm.stubs(:new).returns(llm)
    log_user("admin", "admin")
  end

  # The session as persisted by the store for the logged in user.
  # @return [Hash] the stored session data
  def stored_session
    sessions = ChangeDetectingStore.storage.values.select { |data| data["user_id"] }
    assert_equal 1, sessions.size, "exactly one logged in session must be stored"
    sessions.first
  end

  # Open the chat form, as the sidebar does on page load.
  # @return [void]
  def open_chat_form
    get "/projects/#{@project.id}/ai_helper/chat_form"
    assert_response :success
    assert stored_session.key?("ai_helper"), "chat_form must store the ai_helper area so chat starts from a loaded session"
  end

  # Send a user message and let the assistant answer it. The 200 of call_llm is
  # committed before the stream runs, so callers must check the answered
  # conversation IDs to detect a failure.
  # @param content [String] the message text
  # @return [void]
  def send_message(content)
    post "/projects/#{@project.id}/ai_helper/chat", params: { ai_helper_message: { content: content } }
    assert_response :success
    post "/projects/#{@project.id}/ai_helper/call_llm",
         params: { controller_name: "issues", action_name: "show", content_id: 1, additional_info: { key: "value" } }
    assert_response :success
  end

  # Create a conversation holding one user message.
  # @param user [User] the owner
  # @param content [String] the content of the message
  # @return [AiHelperConversation] the created conversation
  def create_conversation(user, content)
    conversation = AiHelperConversation.create!(user: user, title: "Chat with AI")
    conversation.messages << AiHelperMessage.new(role: "user", content: content)
    conversation
  end

  # Make the stored session display the given conversation without going
  # through the code under test.
  # @param conversation [AiHelperConversation] the conversation to display
  # @return [void]
  def display_conversation(conversation)
    stored_session["ai_helper"] = { conversation_id: conversation.id }
  end

  # The roles of the messages of a conversation in creation order.
  # @param conversation [AiHelperConversation] the conversation
  # @return [Array<String>] the roles
  def message_roles(conversation)
    conversation.messages.reload.order(:id).map(&:role)
  end

  context "a new conversation" do
    should "answer the message sent by chat and keep using the same conversation" do
      open_chat_form
      conversations_before = AiHelperConversation.count

      send_message("Hello AI")

      conversation = AiHelperConversation.order(:id).last
      assert_equal conversations_before + 1, AiHelperConversation.count
      assert_equal [ "user", "assistant" ], message_roles(conversation)
      assert_equal [ conversation.id ], @answered_conversation_ids

      send_message("Second question")

      assert_equal conversations_before + 1, AiHelperConversation.count
      assert_equal [ "user", "assistant", "user", "assistant" ], message_roles(conversation)
      assert_equal [ conversation.id, conversation.id ], @answered_conversation_ids

      get "/projects/#{@project.id}/ai_helper/reload"
      assert_response :success
      assert_includes response.body, "Second question"
      assert_includes response.body, "Answer for conversation #{conversation.id}"
    end
  end

  context "a conversation selected from the history" do
    should "receive the following messages instead of the displayed one" do
      admin = User.find(1)
      conversation_a = create_conversation(admin, "Question A")
      conversation_b = create_conversation(admin, "Question B")
      open_chat_form
      display_conversation(conversation_b)
      conversations_before = AiHelperConversation.count
      assert_not_equal conversation_a.id, stored_session["ai_helper"][:conversation_id]

      get "/projects/#{@project.id}/ai_helper/conversation/#{conversation_a.id}"
      assert_response :success
      assert_equal conversation_a.id, stored_session["ai_helper"][:conversation_id]

      send_message("Follow-up for A")

      assert_equal conversations_before, AiHelperConversation.count
      assert_equal [ "user", "user", "assistant" ], message_roles(conversation_a)
      assert_equal [ "user" ], message_roles(conversation_b)
      assert_equal [ conversation_a.id ], @answered_conversation_ids

      get "/projects/#{@project.id}/ai_helper/reload"
      assert_response :success
      assert_includes response.body, "Follow-up for A"
      assert_not_includes response.body, "Question B"
    end
  end
end
