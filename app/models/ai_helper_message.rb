# frozen_string_literal: true

# AiHelperMessage model for managing AI Helper messages
class AiHelperMessage < ApplicationRecord
  # Allowed values for the +role+ column. Messages with +role "context"+ are
  # imported from a chat channel and merged into a user message before LLM
  # handover (see AiHelperConversation#messages_for_openai).
  ROLES = [ "user", "assistant", "context" ].freeze

  # Role for messages imported from an external chat channel.
  CONTEXT_ROLE = "context"

  belongs_to :conversation, class_name: "AiHelperConversation", touch: true
  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  # Stored form of the web search sources; write it through #web_citations=.
  serialize :citations, coder: JSON
  validate :validate_citations

  # The web search sources of this answer.
  # @return [Array<RedmineAiHelper::WebCitation>] empty when there are none
  def web_citations
    (citations || []).map { |hash| RedmineAiHelper::WebCitation.from_h(hash) }
  end

  # Store the web search sources of this answer.
  # @param list [Array<RedmineAiHelper::WebCitation>] the sources; an empty list stores nil
  # @raise [ArgumentError] when list is not an Array, or an element is not a RedmineAiHelper::WebCitation
  def web_citations=(list)
    raise ArgumentError, "list must be an Array" unless list.is_a?(Array)
    unless list.all? { |citation| citation.is_a?(RedmineAiHelper::WebCitation) }
      raise ArgumentError, "every element must be a RedmineAiHelper::WebCitation"
    end

    self.citations = list.empty? ? nil : list.map(&:to_h)
  end

  private

  # The stored citations must be nil or a list of hashes with a String "url",
  # so that #web_citations can read every saved row.
  def validate_citations
    return if citations.nil?
    return if citations.is_a?(Array) && citations.all? { |hash| hash.is_a?(Hash) && hash["url"].is_a?(String) }

    errors.add(:citations, :invalid)
  end
end
