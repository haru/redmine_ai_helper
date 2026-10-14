require File.expand_path("../../../test_helper", __FILE__)

class AiHelperMessageTest < ActiveSupport::TestCase
  def setup
    @message = AiHelperMessage.new
  end

  def test_message_initialization
    assert_not_nil @message
  end

  context "web_citations" do
    setup do
      @conversation = AiHelperConversation.create!(user: User.find(1), title: "t")
    end

    should "be empty when citations is nil" do
      assert_equal [], @message.web_citations
    end

    should "store nil for an empty list" do
      @message.web_citations = []
      assert_nil @message.citations
    end

    should "round trip through the database" do
      list = [
        RedmineAiHelper::WebCitation.new(url: "https://example.com/a", title: "A"),
        RedmineAiHelper::WebCitation.new(url: "https://example.com/b")
      ]
      message = AiHelperMessage.new(role: "assistant", content: "x", conversation: @conversation)
      message.web_citations = list
      message.save!
      assert_equal list, AiHelperMessage.find(message.id).web_citations
    end

    should "raise ArgumentError when an element is not a WebCitation" do
      assert_raises(ArgumentError) { @message.web_citations = [ { "url" => "https://example.com" } ] }
    end

    should "raise ArgumentError when the list is not an Array" do
      assert_raises(ArgumentError) { @message.web_citations = nil }
    end

    should "be invalid when the raw citations are not a list of hashes with a String url" do
      [ { "url" => "https://example.com" }, [ "https://example.com" ], [ { "title" => "A" } ] ].each do |raw|
        message = AiHelperMessage.new(role: "assistant", content: "x", conversation: @conversation, citations: raw)
        assert_not message.valid?, raw.inspect
        assert message.errors.added?(:citations, :invalid)
      end
    end

    should "be valid with nil or well-formed raw citations" do
      assert AiHelperMessage.new(role: "assistant", content: "x", conversation: @conversation).valid?
      assert AiHelperMessage.new(role: "assistant", content: "x", conversation: @conversation,
                                 citations: [ { "url" => "https://example.com" } ]).valid?
    end
  end
end
