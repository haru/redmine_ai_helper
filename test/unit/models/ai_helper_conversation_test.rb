require File.expand_path("../../../test_helper", __FILE__)

class AiHelperConversationTest < ActiveSupport::TestCase
  def setup
    @ai_helper = AiHelperConversation.new
  end


  def test_ai_helper_initialization
    assert_not_nil @ai_helper
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
end
