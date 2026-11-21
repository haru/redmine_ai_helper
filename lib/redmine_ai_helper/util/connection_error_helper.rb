# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Classifies and describes the errors RubyLLM raises when the transport to
    # an LLM backend fails.
    #
    # RubyLLM 2.2's ErrorMiddleware wraps Faraday::ConnectionFailed,
    # Faraday::TimeoutError and Faraday::SSLError in RubyLLM::ConnectionError
    # and keeps the Faraday error as the Ruby +cause+. Any other Faraday error
    # is not wrapped and is treated as a defect by the callers (see ADR-074).
    module ConnectionErrorHelper
      class << self
        # Whether the error is a read timeout or a connect timeout.
        # @param error [Exception] the error raised by an LLM call
        # @return [Boolean] true only for a RubyLLM::ConnectionError that reports #timeout?
        def timeout?(error)
          error.is_a?(RubyLLM::ConnectionError) && error.timeout?
        end

        # One-line description of an error for logs: the error class and message,
        # followed by the class of its cause (and of the exception a Faraday
        # error wraps) so a refused connection can be told from a DNS failure.
        # @param error [Exception] the error to describe
        # @return [String] the description
        def describe(error)
          text = "#{error.class}: #{error.message}"
          cause = error.cause
          return text if cause.nil?

          text += " (cause: #{cause.class}"
          wrapped = cause.respond_to?(:wrapped_exception) ? cause.wrapped_exception : nil
          text += ", wrapped: #{wrapped.class}" if wrapped
          "#{text})"
        end
      end
    end
  end
end
