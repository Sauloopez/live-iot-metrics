defmodule LiveMetrics.Models.SensorReading do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "sensor_readings" do
    belongs_to :sensor, LiveMetrics.Models.Sensor, type: :binary_id
    field :value, :float
    field :reading_time, :utc_datetime_usec
  end

  @doc false
  def changeset(sensor_reading, attrs) do
    sensor_reading
    |> cast(attrs, [:sensor_id, :value, :reading_time])
    |> validate_required([:sensor_id, :value, :reading_time])
  end
end
