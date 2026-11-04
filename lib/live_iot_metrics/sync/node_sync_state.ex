defmodule LiveMetrics.Sync.NodeSyncState do
  @moduledoc """
  How far the server got synchronizing a node that stores measurements locally.

  `acked_seq` is the contiguous watermark: every measurement of the node up to it is stored.
  """
  use Ecto.Schema

  schema "node_sync_states" do
    field :mac, :string
    field :acked_seq, :integer, default: 0
    field :received_count, :integer, default: 0
    field :skipped_without_time, :integer, default: 0
    field :last_sync_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
