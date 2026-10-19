defmodule LiveMetrics.Repo.Migrations.RecipeBatchSensors do
  use Ecto.Migration

  def change do
    alter table("batch_sensors") do
      add :min_value, :float
      add :max_value, :float
    end
  end
end
