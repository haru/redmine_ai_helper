require File.expand_path("../../test_helper", __FILE__)

class PromptTemplatesIssueLinkTest < ActiveSupport::TestCase
  PROMPT_DIR = File.expand_path("../../../assets/prompt_templates", __FILE__)

  CHAT_REPLY_TEMPLATES = %w[
    issue_read_agent/backstory.yml
    issue_read_agent/backstory_ja.yml
    leader_agent/system_prompt.yml
    leader_agent/system_prompt_ja.yml
    base_agent/system_prompt.yml
    base_agent/system_prompt_ja.yml
  ].freeze

  context "chat reply prompt templates" do
    CHAT_REPLY_TEMPLATES.each do |relative_path|
      should "#{relative_path} contains #N format instruction" do
        content = File.read(File.join(PROMPT_DIR, relative_path))
        assert_match(/#\s*1234|#<id>|#\{id\}|#N|#番号|#チケット番号/i, content,
                     "#{relative_path} does not contain a #N format instruction")
      end

      should "#{relative_path} does not contain old markdown link format [Issue ID](/issues/...)" do
        content = File.read(File.join(PROMPT_DIR, relative_path))
        assert_no_match(/\[[^\]]*(?:Issue\s*ID|チケットID)[^\]]*\]\(\/issues\/[^)]+\)/i, content,
                     "#{relative_path} still contains old markdown link instruction")
      end
    end
  end

  context "non-chat-reply templates are unchanged" do
    should "inline_completion template is not affected" do
      content = File.read(File.join(PROMPT_DIR, "issue_read_agent/inline_completion.yml"))
      assert content.length > 0
    end
  end
end
