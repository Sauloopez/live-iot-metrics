defmodule LiveMetrics.Fixtures do
  @moduledoc """
  Builders for the test data shared by model and LiveView tests.
  """
  alias LiveMetrics.Repo

  alias LiveMetrics.Models.{
    Area,
    AreaBatch,
    BatchSensor,
    Nodes,
    Recipes,
    RecipeBatch,
    Sensor,
    SensorReading
  }

  def unique_mac do
    6
    |> :crypto.strong_rand_bytes()
    |> Base.encode16()
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.map_join(":", &Enum.join/1)
  end

  def node_fixture(attrs \\ %{}) do
    mac = attrs[:mac] || unique_mac()

    %Nodes{}
    |> Nodes.changeset(Map.merge(%{name: mac, mac: mac}, Map.new(attrs)))
    |> Repo.insert!()
  end

  def sensor_fixture(node, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, sensor} =
      Sensor.update_or_create(
        node,
        Map.get(attrs, :node_sensor_id, 1),
        Map.get(attrs, :sensor_type, "temperature"),
        Map.get(attrs, :precision, 1.0)
      )

    sensor
  end

  def area_fixture(attrs \\ %{}) do
    {:ok, area} =
      attrs
      |> Map.new()
      |> Enum.into(%{
        name: "Area #{System.unique_integer([:positive])}",
        description: "Test area"
      })
      |> Area.create_area()

    area
  end

  @doc "ranges: list of {sensor_type, min, max}"
  def recipe_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    ranges = Map.get(attrs, :ranges, [{"temperature", 20.0, 30.0}])

    {:ok, recipe} =
      Recipes.create(%{
        "name" => Map.get(attrs, :name, "Recipe #{System.unique_integer([:positive])}"),
        "description" => Map.get(attrs, :description, "Test recipe"),
        "property_ranges" =>
          Enum.map(ranges, fn {type, min, max} ->
            %{"sensor_type" => type, "min_value" => min, "max_value" => max}
          end)
      })

    recipe
  end

  def batch_fixture(area, recipe, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, batch} =
      RecipeBatch.create(%RecipeBatch{area_batch: %AreaBatch{area_id: area.id}}, %{
        name: Map.get(attrs, :name, "Batch #{System.unique_integer([:positive])}"),
        started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
        recipe_id: recipe.id
      })

    batch
  end

  def batch_sensor_fixture(batch, sensor, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, batch_sensor} =
      BatchSensor.create(%{
        recipe_batch_id: batch.id,
        sensor_id: sensor.id,
        min_value: Map.get(attrs, :min_value, 20.0),
        max_value: Map.get(attrs, :max_value, 30.0),
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        ended_at: Map.get(attrs, :ended_at)
      })

    batch_sensor
  end

  @doc "values: list of floats, one reading per second ending now"
  def readings_fixture(sensor, values) do
    now = DateTime.utc_now()
    count = length(values)

    rows =
      values
      |> Enum.with_index()
      |> Enum.map(fn {value, i} ->
        %{sensor_id: sensor.id, value: value, reading_time: DateTime.add(now, i - count, :second)}
      end)

    Repo.insert_all(SensorReading, rows)
  end
end
