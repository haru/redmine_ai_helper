# frozen_string_literal: true
module RedmineAiHelper
  # Class to store responses from tools
  # TODO: May not be needed
  class ToolResponse
    attr_reader :status, :value, :error
    ToolResponse::STATUS_SUCCESS = "success"
    ToolResponse::STATUS_ERROR = "error"

    def initialize(response = {})
      @status = response[:status] || response["status"]
      @value = response[:value] || response["value"]
      @error = response[:error] || response["error"]
    end

    def to_json
      to_hash().to_json
    end

    def to_hash
      { status: status, value: value, error: error }
    end

    def to_h
      to_hash
    end

    def to_s
      to_hash.to_s
    end

    def is_success?
      status == ToolResponse::STATUS_SUCCESS
    end

    def is_error?
      !is_success?
    end

    def self.create_error(error)
      ToolResponse.new(status: ToolResponse::STATUS_ERROR, error: error)
    end

    def self.create_success(value)
      ToolResponse.new(status: ToolResponse::STATUS_SUCCESS, value: value)
    end
  end
end
