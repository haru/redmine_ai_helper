# frozen_string_literal: true

# Persistent queue row for one webhook-delivered chat event, normalized by an
# inbound adapter at receive time. The web process inserts pending rows here;
# the resident gateway process polls and claims them (data-model.md).
class CreateAiHelperInboundEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_helper_inbound_events do |t|
      t.string :channel_type, null: false
      t.string :event_key, null: false
      t.text :text, null: false
      t.string :channel_id, null: false
      t.string :thread_key, null: false
      t.string :message_ts
      t.boolean :dm, null: false, default: false
      t.boolean :in_thread, null: false, default: false
      t.text :reply_metadata
      t.string :status, null: false, default: "pending", limit: 20
      t.datetime :received_at, null: false
      t.timestamps
    end

    add_index :ai_helper_inbound_events, [ :channel_type, :event_key ],
              unique: true, name: "index_ai_helper_inbound_events_unique"
    add_index :ai_helper_inbound_events, [ :channel_type, :status, :received_at ],
              name: "index_ai_helper_inbound_events_on_poll"
  end
end
