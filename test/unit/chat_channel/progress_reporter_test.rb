# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelProgressReporterTest < ActiveSupport::TestCase
  Reporter = RedmineAiHelper::ChatChannel::ProgressReporter
  Handle = Reporter::Handle

  # Records every progress call. Each operation can be made to fail with an
  # error stored in +errors+.
  class StubApiError < StandardError; end

  class StubAdapter
    attr_reader :calls, :failures
    attr_accessor :supports, :max_length

    def initialize(max_length: 3900)
      @calls = []
      @failures = {}
      @supports = true
      @max_length = max_length
    end

    def channel_type
      "stub_chat"
    end

    def supports_progress?
      @supports
    end

    def max_message_length
      @max_length
    end

    def progress_errors
      [ StubApiError ]
    end

    def post_progress(channel_id:, thread_key:, text:)
      @calls << [ :post, { channel_id: channel_id, thread_key: thread_key, text: text } ]
      raise @failures[:post] if @failures[:post]

      Handle.new(channel_id: channel_id, message_id: "P1")
    end

    def mark_progress(handle:)
      @calls << [ :mark, { handle: handle } ]
      raise @failures[:mark] if @failures[:mark]
    end

    def update_progress(handle:, text:)
      @calls << [ :update, { handle: handle, text: text } ]
      raise @failures[:update] if @failures[:update]
    end

    def delete_progress(handle:)
      @calls << [ :delete, { handle: handle } ]
      raise @failures[:delete] if @failures[:delete]
    end

    def kinds
      @calls.map(&:first)
    end
  end

  setup do
    @adapter = StubAdapter.new
    @message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
      channel_type: "stub_chat", channel_id: "C1", thread_key: "C1:1.1", text: "hi", message_ts: "1.1"
    )
    @reporter = Reporter.new(adapter: @adapter, message: @message)
    @logger = stub_everything("logger")
    @reporter.stubs(:ai_helper_logger).returns(@logger)
  end

  context "inspect" do
    should "name neither the adapter nor the message so the LLM option log stays clean" do
      assert_equal "#<RedmineAiHelper::ChatChannel::ProgressReporter>", @reporter.inspect
      assert_no_match(/stub_chat|hi/, { progress_proc: @reporter }.to_s)
    end
  end

  context "Handle" do
    should "be created from non-empty strings and be frozen" do
      handle = Handle.new(channel_id: "C1", message_id: "1700000000.000100")

      assert_equal "C1", handle.channel_id
      assert_equal "1700000000.000100", handle.message_id
      assert handle.frozen?
    end

    [ :channel_id, :message_id ].each do |field|
      [ nil, "", 123 ].each do |invalid|
        should "reject #{invalid.inspect} as #{field} with ArgumentError" do
          args = { channel_id: "C1", message_id: "1" }.merge(field => invalid)

          assert_raises(ArgumentError) { Handle.new(**args) }
        end
      end
    end
  end

  context "call" do
    should "post the first line to the message's channel and thread" do
      @reporter.call("A\n")

      assert_equal [ :post, { channel_id: "C1", thread_key: "C1:1.1", text: "A" } ], @adapter.calls.first
      assert_equal [ :post, :mark ], @adapter.kinds
    end

    should "rewrite the same message with every line so far and post only once (FR-002, SC-002)" do
      @reporter.call("A\n")
      @reporter.call("B\n")
      @reporter.call("C\n")

      assert_equal [ :post, :mark, :update, :update ], @adapter.kinds
      assert_equal "A\nB", @adapter.calls[2].last[:text]
      assert_equal "A\nB\nC", @adapter.calls[3].last[:text]
      assert_equal "P1", @adapter.calls[1].last[:handle].message_id
      assert_equal "C1", @adapter.calls[2].last[:handle].channel_id
    end

    should "ignore empty and newline-only text without calling the API" do
      @reporter.call("")
      @reporter.call("\n")
      @reporter.call("  \n")

      assert_empty @adapter.calls
    end

    should "reject text that is not a String" do
      assert_raises(ArgumentError) { @reporter.call(nil) }
      assert_raises(ArgumentError) { @reporter.call(:sym) }
      assert_empty @adapter.calls
    end

    should "drop the oldest lines first when the text exceeds the limit (FR-007)" do
      @adapter.max_length = 10
      @reporter.call("aaaa\n")
      @reporter.call("bbbb\n")
      @reporter.call("cccc\n")

      texts = @adapter.calls.reject { |kind, _| kind == :mark }.map { |_, args| args[:text] }
      assert_equal [ "aaaa", "aaaa\nbbbb", "bbbb\ncccc" ], texts
      assert(texts.all? { |text| text.length <= 10 })
    end

    should "keep two lines that join to exactly the limit (FR-007)" do
      @adapter.max_length = 9
      @reporter.call("aaaa\n")
      @reporter.call("bbbb\n")

      assert_equal "aaaa\nbbbb", @adapter.calls.reject { |kind, _| kind == :mark }.last.last[:text]
    end

    should "cut a single line that alone exceeds the limit" do
      @adapter.max_length = 10
      @reporter.call("#{"x" * 50}\n")

      text = @adapter.calls.first.last[:text]
      assert_equal 10, text.length
    end

    should "do nothing when the adapter does not support progress (FR-010)" do
      @adapter.supports = false
      reporter = Reporter.new(adapter: @adapter, message: @message)
      reporter.call("A\n")
      reporter.finish

      assert_empty @adapter.calls
    end
  end

  context "finish" do
    should "delete the posted message" do
      @reporter.call("A\n")
      @reporter.finish

      assert_equal [ :post, :mark, :delete ], @adapter.kinds
      assert_equal "P1", @adapter.calls.last.last[:handle].message_id
    end

    should "not call the API when nothing was posted" do
      @reporter.finish

      assert_empty @adapter.calls
    end

    should "delete only once" do
      @reporter.call("A\n")
      @reporter.finish
      @reporter.finish

      assert_equal [ :post, :mark, :delete ], @adapter.kinds
    end

    should "ignore calls after finish" do
      @reporter.call("A\n")
      @reporter.finish
      @reporter.call("B\n")

      assert_equal [ :post, :mark, :delete ], @adapter.kinds
    end
  end

  context "failures (FR-006)" do
    should "log a failed reaction and keep updating and deleting the message" do
      @adapter.failures[:mark] = StubApiError.new("missing_scope")
      @logger.expects(:error).once.with do |message|
        message.include?("failed to mark progress message P1 (channel C1)") && message.include?("missing_scope")
      end

      assert_nothing_raised { @reporter.call("A\n") }
      @reporter.call("B\n")
      @reporter.finish

      assert_equal [ :post, :mark, :update, :delete ], @adapter.kinds
    end

    should "log a failed post, stop updating and not delete" do
      @adapter.failures[:post] = StubApiError.new("channel_not_found")
      @logger.expects(:error).once.with do |message|
        message.start_with?("chat channel: failed to post progress message on stub_chat thread C1:1.1: ") &&
          message.include?("channel_not_found")
      end

      assert_nothing_raised { @reporter.call("A\n") }
      @reporter.call("B\n")
      @reporter.finish

      assert_equal [ :post ], @adapter.kinds
    end

    should "log a failed update and try again on the next call and on finish" do
      @reporter.call("A\n")
      @adapter.failures[:update] = StubApiError.new("message_not_found")
      @logger.expects(:error).twice.with do |message|
        message.start_with?("chat channel: failed to update progress message P1 (channel C1) on stub_chat thread C1:1.1: ")
      end

      assert_nothing_raised { @reporter.call("B\n") }
      assert_nothing_raised { @reporter.call("C\n") }
      @reporter.finish

      assert_equal [ :post, :mark, :update, :update, :delete ], @adapter.kinds
    end

    should "log a failed delete without raising" do
      @reporter.call("A\n")
      @adapter.failures[:delete] = StubApiError.new("cant_delete_message")
      @logger.expects(:error).once.with do |message|
        message.start_with?("chat channel: failed to delete progress message P1 (channel C1) on stub_chat thread C1:1.1: ")
      end

      assert_nothing_raised { @reporter.finish }
    end

    should "not catch bugs outside the adapter calls" do
      @adapter.max_length = nil

      assert_raises(StandardError) { @reporter.call("A\n") }
    end

    should "reject a max_message_length that cannot hold the omission marker" do
      @adapter.max_length = 2

      assert_raises(ArgumentError) { @reporter.call("A\n") }
      assert_empty @adapter.calls
    end

    should "not catch errors the adapter does not declare in progress_errors" do
      @adapter.failures[:post] = NoMethodError.new("undefined method for nil")

      assert_raises(NoMethodError) { @reporter.call("A\n") }
    end

    should "raise TypeError when post_progress does not return a Handle, and delete nothing" do
      @adapter.define_singleton_method(:post_progress) do |**args|
        @calls << [ :post, args ]
        nil
      end

      error = assert_raises(TypeError) { @reporter.call("A\n") }
      @reporter.finish

      assert_match(/must return a ProgressReporter::Handle/, error.message)
      assert_equal [ :post ], @adapter.kinds
    end

    should "name the posted message in the log when a delete fails" do
      @reporter.call("A\n")
      @adapter.failures[:delete] = StubApiError.new("cant_delete_message")
      @logger.expects(:error).once.with { |message| message.include?("progress message P1 (channel C1)") }

      @reporter.finish
    end
  end
end
