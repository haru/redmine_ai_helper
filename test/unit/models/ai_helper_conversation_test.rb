require File.expand_path("../../../test_helper", __FILE__)

class AiHelperConversationTest < ActiveSupport::TestCase
  def setup
    @ai_helper = AiHelperConversation.new
  end


  def test_ai_helper_initialization
    assert_not_nil @ai_helper
  end

  context "messages_for_openai" do
    setup do
      @conversation = AiHelperConversation.create!(title: "context conversation", user: User.find(1))
    end

    should "return the plain messages unchanged when the conversation has no context" do
      add_message("user", "question")
      add_message("assistant", "answer")

      assert_equal [
        { role: "user", content: "question" },
        { role: "assistant", content: "answer" }
      ], @conversation.messages_for_openai
    end

    should "merge consecutive context messages into a single headed user message" do
      add_message("context", "Yamada: it crashes on save")
      add_message("context", "Suzuki: stack trace attached")
      add_message("user", "what is going on?")

      result = @conversation.messages_for_openai

      assert_equal 2, result.size
      assert_equal "user", result.first[:role]
      assert_equal [
        AiHelperConversation::CONTEXT_HEADER,
        "Yamada: it crashes on save",
        "Suzuki: stack trace attached"
      ].join("\n"), result.first[:content]
      assert_equal({ role: "user", content: "what is going on?" }, result.last)
    end

    should "keep the conversation order and merge each run of context messages separately" do
      add_message("context", "Yamada: first")
      add_message("user", "first question")
      add_message("assistant", "first answer")
      add_message("context", "Suzuki: second")

      result = @conversation.messages_for_openai

      assert_equal([ "user", "user", "assistant", "user" ], result.map { |m| m[:role] })
      assert_match(/Yamada: first/, result[0][:content])
      assert_equal "first question", result[1][:content]
      assert_match(/Suzuki: second/, result[3][:content])
    end

    should "drop the oldest context messages when the character limit is exceeded" do
      add_message("context", "A: #{"a" * 15_000}")
      add_message("context", "B: #{"b" * 15_000}")
      add_message("user", "question")

      result = @conversation.messages_for_openai

      assert_equal 2, result.size
      assert_no_match(/aaaa/, result.first[:content])
      assert_match(/bbbb/, result.first[:content])
    end

    should "not modify the stored records when context messages are dropped" do
      add_message("context", "A: #{"a" * 15_000}")
      add_message("context", "B: #{"b" * 15_000}")

      @conversation.messages_for_openai

      assert_equal 2, @conversation.reload.messages.where(role: "context").count
    end

    should "keep every context message when the total stays within the limit" do
      add_message("context", "A: short")
      add_message("context", "B: also short")

      result = @conversation.messages_for_openai

      assert_equal 1, result.size
      assert_match(/A: short/, result.first[:content])
      assert_match(/B: also short/, result.first[:content])
    end
  end

  def test_cleanup_old_conversations
    user = User.find(1)

    # Create conversations with different ages
    old_conversation = AiHelperConversation.create!(
      title: "Old conversation",
      user: user,
      created_at: 7.months.ago
    )

    recent_conversation = AiHelperConversation.create!(
      title: "Recent conversation",
      user: user,
      created_at: 1.month.ago
    )

    # Verify both conversations exist
    assert_equal 2, AiHelperConversation.count

    # Run cleanup
    AiHelperConversation.cleanup_old_conversations

    # Verify only recent conversation remains
    assert_equal 1, AiHelperConversation.count
    assert_equal recent_conversation.id, AiHelperConversation.first.id
    assert_nil AiHelperConversation.find_by(id: old_conversation.id)
  end

  def test_cleanup_old_conversations_with_different_ages
    user = User.find(1)

    # Create conversation 5 months ago (should remain)
    five_months_old = AiHelperConversation.create!(
      title: "5 months old",
      user: user,
      created_at: 5.months.ago
    )

    # Create conversation 7 months ago (should be deleted)
    seven_months_old = AiHelperConversation.create!(
      title: "7 months old",
      user: user,
      created_at: 7.months.ago
    )

    # Verify both conversations exist before cleanup
    initial_count = AiHelperConversation.count

    # Run cleanup
    AiHelperConversation.cleanup_old_conversations

    # Verify 5 months conversation remains, 7 months is deleted
    remaining_conversations = AiHelperConversation.all

    assert_equal initial_count - 1, remaining_conversations.count
    assert_not_nil AiHelperConversation.find_by(id: five_months_old.id)
    assert_nil AiHelperConversation.find_by(id: seven_months_old.id)
  end

  private

  # Appends and stores one message of the given role in @conversation.
  def add_message(role, content)
    @conversation.messages << AiHelperMessage.new(role: role, content: content)
    @conversation.save!
  end
end
