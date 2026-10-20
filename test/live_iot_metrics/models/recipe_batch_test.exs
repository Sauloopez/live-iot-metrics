defmodule LiveMetrics.Models.RecipeBatchTest do
  use LiveMetrics.DataCase, async: true

  import LiveMetrics.Fixtures
  alias LiveMetrics.Models.{BatchSensor, RecipeBatch}

  setup do
    area = area_fixture()
    recipe = recipe_fixture()
    %{area: area, recipe: recipe, batch: batch_fixture(area, recipe)}
  end

  test "a batch needs a name, a start time and a recipe", %{area: area} do
    struct = %RecipeBatch{area_batch: %LiveMetrics.Models.AreaBatch{area_id: area.id}}
    assert {:error, changeset} = RecipeBatch.create(struct, %{})
    assert %{name: [_], started_at: [_], recipe_id: [_]} = errors_on(changeset)
  end

  test "find_all_active_by_area/1 returns active batches with their sensors loaded", %{
    area: area,
    recipe: recipe,
    batch: batch
  } do
    sensor = sensor_fixture(node_fixture(), sensor_type: "light")
    batch_sensor_fixture(batch, sensor)

    ended = batch_fixture(area, recipe)
    ended |> Ecto.Changeset.change(ended_at: DateTime.utc_now()) |> Repo.update!()
    batch_fixture(area_fixture(), recipe)

    assert [found] = RecipeBatch.find_all_active_by_area(area.id)
    assert found.id == batch.id
    assert found.recipe.id == recipe.id
    # The dashboard card reads the sensor type of every batch sensor
    assert [%{sensor: %{sensor_type: "light"}}] = found.batch_sensors
  end

  test "find_by_id/1 preloads recipe ranges and sensor nodes", %{batch: batch} do
    node = node_fixture()
    batch_sensor_fixture(batch, sensor_fixture(node))

    found = RecipeBatch.find_by_id(batch.id)
    assert [_] = found.recipe.property_ranges
    assert [%{sensor: %{node: %{id: node_id}}}] = found.batch_sensors
    assert node_id == node.id
  end

  test "end_tracking_for_node/2 only ends the given node's active sensors", %{batch: batch} do
    node = node_fixture()
    other = node_fixture()
    batch_sensor_fixture(batch, sensor_fixture(node, node_sensor_id: 1))
    batch_sensor_fixture(batch, sensor_fixture(node, node_sensor_id: 2))
    batch_sensor_fixture(batch, sensor_fixture(other))

    assert {2, _} = BatchSensor.end_tracking_for_node(batch.id, node.id)

    ended =
      RecipeBatch.find_by_id(batch.id).batch_sensors
      |> Enum.map(&{&1.sensor.node_id, not is_nil(&1.ended_at)})

    assert {other.id, false} in ended
    assert Enum.count(ended, &(&1 == {node.id, true})) == 2
  end

  test "ending a batch ends its active sensors and keeps earlier end times", %{batch: batch} do
    earlier = ~U[2026-01-01 10:00:00Z]
    active = batch_sensor_fixture(batch, sensor_fixture(node_fixture()))
    detached = batch_sensor_fixture(batch, sensor_fixture(node_fixture()), ended_at: earlier)

    ended_at = DateTime.utc_now() |> DateTime.truncate(:second)
    # recipe_batch stores microseconds, batch_sensors seconds
    batch |> Ecto.Changeset.change(ended_at: %{ended_at | microsecond: {0, 6}}) |> Repo.update!()

    assert Repo.get!(BatchSensor, active.id).ended_at == ended_at
    assert Repo.get!(BatchSensor, detached.id).ended_at == earlier
  end

  test "delete/1 removes the batch and its tracking but keeps sensor readings", %{batch: batch} do
    sensor = sensor_fixture(node_fixture())
    batch_sensor_fixture(batch, sensor)
    readings_fixture(sensor, [1.0, 2.0])

    assert {:ok, _} = RecipeBatch.delete(batch)

    assert RecipeBatch.find_by_id(batch.id) == nil
    assert Repo.all(BatchSensor) == []
    assert Repo.all(LiveMetrics.Models.AreaBatch) == []
    assert Repo.aggregate(LiveMetrics.Models.SensorReading, :count) == 2
  end
end
