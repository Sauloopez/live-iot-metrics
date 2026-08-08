defmodule LiveMetrics.Repo.Migrations.AddActiveToSensors do
  use Ecto.Migration

  def change do
    alter table("sensors") do
      add :active, :boolean, default: true, null: false
      add :inactivated_at, :timestamptz
    end
  end
end
