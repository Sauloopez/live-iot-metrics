defmodule LiveMetrics.Models.NodesTest do
  use LiveMetrics.DataCase

  test "do no insert nodes with bad MAC address" do
    case LiveMetrics.Models.Nodes.get_or_insert("1234") do
      {:error, changeset} ->
        IO.inspect(changeset)
        assert changeset != nil

      {:ok, new_node} ->
        assert new_node == nil
    end
  end

  test "get or insert node" do
    case LiveMetrics.Models.Nodes.get_or_insert("00:1A:2B:3C:4D:5E") do
      {:error, changeset} ->
        IO.inspect(changeset)
        assert changeset == nil

      {:ok, new_node} ->
        assert new_node != nil
    end
  end
end
