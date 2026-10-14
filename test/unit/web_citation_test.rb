require File.expand_path("../../test_helper", __FILE__)

class WebCitationTest < ActiveSupport::TestCase
  WebCitation = RedmineAiHelper::WebCitation

  context "WebCitation" do
    context "initialize" do
      should "keep url and title" do
        citation = WebCitation.new(url: "https://example.com/a", title: "A")
        assert_equal "https://example.com/a", citation.url
        assert_equal "A", citation.title
      end

      should "accept a nil title" do
        assert_nil WebCitation.new(url: "https://example.com/a").title
      end

      should "normalize a blank title to nil" do
        assert_nil WebCitation.new(url: "https://example.com/a", title: "   ").title
      end

      should "raise ArgumentError when url is not a String" do
        assert_raises(ArgumentError) { WebCitation.new(url: nil) }
        assert_raises(ArgumentError) { WebCitation.new(url: 1) }
      end

      should "raise ArgumentError when url is blank" do
        assert_raises(ArgumentError) { WebCitation.new(url: "") }
        assert_raises(ArgumentError) { WebCitation.new(url: "  ") }
      end

      should "raise ArgumentError when title is neither String nor nil" do
        assert_raises(ArgumentError) { WebCitation.new(url: "https://example.com", title: 1) }
      end

      should "be frozen and not share the caller's strings" do
        url = +"https://example.com/a"
        title = +"A"
        citation = WebCitation.new(url: url, title: title)
        url << "x"
        title << "x"

        assert citation.frozen?
        assert citation.url.frozen?
        assert citation.title.frozen?
        assert_equal "https://example.com/a", citation.url
        assert_equal "A", citation.title
      end
    end

    context "from_ruby_llm" do
      should "convert a RubyLLM::Citation" do
        source = RubyLLM::Citation.new(url: "https://example.com/a", title: "A")
        assert_equal WebCitation.new(url: "https://example.com/a", title: "A"), WebCitation.from_ruby_llm(source)
      end

      should "return nil when the url is nil or empty" do
        assert_nil WebCitation.from_ruby_llm(RubyLLM::Citation.new(url: nil, title: "A"))
        assert_nil WebCitation.from_ruby_llm(RubyLLM::Citation.new(url: "", title: "A"))
        assert_nil WebCitation.from_ruby_llm(RubyLLM::Citation.new(url: "  ", title: "A"))
      end

      should "raise ArgumentError when the url is not a String" do
        assert_raises(ArgumentError) { WebCitation.from_ruby_llm(RubyLLM::Citation.new(url: 1, title: "A")) }
      end

      should "raise ArgumentError for any other type" do
        assert_raises(ArgumentError) { WebCitation.from_ruby_llm({ url: "https://example.com" }) }
      end
    end

    context "from_h and to_h" do
      should "round trip" do
        citation = WebCitation.new(url: "https://example.com/a", title: "A")
        assert_equal citation, WebCitation.from_h(citation.to_h)
      end

      should "raise ArgumentError when from_h is given something other than a Hash" do
        assert_raises(ArgumentError) { WebCitation.from_h(nil) }
        assert_raises(ArgumentError) { WebCitation.from_h([ "https://example.com" ]) }
      end

      should "omit the title key when title is nil" do
        assert_equal({ "url" => "https://example.com/a" }, WebCitation.new(url: "https://example.com/a").to_h)
      end
    end

    context "dedupe" do
      should "keep the first position and title and preserve the order" do
        a1 = WebCitation.new(url: "https://example.com/a", title: "first")
        b = WebCitation.new(url: "https://example.com/b", title: "B")
        a2 = WebCitation.new(url: "https://example.com/a", title: "second")
        assert_equal [ a1, b ], WebCitation.dedupe([ a1, b, a2 ])
      end
    end

    context "label" do
      should "return the title when present, otherwise the url" do
        assert_equal "A", WebCitation.new(url: "https://example.com/a", title: "A").label
        assert_equal "https://example.com/a", WebCitation.new(url: "https://example.com/a").label
      end
    end

    context "linkable?" do
      should "be true only for http and https, case-insensitively" do
        assert WebCitation.new(url: "http://example.com").linkable?
        assert WebCitation.new(url: "https://example.com").linkable?
        assert WebCitation.new(url: "HTTPS://example.com").linkable?
        assert_not WebCitation.new(url: "javascript:alert(1)").linkable?
        assert_not WebCitation.new(url: "ftp://example.com").linkable?
      end
    end

    should "compare by url and title" do
      assert_equal WebCitation.new(url: "https://a", title: "A"), WebCitation.new(url: "https://a", title: "A")
      assert_not_equal WebCitation.new(url: "https://a", title: "A"), WebCitation.new(url: "https://a", title: "B")
    end
  end
end
