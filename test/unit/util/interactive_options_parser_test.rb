require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/interactive_options_parser"

class RedmineAiHelper::Util::InteractiveOptionsParserTest < ActiveSupport::TestCase
  include RedmineAiHelper::Logger

  SIMPLE_BLOCK = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"はい","value":"はい"},{"label":"いいえ","value":"いいえ"}]}-->'
  FIVE_CHOICES_BLOCK = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"A","value":"A"},{"label":"B","value":"B"},{"label":"C","value":"C"},{"label":"D","value":"D"},{"label":"E","value":"E"}]}-->'
  SIX_CHOICES_BLOCK = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"A","value":"A"},{"label":"B","value":"B"},{"label":"C","value":"C"},{"label":"D","value":"D"},{"label":"E","value":"E"},{"label":"F","value":"F"}]}-->'
  THREE_CHOICES_BLOCK = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"High","value":"High"},{"label":"Normal","value":"Normal"},{"label":"Low","value":"Low"}]}-->'

  Parser = RedmineAiHelper::Util::InteractiveOptionsParser

  context "strip" do
    should "remove the options block and return the body" do
      content = "この課題を次のバージョンに移動しますか？\n\n#{SIMPLE_BLOCK}"
      result = Parser.strip(content)
      assert_equal "この課題を次のバージョンに移動しますか？", result
      refute_includes result, "AIHELPER_OPTIONS"
    end

    should "return the original string when no block is present" do
      content = "普通の回答です。"
      assert_equal content, Parser.strip(content)
    end

    should "strip leading and trailing whitespace after removing the block" do
      content = "  本文  \n\n#{SIMPLE_BLOCK}\n  "
      result = Parser.strip(content)
      assert_equal "本文", result
    end
  end

  context "extract_options" do
    should "return choices array with 2 choices from a simple block" do
      content = "この課題を次のバージョンに移動しますか？\n\n#{SIMPLE_BLOCK}"
      result = Parser.extract_options(content)
      assert_not_nil result
      assert_equal 2, result.length
      assert_equal "はい", result[0][:label]
      assert_equal "はい", result[0][:value]
      assert_equal "いいえ", result[1][:label]
      assert_equal "いいえ", result[1][:value]
    end

    should "return all 5 choices when block has 5 choices" do
      content = "どれにしますか？\n\n#{FIVE_CHOICES_BLOCK}"
      result = Parser.extract_options(content)
      assert_not_nil result
      assert_equal 5, result.length
    end

    should "return only the first 5 choices when block has 6 or more" do
      content = "どれにしますか？\n\n#{SIX_CHOICES_BLOCK}"
      result = Parser.extract_options(content)
      assert_not_nil result
      assert_equal 5, result.length
      assert_equal "E", result[4][:label]
    end

    should "return nil when no block is present" do
      result = Parser.extract_options("普通の回答です。")
      assert_nil result
    end

    should "return nil and log error when JSON is invalid" do
      content = "<!--AIHELPER_OPTIONS:invalid json-->"
      ai_helper_logger.expects(:error).at_least_once
      result = Parser.extract_options(content)
      assert_nil result
    end

    should "exclude choices where label is empty" do
      content = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"","value":"A"},{"label":"B","value":"B"}]}-->'
      result = Parser.extract_options(content)
      assert_not_nil result
      assert_equal 1, result.length
      assert_equal "B", result[0][:label]
    end

    should "exclude choices where value is empty" do
      content = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"A","value":""},{"label":"B","value":"B"}]}-->'
      result = Parser.extract_options(content)
      assert_not_nil result
      assert_equal 1, result.length
      assert_equal "B", result[0][:label]
    end

    should "return 3 choices in correct order" do
      content = "優先度を選択してください。\n\n#{THREE_CHOICES_BLOCK}"
      result = Parser.extract_options(content)
      assert_not_nil result
      assert_equal 3, result.length
      assert_equal "High", result[0][:label]
      assert_equal "Normal", result[1][:label]
      assert_equal "Low", result[2][:label]
    end

    should "return independent label and value when they differ" do
      content = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"表示テキスト","value":"送信テキスト"}]}-->'
      result = Parser.extract_options(content)
      assert_not_nil result
      assert_equal 1, result.length
      assert_equal "表示テキスト", result[0][:label]
      assert_equal "送信テキスト", result[0][:value]
    end
  end
end
