# Creates an area, recipe, batch tracking the node's sensors, and 20 minutes of history.
# Run with: mix run --no-start /tmp/livemetrics-e2e/seed.exs <mac>
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sql)
{:ok, _} = LiveMetrics.Repo.start_link()

alias LiveMetrics.Repo
alias LiveMetrics.Models.{Area, AreaBatch, BatchSensor, Nodes, Recipes, RecipeBatch, Sensor, SensorReading}
import Ecto.Query

[mac] = System.argv()
ranges = %{"temperature" => {20.0, 30.0}, "air_humidity" => {40.0, 70.0}, "light" => {30.0, 90.0}}

node = Repo.get_by!(Nodes, mac: mac)
sensors = Repo.all(from s in Sensor, where: s.node_id == ^node.id)

area =
  Repo.get_by(Area, name: "Invernadero E2E") ||
    elem(Area.create_area(%{name: "Invernadero E2E", description: "Playwright test area"}), 1)

{:ok, recipe} =
  Recipes.create(%{
    name: "Germinación E2E #{System.os_time(:second)}",
    description: "Seeded by the e2e test",
    property_ranges:
      Enum.map(ranges, fn {type, {min, max}} -> %{sensor_type: type, min_value: min, max_value: max} end)
  })

now = DateTime.utc_now()

{:ok, batch} =
  RecipeBatch.create(%RecipeBatch{area_batch: %AreaBatch{area_id: area.id}}, %{
    name: "Lote E2E",
    started_at: DateTime.add(now, -30, :minute),
    recipe_id: recipe.id
  })

{:ok, _} =
  BatchSensor.create_many(
    for s <- sensors, {min, max} = ranges[s.sensor_type] do
      %{
        recipe_batch_id: batch.id,
        sensor_id: s.id,
        min_value: min,
        max_value: max,
        started_at: DateTime.add(now, -30, :minute) |> DateTime.truncate(:second)
      }
    end
  )

# 40 readings per sensor, one every 30s over the last 20 minutes, with an excursion
history =
  for s <- sensors, i <- 1..40 do
    base =
      case s.sensor_type do
        "temperature" -> 25.0 + 3.5 * :math.sin(i / 5) + if(i in 18..20, do: 6.0, else: 0.0)
        "air_humidity" -> 55.0 + 10 * :math.cos(i / 7) - if(i in 30..33, do: 14.0, else: 0.0)
        "light" -> 60.0 + 20 * :math.sin(i / 9)
      end

    %{
      sensor_id: s.id,
      value: base + :rand.uniform() - 0.5,
      reading_time: DateTime.add(now, -(41 - i) * 30, :second)
    }
  end

{count, _} = Repo.insert_all(SensorReading, history)
IO.puts("history readings: #{count}")
IO.puts("BATCH_ID=#{batch.id}")
