# frozen_string_literal: true

module RedmineAiHelper
  module ChatChannel
    # Converts `#NNNN` issue references in outbound chat messages into
    # chat-tool-specific link syntax. The detection pattern protects code
    # blocks, inline code, existing URLs and markdown links from conversion.
    class IssueLinkFormatter
      # Value object pairing a rendering function with the regexp that
      # matches its output, used by {BaseAdapter#link_safe_cut} to avoid
      # splitting messages inside a link.
      Format = Struct.new(:renderer, :pattern) do
        # Builds the link string for the given label and URL.
        # @param label [String] the display text (e.g. "#1549")
        # @param url [String] the absolute URL
        # @return [String]
        def render(label, url)
          renderer.call(label, url)
        end
      end

      # Fallback format: `#1549 (https://example.com/issues/1549)`
      PLAIN = Format.new(
        ->(label, url) { "#{label} (#{url})" },
        /#\d+ \(https?:\/\/[^\s)]+\)/
      ).freeze

      # Slack mrkdwn format: `<https://example.com/issues/1549|#1549>`
      SLACK = Format.new(
        ->(label, url) { "<#{url}|#{label}>" },
        /<https?:\/\/[^\s|>]+\|#\d+>/
      ).freeze

      # Discord markdown format: `[#1549](https://example.com/issues/1549)`
      DISCORD = Format.new(
        ->(label, url) { "[#{label}](#{url})" },
        /\[#\d+\]\(https?:\/\/[^\s)]+\)/
      ).freeze

      # Combined detection pattern for protected regions and issue references.
      # The first alternative (protected) matches code fences (backtick or
      # tilde, with unclosed fences extending to end-of-string), inline
      # code, existing markdown links and bare URLs — these are passed
      # through unchanged. The second alternative (ref) matches a `#`
      # followed by one or more digits, but only when not immediately
      # preceded by an ASCII alphanumeric character or underscore (so
      # `abc#1549` and `x_#1549` are excluded, but full-width CJK
      # prefixes and punctuation are accepted). The `/m` flag makes `.` match
      # any character except newline, so a single-pattern pass avoids
      # splitting multi-line constructs.
      PATTERN = /
        (?<protected>
            ```.*?(?:```|\z)
          | ~~~.*?(?:~~~|\z)
          | `[^`\n]*`
          | \[[^\]\n]*\]\([^)\s]*\)
          | <?https?:\/\/[^\s<>]+>?
        )
        |
        (?<ref>(?<![A-Za-z0-9_])\#\d+)
      /mx

      # @param link_format [Format] the output link format
      def initialize(link_format)
        @link_format = link_format
      end

      # Scans +text+ once, replacing each `#NNNN` reference that is not
      # inside a protected region (code block, inline code, URL or markdown
      # link) with the link format's rendered string.
      # @param text [String] the outbound message body
      # @return [String]
      def format(text)
        text.gsub(PATTERN) do |match|
          next match if $~[:protected]

          raise "PATTERN matched neither :protected nor :ref for #{match.inspect}" unless $~[:ref]

          issue_id = $~[:ref].delete("#").to_i
          @link_format.render($~[:ref], issue_url(issue_id))
        end
      end

      private

      def issue_url(id)
        raise "Setting.host_name is blank; issue links cannot be generated" if Setting.host_name.blank?

        # Setting.host_name may embed a port and/or a path prefix
        # (e.g. "r.example.com:3000/redmine"); Mailer.default_url_options
        # already parses that into :host, :port and :script_name the way
        # the rest of Redmine expects, so reuse it instead of re-deriving it.
        Rails.application.routes.url_helpers.issue_url(id, **Mailer.default_url_options)
      end
    end
  end
end
