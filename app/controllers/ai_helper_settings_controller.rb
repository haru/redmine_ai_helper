# frozen_string_literal: true

# AiHelperSetting Controller for managing AI Helper settings
class AiHelperSettingsController < ApplicationController
  layout "admin"

  protect_from_forgery with: :exception

  before_action :require_admin
  before_action :find_setting, except: %i[test_vector_connection test_embedding_connection]
  self.main_menu = false

  include AiHelperSettingsHelper
  include RedmineAiHelper::Logger

  # Placeholder value rendered in token fields when a token is already
  # stored, so the raw value never reaches the HTML source (same approach
  # as AiHelperModelProfilesController::DUMMY_ACCESS_KEY). When this value
  # is submitted, the controller keeps the existing token unchanged.
  DUMMY_TOKEN = "___DUMMY_TOKEN___"

  # Maximum length of the provider error message returned by
  # #test_embedding_connection. The log keeps the full message.
  EMBEDDING_TEST_ERROR_MAX_LENGTH = 500

  # Number of backtrace lines logged when #test_embedding_connection fails
  # with an unexpected error (not a provider, network or response error).
  EMBEDDING_TEST_BACKTRACE_LINES = 10

  # Form fields used by #test_embedding_connection to pick the model profile
  # and embedding model. Any other submitted parameter is ignored.
  EMBEDDING_TEST_FIELDS = %w[model_profile_id use_vector_model_profile vector_model_profile_id embedding_model].freeze

  # Display the settings page
  def index
    @selected_tab = params[:tab].presence
  end

  # Returns the HTML-rendered setup guide for a chat adapter.
  # Used by the help popup dialog in the channels settings tab.
  def help
    channel_type = params[:channel_type]
    valid_types = RedmineAiHelper::ChatChannel::BaseAdapter.adapters.keys
    unless valid_types.include?(channel_type)
      render_404
      return
    end

    doc_path = Rails.root.join("plugins/redmine_ai_helper/docs/#{channel_type}_gateway_setup.md")
    unless File.exist?(doc_path)
      render_404
      return
    end

    markdown = File.read(doc_path, encoding: Encoding::UTF_8)
    html = Redmine::WikiFormatting::CommonMark::Formatter.new(markdown).to_html
    render plain: html, content_type: "text/html"
  end

  # Update the settings. The global setting and every adapter setting are
  # persisted atomically: if any of them is invalid, none is kept, so the
  # page never re-renders with only half of the changes committed.
  def update
    @setting.safe_attributes = params[:ai_helper_setting]
    @chat_adapter_settings = chat_adapter_settings_from_params

    setting_saved = nil
    adapters_saved = nil
    AiHelperSetting.transaction do
      setting_saved = @setting.save
      adapters_saved = @chat_adapter_settings.values.map(&:save).all?
      raise ActiveRecord::Rollback unless setting_saved && adapters_saved
    end

    if setting_saved && adapters_saved
      flash[:notice] = l(:notice_successful_update)
      redirect_to action: :index, tab: params[:tab].presence
    else
      @selected_tab = if adapters_saved
          ai_helper_settings_selected_tab(
            @setting.errors.attribute_names,
            params[:tab].presence
          )
      else
          "channels"
      end
      # find_setting derived this from the persisted flag, before safe_attributes=.
      # Recompute it so the re-rendered vector tab matches the all_projects_scope
      # the general tab is about to show.
      @vector_candidate_projects = @setting.vector_scope_projects.order(:name)
      render action: :index
    end
  end

  # Checks the Qdrant connection with the unsaved values from the form.
  # Does not read or write the stored settings. Responds with JSON
  # `{ success: true }` or `{ success: false, error: message }`.
  def test_vector_connection
    attrs = params[:ai_helper_setting] || {}
    uri = attrs[:vector_search_uri].to_s.strip
    api_key = attrs[:vector_search_api_key].to_s.strip.presence

    unless valid_vector_search_uri?(uri)
      render json: { success: false, error: l("ai_helper.vector_search.messages.invalid_uri") }, status: :unprocessable_content
      return
    end

    RedmineAiHelper::Vector::Qdrant.test_connection(url: uri, api_key: api_key)
    render json: { success: true }
  rescue => e
    ai_helper_logger.error("Qdrant connection test failed: #{e.class}: #{e.message}")
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Checks that the embedding model works with the unsaved values from the
  # form, by embedding a fixed text once with the model profile that vector
  # registration would use. Does not save the settings or touch the vector DB.
  # For providers with a model registry, the profile's chat model may first be
  # looked up in the provider's model list, so a wrong chat model name also
  # fails this test.
  # Responds with JSON `{ success: true, dimension: n }` or
  # `{ success: false, error: message }`.
  def test_embedding_connection
    setting = AiHelperSetting.new
    setting.safe_attributes = params.fetch(:ai_helper_setting, {}).permit(*EMBEDDING_TEST_FIELDS)

    profile, error = embedding_test_profile(setting)
    if error
      render json: { success: false, error: error }, status: :unprocessable_content
      return
    end

    dimension = RedmineAiHelper::LlmProvider.test_embedding(profile: profile, embedding_model: setting.embedding_model)
    render json: { success: true, dimension: dimension }
  # NotImplementedError (unsupported llm_type) is a ScriptError, so list it explicitly.
  rescue StandardError, NotImplementedError => e
    ai_helper_logger.error(embedding_test_log_message(e))
    render json: { success: false, error: embedding_test_error_message(e) }, status: :internal_server_error
  end

  private

  # Resolves the model profile for the embedding connection test, checking
  # that the form selects one before anything is sent to the provider.
  # @param setting [AiHelperSetting] unsaved setting holding the form values
  # @return [Array(AiHelperModelProfile, nil), Array(nil, String)] the profile, or nil and an error message
  def embedding_test_profile(setting)
    if setting.use_vector_model_profile?
      return [ nil, l("ai_helper.vector_search.messages.vector_model_profile_required") ] if setting.vector_model_profile_id.blank?
    else
      return [ nil, l("ai_helper.vector_search.messages.model_profile_required") ] if setting.model_profile_id.blank?
    end

    profile = begin
      setting.vector_llm_model_profile
    rescue ActiveRecord::RecordNotFound
      nil
    end
    return [ nil, l("ai_helper.vector_search.messages.model_profile_not_found") ] unless profile

    [ profile, nil ]
  end

  # Message shown for a failed embedding connection test.
  # @param error [StandardError] the error raised by the test
  # @return [String] the timeout message, or the error message truncated to EMBEDDING_TEST_ERROR_MAX_LENGTH
  def embedding_test_error_message(error)
    if embedding_test_timeout?(error)
      return l("ai_helper.vector_search.messages.embedding_timeout", seconds: RedmineAiHelper::LlmProvider::EMBEDDING_TEST_TIMEOUT)
    end

    error.message.truncate(EMBEDDING_TEST_ERROR_MAX_LENGTH)
  end

  # Log line for a failed embedding connection test. Unexpected errors also get
  # the first EMBEDDING_TEST_BACKTRACE_LINES backtrace lines so their origin can
  # be found; provider, network and response errors are logged on one line.
  # @param error [Exception] the error raised by the test
  # @return [String]
  def embedding_test_log_message(error)
    message = "Embedding connection test failed: #{error.class}: #{error.message}"
    return message if embedding_test_expected_error?(error)

    [ message, *error.backtrace&.first(EMBEDDING_TEST_BACKTRACE_LINES) ].join("\n")
  end

  # Whether the error comes from the provider, the network or the response
  # check, rather than from a bug in our code.
  # @param error [Exception]
  # @return [Boolean]
  def embedding_test_expected_error?(error)
    error.is_a?(RubyLLM::Error) || error.is_a?(Faraday::Error) ||
      error.is_a?(RedmineAiHelper::LlmProvider::UnexpectedEmbeddingResponseError)
  end

  # Whether the error is a read timeout or a connect timeout. faraday-net_http
  # wraps Net::OpenTimeout in Faraday::ConnectionFailed.
  # @param error [StandardError]
  # @return [Boolean]
  def embedding_test_timeout?(error)
    error.is_a?(Faraday::TimeoutError) ||
      (error.is_a?(Faraday::ConnectionFailed) && error.cause.is_a?(Net::OpenTimeout))
  end

  # Whether the given string is an http(s) URL with a host.
  # @param uri [String] The Qdrant URI entered on the form.
  # @return [Boolean]
  def valid_vector_search_uri?(uri)
    parsed = URI.parse(uri)
    parsed.is_a?(URI::HTTP) && parsed.host.present?
  rescue URI::InvalidURIError
    false
  end

  # Always enforce CSRF verification for this controller.
  # Overrides Redmine's ApplicationController which conditionally skips
  # verification for API requests. This controller does not serve API requests.
  def verify_authenticity_token
    unless verified_request?
      handle_unverified_request
    end
  end

  # Always handle unverified requests by returning 422.
  # Overrides Redmine's version which skips handling for API-format requests.
  def handle_unverified_request
    cookies.delete(autologin_cookie_name)
    self.logged_user = nil
    set_localization
    render_error status: 422, message: l(:error_invalid_authenticity_token)
  end

  # Find or create the AI Helper setting and load all settings data
  # (model profiles, projects, channel bindings, and active users).
  def find_setting
    @setting = AiHelperSetting.find_or_create
    @model_profiles = AiHelperModelProfile.order(:name)
    @ai_helper_projects = Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" }).order(:name)
    @vector_candidate_projects = @setting.vector_scope_projects.order(:name)
    @channel_bindings_by_type = AiHelperChannelBinding.includes(:project)
                                                      .order(:channel_type, :channel_id)
                                                      .group_by(&:channel_type)
    @ai_helper_users = User.active.sorted
  end

  # Builds adapter setting records from the channels tab params, keyed by
  # channel_type. Only registered adapters are accepted. Token fields that
  # come back unchanged from the form (DUMMY_TOKEN) are preserved as-is so
  # the stored secret is never round-tripped through the browser.
  # @return [Hash{String => AiHelperChatAdapterSetting}]
  def chat_adapter_settings_from_params
    submitted = params[:chat_adapter_settings] || {}
    RedmineAiHelper::ChatChannel::BaseAdapter.adapters.keys.each_with_object({}) do |channel_type, hash|
      attrs = submitted[channel_type]
      next unless attrs

      setting = AiHelperChatAdapterSetting.for_channel(channel_type)
      preserve_unchanged_tokens!(setting, attrs)
      setting.safe_attributes = attrs
      hash[channel_type] = setting
    end
  end

  # Replaces DUMMY_TOKEN submissions with the value currently stored so the
  # operator does not have to re-enter a secret to keep it.
  def preserve_unchanged_tokens!(setting, attrs)
    %w[app_token bot_token].each do |field|
      next unless attrs[field] == DUMMY_TOKEN

      attrs[field] = setting.send(field)
    end
  end
end
