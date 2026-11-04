defmodule LiveMetrics.Repo.Migrations.CreateNodeSyncStates do
  use Ecto.Migration

  # Synchronization progress of each node that stores measurements locally. `acked_seq` is the
  # contiguous watermark: the server has every measurement of the node up to that seq, so it
  # is safe to confirm it to the node and to ignore anything at or below it (resends, or the
  # same storage extracted twice).
  def change do
    create table("node_sync_states") do
      add :mac, :string, null: false
      add :acked_seq, :bigint, null: false, default: 0
      add :received_count, :bigint, null: false, default: 0
      add :skipped_without_time, :bigint, null: false, default: 0
      add :last_sync_at, :timestamptz
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create unique_index("node_sync_states", [:mac])
  end
end
