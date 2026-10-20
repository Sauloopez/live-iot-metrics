defmodule LiveMetrics.Repo.Migrations.CreateNodeSensorConfigs do
  use Ecto.Migration

  # Sensor configuration pushed to the nodes over Web Serial. Intentionally not linked to
  # `sensors` or `sensor_readings`: it only mirrors what is stored on each node. The integer
  # id is the sensor id the firmware uses.
  def change do
    create table("node_sensor_configs") do
      add :mac, :string, null: false
      add :pin, :integer, null: false
      add :sensor_type, :string, null: false
      add :driver, :string, null: false, default: "analog"
      add :precision, :float, null: false, default: 1.0
      add :offset, :float, null: false, default: 0.0
      add :interval_ms, :integer, null: false, default: 10_000
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create index("node_sensor_configs", [:mac])
    create unique_index("node_sensor_configs", [:mac, :pin, :driver])
  end
end
