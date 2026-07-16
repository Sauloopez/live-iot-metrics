defmodule LiveMetrics.Models.BatchSensor do
  use LiveMetrics.BaseSchema
  alias LiveMetrics.Models.{RecipeBatch, Sensor}

  import Ecto.Changeset

  schema "batch_sensors" do
    field :min_value, :float
    field :max_value, :float
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :recipe_batch, RecipeBatch, foreign_key: :recipe_batch_id
    belongs_to :sensor, Sensor
  end

  def changeset(property_range, attrs) do
    property_range
    |> cast(attrs, [:min_value, :max_value, :recipe_batch_id, :sensor_id, :started_at, :ended_at])
    |> validate_required([
      :min_value,
      :max_value,
      :recipe_batch_id,
      :sensor_id,
      :started_at
    ])
  end
end
