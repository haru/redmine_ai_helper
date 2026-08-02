# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelIssueLinkFormatterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  context "IssueLinkFormatter::Format" do
    should "delegate #render to the renderer callable" do
      format = RedmineAiHelper::ChatChannel::IssueLinkFormatter::Format.new(
        ->(label, url) { "#{label}@#{url}" },
        /#/
      )

      assert_equal "#1549@https://r.example.com/issues/1549",
                   format.render("#1549", "https://r.example.com/issues/1549")
    end

    should "produce a result that fully matches the format's own pattern" do
      assert format_constants.any?, "expected at least one Format constant to check"

      format_constants.each do |name|
        format = RedmineAiHelper::ChatChannel::IssueLinkFormatter.const_get(name)
        rendered = format.render("#1549", "https://r.example.com/issues/1549")
        assert_equal rendered, format.pattern.match(rendered)&.[](0),
                     "#{name}#render result #{rendered.inspect} should match its own pattern over its full span, not partially"
      end
    end

    should "produce a result without newlines" do
      format_constants.each do |name|
        format = RedmineAiHelper::ChatChannel::IssueLinkFormatter.const_get(name)
        rendered = format.render("#1549", "https://r.example.com/issues/1549")
        assert_no_match(/\n/, rendered, "#{name}#render result must not contain newlines")
      end
    end
  end

  # All Format constants declared on IssueLinkFormatter, discovered rather
  # than hard-coded so a newly added chat-tool format is covered automatically.
  def format_constants
    RedmineAiHelper::ChatChannel::IssueLinkFormatter.constants.select do |name|
      RedmineAiHelper::ChatChannel::IssueLinkFormatter.const_get(name).is_a?(RedmineAiHelper::ChatChannel::IssueLinkFormatter::Format)
    end
  end

  def stub_host(protocol: "https", host: "r.example.com")
    Setting.stubs(:protocol).returns(protocol)
    Setting.stubs(:host_name).returns(host)
  end

  def formatter(format = nil)
    format ||= RedmineAiHelper::ChatChannel::IssueLinkFormatter::PLAIN
    RedmineAiHelper::ChatChannel::IssueLinkFormatter.new(format)
  end

  context "#format" do
    setup do
      stub_host
    end

    should "V-01: convert #1549 to SLACK link syntax" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("#1549 を確認")

      assert_equal "<https://r.example.com/issues/1549|#1549> を確認", result
    end

    should "V-02: replace both occurrences of the same issue number" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("See #1549 and #1540")

      assert_match(/<https:\/\/r\.example\.com\/issues\/1549\|#1549>/, result)
      assert_match(/<https:\/\/r\.example\.com\/issues\/1540\|#1540>/, result)
      assert_no_match(/#1549[^>]/, result.gsub(/<[^>]*>#1549>/, ""))
    end

    should "V-02: replace duplicate references to the same number" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("#1549 and #1549")

      assert_equal 2, result.scan(/#1549/).length
      assert_no_match(/(?<!<https:\/\/r\.example\.com\/issues\/1549\|)#1549/, result)
    end

    should "V-03: return input unchanged when no issue references are present" do
      input = "チケットはありません"
      result = formatter.format(input)

      assert_equal input, result
    end

    should "V-04: not convert abc#1549" do
      assert_equal "abc#1549", formatter.format("abc#1549")
    end

    should "V-04: not convert 123#1549" do
      assert_equal "123#1549", formatter.format("123#1549")
    end

    should "V-04: not convert x_#1549" do
      assert_equal "x_#1549", formatter.format("x_#1549")
    end

    should "V-05: convert チケット#1549" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("チケット#1549")

      assert_match(/<https:\/\/r\.example\.com\/issues\/1549\|#1549>/, result)
    end

    should "V-05: convert （#1549）" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("（#1549）")

      assert_match(/<https:\/\/r\.example\.com\/issues\/1549\|#1549>/, result)
    end

    should "V-05: convert 「#1549」" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("「#1549」")

      assert_match(/<https:\/\/r\.example\.com\/issues\/1549\|#1549>/, result)
    end

    should "V-05: convert #1549。" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("#1549。")

      assert_match(/<https:\/\/r\.example\.com\/issues\/1549\|#1549>。/, result)
    end

    should "V-05: convert #1549 at the beginning of a line" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("first line\n#1549 next")

      assert_match(/\n<https:\/\/r\.example\.com\/issues\/1549\|#1549> next/, result)
    end

    should "V-06: not convert #abc" do
      assert_equal "#abc", formatter.format("#abc")
    end

    should "V-06: not convert lone #" do
      assert_equal "#", formatter.format("#")
    end

    should "V-06: not convert # 1549" do
      assert_equal "# 1549", formatter.format("# 1549")
    end

    should "V-06: not convert # 見出し" do
      assert_equal "# 見出し", formatter.format("# 見出し")
    end

    should "V-07: not convert #1549 inside inline code" do
      assert_equal "`#1549`", formatter.format("`#1549`")
    end

    should "V-07: not convert #1549 inside fenced code block" do
      input = "```\n#1549\n```"
      assert_equal input, formatter.format(input)
    end

    should "V-07: not convert #1549 inside unclosed fenced code block" do
      input = "```\n#1549"
      assert_equal input, formatter.format(input)
    end

    should "V-07: not convert #1549 inside tilde fenced code block" do
      input = "~~~\n#1549\n~~~"
      assert_equal input, formatter.format(input)
    end

    should "V-07: convert a ref that follows a closed fenced code block, leaving the fenced ref untouched" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("```ruby\n#1\n```\nsee #2")

      assert_equal "```ruby\n#1\n```\nsee <https://r.example.com/issues/2|#2>", result
    end

    should "V-08: not convert #note-3 inside a bare URL" do
      input = "https://r.example.com/issues/1549#note-3"
      assert_equal input, formatter.format(input)
    end

    should "V-08: not convert inside an existing markdown link" do
      input = "[前回の修正](https://r.example.com/issues/1549)"
      assert_equal input, formatter.format(input)
    end

    should "V-09: convert #999999999999 without existence check" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("#999999999999")

      assert_match(/<https:\/\/r\.example\.com\/issues\/999999999999\|#999999999999>/, result)
    end

    should "V-10: PLAIN format renders #1549 (URL)" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::PLAIN)
      result = f.format("#1549")

      assert_equal "#1549 (https://r.example.com/issues/1549)", result
    end

    should "V-10: SLACK format renders <URL|#1549>" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("#1549")

      assert_equal "<https://r.example.com/issues/1549|#1549>", result
    end

    should "V-10: DISCORD format renders [#1549](URL)" do
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::DISCORD)
      result = f.format("#1549")

      assert_equal "[#1549](https://r.example.com/issues/1549)", result
    end

    should "V-11: generate correct absolute URL when host includes port and path prefix" do
      stub_host(protocol: "https", host: "r.example.com:3000/redmine")
      f = formatter(RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK)
      result = f.format("#1549")

      assert_match(/https:\/\/r\.example\.com:3000\/redmine\/issues\/1549/, result)
    end

    should "raise when Setting.host_name is blank" do
      stub_host(host: "")
      f = formatter

      assert_raises(RuntimeError) { f.format("#1549") }
    end
  end
end
