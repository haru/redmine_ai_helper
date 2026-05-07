# frozen_string_literal: true

# AiHelperVectorData model for storing vector data related to Issue data
class AiHelperVectorData < ApplicationRecord
  validates :object_id, presence: true
  validates :index, presence: true
  validates :uuid, presence: true
end
