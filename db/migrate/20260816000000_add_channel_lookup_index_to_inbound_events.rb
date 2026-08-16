# frozen_string_literal: true

class AddChannelLookupIndexToInboundEvents < ActiveRecord::Migration[7.2]
  def change
    add_index :ai_helper_inbound_events,
              [ :channel_type, :channel_id, :received_at ],
              name: "index_inbound_events_on_channel_lookup"
  end
end
