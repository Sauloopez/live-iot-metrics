defmodule LiveMetrics.Models.NodesTest do
  use LiveMetrics.DataCase, async: true

  import LiveMetrics.Fixtures
  alias LiveMetrics.Models.Nodes

  describe "changeset/2" do
    test "requires a valid MAC address" do
      changeset = Nodes.changeset(%Nodes{}, %{name: "node", mac: "1234"})
      assert "has invalid format" in errors_on(changeset).mac
    end

    test "accepts colon and dash separated MACs" do
      assert Nodes.changeset(%Nodes{}, %{name: "a", mac: "00:1A:2B:3C:4D:5E"}).valid?
      assert Nodes.changeset(%Nodes{}, %{name: "b", mac: "00-1A-2B-3C-4D-5E"}).valid?
    end
  end

  test "find_all/0 sorts by name and preloads sensors" do
    b = node_fixture(name: "b-node")
    a = node_fixture(name: "a-node")
    sensor_fixture(b, node_sensor_id: 1)

    assert [%{id: first_id, sensors: []}, %{id: second_id, sensors: [_]}] = Nodes.find_all()
    assert {first_id, second_id} == {a.id, b.id}
  end

  test "find_available/0 excludes nodes tracked by an active batch" do
    tracked = node_fixture()
    released = node_fixture()
    idle = node_fixture()

    batch = batch_fixture(area_fixture(), recipe_fixture())
    batch_sensor_fixture(batch, sensor_fixture(tracked))

    batch_sensor_fixture(batch, sensor_fixture(released),
      ended_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    available = Nodes.find_available() |> Enum.map(& &1.id) |> MapSet.new()

    refute tracked.id in available
    assert released.id in available
    assert idle.id in available
  end
end
