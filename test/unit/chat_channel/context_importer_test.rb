# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelContextImporterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  ContextImporter = RedmineAiHelper::ChatChannel::ContextImporter
  HistoryMessage = RedmineAiHelper::ChatChannel::HistoryMessage
  IncomingMessage = RedmineAiHelper::ChatChannel::IncomingMessage

  # Adapter that supports history retrieval and records how it was called.
  class HistoryAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_reader :calls
    attr_accessor :thread_history, :channel_history

    class << self
      def channel_type
        "importer_chat"
      end
    end

    def initialize
      super
      @calls = []
      @thread_history = []
      @channel_history = []
    end

    def start; end

    def stop; end

    def send_message(channel_id:, thread_key:, text:); end

    def supports_history?
      true
    end

    def fetch_thread_history(channel_id:, thread_key:, after: nil)
      @calls << { source: :thread, channel_id: channel_id, thread_key: thread_key, after: after }
      @thread_history
    end

    def fetch_channel_history(channel_id:, before:, since:, limit:)
      @calls << { source: :channel, channel_id: channel_id, before: before, since: since, limit: limit }
      @channel_history
    end
  end

  # Adapter without history support (the default from BaseAdapter).
  class NoHistoryAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    class << self
      def channel_type
        "importer_no_history"
      end
    end

    def start; end

    def stop; end

    def send_message(channel_id:, thread_key:, text:); end
  end

  setup do
    @adapter = HistoryAdapter.new
    @channel_conversation = create(:ai_helper_channel_conversation,
                                   channel_type: "importer_chat", thread_key: "C1:100.000001")
    @conversation = @channel_conversation.conversation
  end

  def incoming(in_thread: true, message_ts: "100.000900", channel_id: "C1", thread_key: "C1:100.000001")
    IncomingMessage.new(
      channel_type: "importer_chat", channel_id: channel_id, thread_key: thread_key,
      message_ts: message_ts, text: "@bot what about this?", in_thread: in_thread
    )
  end

  def history(*pairs)
    pairs.map { |speaker, text| HistoryMessage.new(speaker: speaker, text: text) }
  end

  context "adapters without history support" do
    should "return 0 without retrieving any history" do
      importer = ContextImporter.new(NoHistoryAdapter.new)

      assert_equal 0, importer.import(conversation: @conversation, message: incoming)
      assert_equal 0, @conversation.reload.messages.count
      assert_nil @channel_conversation.reload.last_imported_message_key
    end
  end

  context "storing imported messages" do
    should "append each retrieved message as a context message with the speaker prefix" do
      @adapter.thread_history = history([ "Yamada", "it crashes on save" ], [ "Suzuki", "stack trace attached" ])

      imported = ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming)

      assert_equal 2, imported
      assert_equal [
        [ "context", "Yamada: it crashes on save" ],
        [ "context", "Suzuki: stack trace attached" ]
      ], @conversation.reload.messages.order(:id).pluck(:role, :content)
    end

    should "advance the import cursor to the message_ts of the current mention" do
      @adapter.thread_history = history([ "Yamada", "hello" ])

      ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming(message_ts: "100.000900"))

      assert_equal "100.000900", @channel_conversation.reload.last_imported_message_key
    end

    should "advance the import cursor even when nothing was retrieved" do
      @adapter.thread_history = []

      imported = ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming(message_ts: "100.000901"))

      assert_equal 0, imported
      assert_equal "100.000901", @channel_conversation.reload.last_imported_message_key
    end

    should "store the messages and the cursor in one transaction" do
      @adapter.thread_history = history([ "Yamada", "hello" ])
      AiHelperChannelConversation.any_instance.stubs(:update!).raises(ActiveRecord::StatementInvalid, "boom")

      assert_raises(ActiveRecord::StatementInvalid) do
        ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming)
      end

      assert_equal 0, @conversation.reload.messages.count
      assert_nil @channel_conversation.reload.last_imported_message_key
    end
  end

  context "thread mode" do
    should "retrieve the thread history for a mention posted inside a thread" do
      ContextImporter.new(@adapter).import(
        conversation: @conversation, message: incoming(in_thread: true, channel_id: "C1", thread_key: "C1:100.000001")
      )

      assert_equal 1, @adapter.calls.size
      call = @adapter.calls.first
      assert_equal :thread, call[:source]
      assert_equal "C1", call[:channel_id]
      assert_equal "C1:100.000001", call[:thread_key]
    end

    should "pass no cursor on the first import of a thread" do
      ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming)

      assert_nil @adapter.calls.first[:after]
    end

    should "pass the stored cursor on a later import of the same thread" do
      @channel_conversation.update!(last_imported_message_key: "100.000500")

      ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming)

      assert_equal "100.000500", @adapter.calls.first[:after]
    end

    should "advance the cursor with every import so nothing is imported twice" do
      importer = ContextImporter.new(@adapter)
      @adapter.thread_history = history([ "Yamada", "first" ])
      importer.import(conversation: @conversation, message: incoming(message_ts: "100.000901"))
      @adapter.thread_history = history([ "Suzuki", "second" ])
      importer.import(conversation: @conversation, message: incoming(message_ts: "100.000902"))

      assert_equal([ nil, "100.000901" ], @adapter.calls.map { |call| call[:after] })
      assert_equal "100.000902", @channel_conversation.reload.last_imported_message_key
      assert_equal [ "Yamada: first", "Suzuki: second" ],
                   @conversation.reload.messages.where(role: "context").order(:id).pluck(:content)
    end

    should "apply no count or age limit in thread mode" do
      @adapter.thread_history = history(*Array.new(50) { |i| [ "Yamada", "message #{i}" ] })

      imported = ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming)

      assert_equal 50, imported
      assert_equal 50, @conversation.reload.messages.where(role: "context").count
      assert_equal([ :thread ], @adapter.calls.map { |call| call[:source] })
      assert_not @adapter.calls.first.key?(:limit), "thread mode must not pass a count limit"
      assert_not @adapter.calls.first.key?(:since), "thread mode must not pass an age limit"
    end

    should "keep importing into a thread conversation that already has messages" do
      @conversation.messages << AiHelperMessage.new(role: "user", content: "earlier question")
      @conversation.save!
      @adapter.thread_history = history([ "Yamada", "follow-up remark" ])

      imported = ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming)

      assert_equal 1, imported
    end
  end

  context "channel mode" do
    should "retrieve the channel history for a new conversation started outside a thread" do
      @adapter.channel_history = history([ "Yamada", "we should file a ticket" ])

      imported = ContextImporter.new(@adapter).import(
        conversation: @conversation, message: incoming(in_thread: false, message_ts: "100.000900")
      )

      assert_equal 1, imported
      call = @adapter.calls.first
      assert_equal :channel, call[:source]
      assert_equal "C1", call[:channel_id]
      assert_equal "100.000900", call[:before]
      assert_equal ContextImporter::CONTEXT_MESSAGE_LIMIT, call[:limit]
      assert_in_delta ContextImporter::CONTEXT_LOOKBACK_HOURS.hours.ago, call[:since], 5
    end

    should "store the retrieved channel messages and advance the cursor" do
      @adapter.channel_history = history([ "Yamada", "we should file a ticket" ])

      ContextImporter.new(@adapter).import(
        conversation: @conversation, message: incoming(in_thread: false, message_ts: "100.000900")
      )

      assert_equal [ "Yamada: we should file a ticket" ],
                   @conversation.reload.messages.where(role: "context").pluck(:content)
      assert_equal "100.000900", @channel_conversation.reload.last_imported_message_key
    end

    should "advance the cursor even when the channel has no recent messages" do
      @adapter.channel_history = []

      imported = ContextImporter.new(@adapter).import(
        conversation: @conversation, message: incoming(in_thread: false, message_ts: "100.000901")
      )

      assert_equal 0, imported
      assert_equal "100.000901", @channel_conversation.reload.last_imported_message_key
    end

    should "import nothing for a mention outside a thread that continues a conversation" do
      @conversation.messages << AiHelperMessage.new(role: "user", content: "earlier question")
      @conversation.save!

      imported = ContextImporter.new(@adapter).import(
        conversation: @conversation, message: incoming(in_thread: false)
      )

      assert_equal 0, imported
      assert_empty @adapter.calls
      assert_nil @channel_conversation.reload.last_imported_message_key
    end

    should "use the same path for direct messages" do
      @adapter.channel_history = history([ "Yamada", "one more thing" ])

      imported = ContextImporter.new(@adapter).import(
        conversation: @conversation,
        message: IncomingMessage.new(
          channel_type: "importer_chat", channel_id: "D1", thread_key: "D1:msg:900",
          message_ts: "900", text: "what about this?", dm: true
        )
      )

      assert_equal 1, imported
      assert_equal :channel, @adapter.calls.first[:source]
      assert_equal "D1", @adapter.calls.first[:channel_id]
    end
  end

  context "logging" do
    should "log the number of imported messages, the source and the conversation" do
      @adapter.thread_history = history([ "Yamada", "hello" ], [ "Suzuki", "hi" ])
      importer = ContextImporter.new(@adapter)
      logger = mock("logger")
      logger.expects(:info).with(
        regexp_matches(/imported 2 context messages from thread .*conversation #{@conversation.id}/)
      )
      importer.stubs(:ai_helper_logger).returns(logger)

      importer.import(conversation: @conversation, message: incoming)
    end
  end

  context "retrieval failures" do
    should "re-raise the adapter's error instead of swallowing it" do
      @adapter.stubs(:fetch_thread_history).raises(RuntimeError, "slack is down")

      error = assert_raises(RuntimeError) do
        ContextImporter.new(@adapter).import(conversation: @conversation, message: incoming)
      end

      assert_equal "slack is down", error.message
      assert_nil @channel_conversation.reload.last_imported_message_key
    end
  end
end
