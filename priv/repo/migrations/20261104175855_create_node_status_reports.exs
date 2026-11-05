defmodule LiveMetrics.Repo.Migrations.CreateNodeStatusReports do
  use Ecto.Migration

  # Health reports sent by the nodes (the serial `status` command today; CoAP and LoRa later).
  # One row per report so battery and counters can be followed over time.
  def change do
    create table("node_status_reports") do
      add :mac, :string, null: false
      add :variant, :string
      add :transport, :string, null: false
      add :reported_at, :timestamptz, null: false
      add :battery_mv, :integer
      add :battery_percent, :integer
      add :clock_ts, :bigint
      add :clock_valid, :boolean
      add :next_seq, :bigint
      add :acked_seq, :bigint
      add :pending, :bigint
      add :storage_free_bytes, :bigint
      add :storage_total_bytes, :bigint
      add :failed_writes, :bigint
      add :boot_count, :bigint
      add :awake_ms, :bigint
      add :reset_reason, :integer
    end

    create index("node_status_reports", [:mac, :reported_at])
  end
end
