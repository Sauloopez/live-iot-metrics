defmodule LiveMetrics.Models.AreaTest do
  use LiveMetrics.DataCase, async: true

  import LiveMetrics.Fixtures
  alias LiveMetrics.Models.Area

  test "create_area/1 requires name and description" do
    assert {:error, changeset} = Area.create_area(%{})
    assert %{name: [_], description: [_]} = errors_on(changeset)

    assert {:ok, %Area{name: "Greenhouse"}} =
             Area.create_area(%{name: "Greenhouse", description: "North side"})
  end

  test "find_all_sorted_by_name/0" do
    area_fixture(name: "Zeta")
    area_fixture(name: "Alpha")

    assert ["Alpha", "Zeta"] = Enum.map(Area.find_all_sorted_by_name(), & &1.name)
  end
end
