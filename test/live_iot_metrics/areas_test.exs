defmodule LiveMetrics.Coap.AreasTest do
  use LiveMetrics.DataCase

  describe "areas" do
    test "create an area" do
      with {:ok, area} <-
             LiveMetrics.Models.Area.create_area(%{
               name: "test area",
               description: "This is test area"
             }) do
        assert area != nil
        assert area.name == "test area"
      end
    end

    test "create area and assign node" do
      with {:ok, device} <- LiveMetrics.Models.Nodes.get_or_insert("00:1A:2B:3C:4D:5E"),
           {:ok, area} <-
             LiveMetrics.Models.Area.create_area(%{
               name: "test area",
               description: "This is test area"
             }) do
        case LiveMetrics.Models.Area.add_node(area, [device]) do
          {:ok, updated_area} ->
            IO.puts("Added node to area")
            assert length(updated_area.nodes) == 1

          {:error, changeset} ->
            IO.puts("Error while addding node to area")
            IO.inspect(changeset.errors)
            assert changeset == nil
        end
      end
    end
  end
end
