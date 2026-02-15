require "redmine_ai_helper/base_tools"

# This class provides fortune-telling features such as omikuji (Japanese fortune-telling) and horoscope predictions.
# Uses the define_function DSL from BaseTools which generates RubyLLM::Tool subclasses.
class FortuneTools < RedmineAiHelper::BaseTools
  # Definition of the Omikuji fortune-telling feature
  define_function :omikuji, description: "Draw a fortune by Japanese-OMIKUJI for the specified date." do
    property :date, type: "string", description: "Specify the date to draw the fortune in 'YYYY-MM-DD' format.", required: true
  end

  # Omikuji fortune-telling method
  # @param date [String] The date for which to draw the fortune.
  # @return [String] The fortune result.
  # @example
  #   omikuji(date: "2023-10-01")
  #   => "DAI-KICHI/Great blessing"
  #
  # @note The date parameter is not used in the fortune drawing process.
  def omikuji(date:)
    ["DAI-KICHI/Great blessing", "CHU-KICHI/Middle blessing", "SHOU-KICHI/Small blessing", "SUE-KICHI/Future blessing", "KYOU/Curse", "DAI-KYOU/Great curse"].sample
  end

  # Definition of the horoscope fortune-telling feature
  define_function :horoscope, description: "Predict the monthly horoscope for the person with the specified birthday." do
    property :birthday, type: "string", description: "Specify the birthday of the person to predict in 'YYYY-MM-DD' format.", required: true
  end

  # Horoscope fortune-telling method
  # @param birthday [String] The birthday of the person to predict.
  # @return [String] The horoscope result.
  # @example
  #   horoscope(birthday: "1990-01-01")
  #   => "This month's fortune is excellent. Everything you do will go well."
  #
  # @note The birthday parameter is not used in the horoscope prediction process.
  def horoscope(birthday:)
    fortune1 = "This month's fortune is excellent. Everything you do will go well."
    fortune2 = "This month's fortune is so-so. There are no particular problems."
    fortune3 = "This month's fortune is not very good. Caution is required."
    fortune4 = "This month's fortune is the worst. Nothing you do will go well."
    [fortune1, fortune2, fortune3, fortune4].sample
  end
end
