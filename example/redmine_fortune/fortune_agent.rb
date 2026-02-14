require "redmine_ai_helper/base_agent"
require_relative "./fortune_tools"

class FortuneAgent < RedmineAiHelper::BaseAgent
  def backstory
    "You are a fortune-telling agent of the Redmine AI Helper plugin. You can predict the fortunes of Redmine users. You provide Japanise-omikuji and horoscope readings."
  end

  def available_tool_classes
    FortuneTools.tool_classes
  end
end
