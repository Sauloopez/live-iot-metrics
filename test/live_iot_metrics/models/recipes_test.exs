defmodule LiveMetrics.Models.RecipesTest do
  use LiveMetrics.DataCase, async: true

  import LiveMetrics.Fixtures
  alias LiveMetrics.Models.Recipes

  defp range(type, min, max), do: %{"sensor_type" => type, "min_value" => min, "max_value" => max}

  test "create/1 stores the property ranges" do
    {:ok, recipe} =
      Recipes.create(%{
        "name" => "Basil",
        "property_ranges" => [range("temperature", 18, 30), range("light", 30, 90)]
      })

    assert recipe |> Map.get(:property_ranges) |> length() == 2
  end

  test "a recipe needs at least one range" do
    assert {:error, changeset} = Recipes.create(%{"name" => "Empty", "property_ranges" => []})
    assert errors_on(changeset).property_ranges
  end

  test "sensor types are normalized to match what nodes report" do
    {:ok, recipe} =
      Recipes.create(%{
        "name" => "Soil",
        "property_ranges" => [range("  Soil_Moisture ", 40, 80)]
      })

    assert [%{sensor_type: "soil_moisture"}] = recipe.property_ranges
  end

  test "rejects types the nodes can not report" do
    {:error, changeset} =
      Recipes.create(%{"name" => "Bad", "property_ranges" => [range("soil moisture!", 1, 2)]})

    assert [%{sensor_type: [_]}] = errors_on(changeset).property_ranges
  end

  test "min must be lower than max" do
    {:error, changeset} =
      Recipes.create(%{"name" => "Bad", "property_ranges" => [range("light", 90, 30)]})

    assert [%{min_value: ["The min value must be minor of the max"]}] =
             errors_on(changeset).property_ranges
  end

  test "update/2 replaces the ranges" do
    recipe = recipe_fixture(ranges: [{"temperature", 20, 30}, {"light", 30, 90}])

    {:ok, updated} =
      Recipes.update(recipe, %{"property_ranges" => [range("soil_moisture", 40, 80)]})

    assert [%{sensor_type: "soil_moisture"}] = Recipes.find_by_id(updated.id).property_ranges
  end

  test "find_select_options/0 returns {name, id} tuples" do
    recipe = recipe_fixture(name: "Mint")
    assert {"Mint", recipe.id} in Recipes.find_select_options()
  end

  describe "delete/1" do
    test "deletes an unused recipe with its ranges" do
      recipe = recipe_fixture()
      assert {:ok, _} = Recipes.delete(recipe)
      assert Recipes.find_by_id(recipe.id) == nil
      assert Repo.all(LiveMetrics.Models.PropertyRange) == []
    end

    test "keeps recipes used by batches instead of cascading to them" do
      recipe = recipe_fixture()
      batch_fixture(area_fixture(), recipe)
      batch_fixture(area_fixture(), recipe)

      assert Recipes.delete(recipe) == {:error, {:in_use, 2}}
      assert Recipes.find_by_id(recipe.id)
    end
  end
end
