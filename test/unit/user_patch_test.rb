require File.expand_path("../../test_helper", __FILE__)

class UserPatchTest < ActiveSupport::TestCase
  context "UserPatch" do
    setup do
      @user = User.find(1)
    end

    should "have ai_helper_conversations association" do
      assert_respond_to @user, :ai_helper_conversations
    end

    should "destroy conversations when user is deleted" do
      # Create conversations for the user
      conversation1 = AiHelperConversation.create!(
        title: "Test conversation 1",
        user: @user
      )

      conversation2 = AiHelperConversation.create!(
        title: "Test conversation 2",
        user: @user
      )

      # Verify conversations exist
      assert_equal 2, @user.ai_helper_conversations.count
      assert_not_nil AiHelperConversation.find_by(id: conversation1.id)
      assert_not_nil AiHelperConversation.find_by(id: conversation2.id)

      # Delete the user
      @user.destroy!

      # Verify conversations are deleted
      assert_nil AiHelperConversation.find_by(id: conversation1.id)
      assert_nil AiHelperConversation.find_by(id: conversation2.id)
    end

    should "only delete own conversations when user is deleted" do
      other_user = User.find(2)

      # Create conversations for both users
      user_conversation = AiHelperConversation.create!(
        title: "User conversation",
        user: @user
      )

      other_conversation = AiHelperConversation.create!(
        title: "Other user conversation",
        user: other_user
      )

      # Delete first user
      @user.destroy!

      # Verify only first user's conversation is deleted
      assert_nil AiHelperConversation.find_by(id: user_conversation.id)
      assert_not_nil AiHelperConversation.find_by(id: other_conversation.id)
    end
  end
end
