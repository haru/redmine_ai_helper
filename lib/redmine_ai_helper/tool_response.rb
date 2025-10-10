# frozen_string_literal: true
module RedmineAiHelper
  # Class to store responses from tools
  # TODO: May not be needed
  class ToolResponse
    attr_reader :status, :value, :error
    # Success status constant
    STATUS_SUCCESS = "success"
    # Error status constant
    STATUS_ERROR = "error"

    def initialize(response = {})
      @status = response[:status] || response["status"]
      @value = response[:value] || response["value"]
      @error = response[:error] || response["error"]
    end

    # Convert to JSON
    # @return [String] JSON representation
    def to_json(*_args)
      to_hash().to_json
    end

    # Convert to hash
    # @return [Hash] Hash representation
    def to_hash
      { status: status, value: value, error: error }
    end

    # Convert to hash (alias)
    # @return [Hash] Hash representation
    def to_h
      to_hash
    end

    # Convert to string
    # @return [String] String representation
    def to_s
      to_hash.to_s
    end

    def is_success?
      status == ToolResponse::STATUS_SUCCESS
    end

    def is_error?
      !is_success?
    end

    # Create an error response
    # @param error [String] Error message
    # @return [ToolResponse] Error response
    def self.create_error(error)
      ToolResponse.new(status: ToolResponse::STATUS_ERROR, error: error)
    end

    # Create a success response
    # @param value [Object] Response value
    # @return [ToolResponse] Success response
    def self.create_success(value)
      ToolResponse.new(status: ToolResponse::STATUS_SUCCESS, value: value)
    end
  end
end
