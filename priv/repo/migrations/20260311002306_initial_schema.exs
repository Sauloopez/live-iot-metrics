defmodule LiveMetrics.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def change do
    create table("areas", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :name, :string
      add :description, :string
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create unique_index("areas", :name)

    create table("nodes", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :area_id, references("areas", on_delete: :delete_all, type: :binary_id), null: true
      add :name, :string, unique: true
      add :mac, :binary, unique: true
      add :description, :string
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create unique_index("nodes", :name)
    create unique_index("nodes", :mac)

    create table("sensors", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :node_id, references("nodes", on_delete: :delete_all, type: :binary_id), null: false
      add :node_sensor_id, :integer
      add :sensor_type, :string
      add :precision, :float, check: "precision > 0 AND precision < 1"
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create index("sensors", :node_id)
    create unique_index("sensors", [:node_id, :node_sensor_id])

    create table("sensor_readings", primary_key: false) do
      add :sensor_id, references("sensors", on_delete: :delete_all, type: :binary_id), null: false
      add :value, :float
      add :reading_time, :timestamptz
    end

    execute "SELECT create_hypertable('sensor_readings', 'reading_time');"

    create index("sensor_readings", [:sensor_id, :reading_time])
  end
end
