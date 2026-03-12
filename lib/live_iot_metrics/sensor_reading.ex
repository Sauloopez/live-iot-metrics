defmodule LiveMetrics.SensorReading do
  alias LiveMetrics.Repo
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "sensor_readings" do
    belongs_to :sensor, LiveMetrics.Sensor, type: :binary_id
    field :value, :float
    field :reading_time, :utc_datetime_usec
  end

  @doc false
  def changeset(sensor_reading, attrs) do
    sensor_reading
    |> cast(attrs, [:sensor_id, :value, :reading_time])
    |> validate_required([:sensor_id, :value, :reading_time])
  end

  def create_reading(attrs) do
    %LiveMetrics.SensorReading{}
    |> changeset(attrs)
    |> Repo.insert()
    |> broadcast_reading()
  end

  defp broadcast_reading({:ok, reading} = result) do
    reading = Repo.preload(reading, :sensor)

    Phoenix.PubSub.broadcast(
      LiveMetrics.PubSub,
      "sensor_readings",
      {:new_reading, reading}
    )

    result
  end

  defp broadcast_reading(error), do: error
end
