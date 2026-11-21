# frozen_string_literal: true

module RedmineAiHelper
  module TestSupport
    # Builds RubyLLM::ConnectionError objects shaped like the ones RubyLLM 2.2's
    # ErrorMiddleware raises: the Faraday error is the Ruby `cause`.
    module ConnectionErrors
      # The failure kinds build_connection_error accepts.
      KINDS = %i[read_timeout connect_timeout refused ssl_error].freeze

      # @param kind [Symbol] one of KINDS
      # @return [RubyLLM::ConnectionError]
      # @raise [ArgumentError] when kind is not one of KINDS
      def build_connection_error(kind)
        raise ArgumentError, "unknown connection error kind: #{kind.inspect}" unless KINDS.include?(kind)

        # Ruby sets #cause only while an exception is being handled, so the
        # ConnectionError has to be raised from inside the rescue of the Faraday
        # error. Do not "simplify" this into ConnectionError.new(...).
        begin
          raise_faraday_error(kind)
        rescue Faraday::Error => e
          begin
            raise RubyLLM::ConnectionError, e.message
          rescue RubyLLM::ConnectionError => wrapped
            wrapped
          end
        end
      end

      private

      def raise_faraday_error(kind)
        case kind
        when :read_timeout
          raise Faraday::TimeoutError, "Net::ReadTimeout"
        when :connect_timeout
          raise Faraday::ConnectionFailed, Net::OpenTimeout.new("execution expired")
        when :refused
          raise Faraday::ConnectionFailed, Errno::ECONNREFUSED.new("Connection refused")
        when :ssl_error
          raise Faraday::SSLError, "SSL_connect returned=1 errno=0"
        end
      end
    end
  end
end
