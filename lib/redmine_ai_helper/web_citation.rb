# frozen_string_literal: true

module RedmineAiHelper
  # A web search source (URL and optional title) returned by an LLM provider.
  # Immutable value object; the url and title come from an external source.
  class WebCitation
    # @return [String] the source URL (never blank)
    attr_reader :url
    # @return [String, nil] the source title; nil when absent or blank
    attr_reader :title

    # @param url [String] the source URL
    # @param title [String, nil] the source title
    # @raise [ArgumentError] when url is not a non-blank String, or title is neither String nor nil
    def initialize(url:, title: nil)
      raise ArgumentError, "url must be a String" unless url.is_a?(String)
      raise ArgumentError, "url must not be blank" if url.strip.empty?
      raise ArgumentError, "title must be a String or nil" unless title.nil? || title.is_a?(String)

      @url = url.dup.freeze
      @title = title.nil? || title.strip.empty? ? nil : title.dup.freeze
      freeze
    end

    class << self
      # Build from a RubyLLM citation.
      # @param citation [RubyLLM::Citation] the provider citation
      # @return [WebCitation, nil] nil when the citation has no url or a blank url
      # @raise [ArgumentError] when citation is not a RubyLLM::Citation, or its url
      #   or title has an unexpected type
      def from_ruby_llm(citation)
        raise ArgumentError, "citation must be a RubyLLM::Citation" unless citation.is_a?(RubyLLM::Citation)

        url = citation.url
        return nil if url.nil? || (url.is_a?(String) && url.strip.empty?)

        new(url: url, title: citation.title)
      end

      # Build from the stored form (string keys).
      # @param hash [Hash] a hash produced by {#to_h}
      # @return [WebCitation]
      # @raise [ArgumentError] when hash is not a Hash, or its values are invalid
      def from_h(hash)
        raise ArgumentError, "hash must be a Hash" unless hash.is_a?(Hash)

        new(url: hash["url"], title: hash["title"])
      end

      # Remove later citations with an already seen url, keeping the first position and title.
      # @param citations [Array<WebCitation>]
      # @return [Array<WebCitation>]
      def dedupe(citations)
        citations.uniq(&:url)
      end
    end

    # @return [Hash] the stored form; the title key is omitted when title is nil
    def to_h
      hash = { "url" => url }
      hash["title"] = title if title
      hash
    end

    # @return [String] the title when present, otherwise the url
    def label
      title || url
    end

    # Whether the url may be rendered as a link (http or https only).
    # @return [Boolean]
    def linkable?
      url.match?(%r{\Ahttps?://}i)
    end

    # @param other [Object]
    # @return [Boolean] true when other is a WebCitation with the same url and title
    def ==(other)
      other.is_a?(WebCitation) && url == other.url && title == other.title
    end
    alias_method :eql?, :==

    # @return [Integer]
    def hash
      [ url, title ].hash
    end
  end
end
