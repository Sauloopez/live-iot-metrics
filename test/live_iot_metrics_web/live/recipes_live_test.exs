defmodule LiveMetricsWeb.RecipesLiveTest do
  use LiveMetricsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LiveMetrics.Fixtures

  alias LiveMetrics.Models.Recipes

  defp recipe_params(name, type, min, max) do
    %{
      name: name,
      description: "Test",
      property_ranges: %{"0" => %{sensor_type: type, min_value: min, max_value: max}}
    }
  end

  test "lists recipes with their ranges", %{conn: conn} do
    recipe = recipe_fixture(name: "Basil", ranges: [{"light", 30, 90}])
    {:ok, view, _html} = live(conn, ~p"/recipes")

    assert has_element?(view, "#recipes_table", "Basil")
    assert has_element?(view, "#recipes_table", "light")
    assert has_element?(view, "#edit-recipe-#{recipe.id}")
  end

  test "creates a recipe with a free-text sensor type", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes")

    view |> element("#btn-add-recipe") |> render_click()

    view
    |> form("#recipe-form", recipe: recipe_params("Soil", "  Soil_Moisture ", "40.5", "80"))
    |> render_submit()

    refute has_element?(view, "#recipe-form")
    assert has_element?(view, "#recipes_table", "Soil")

    assert [%{property_ranges: [%{sensor_type: "soil_moisture", min_value: 40.5}]}] =
             Recipes.find_all()
  end

  test "shows validation errors for invalid types and ranges", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes")
    view |> element("#btn-add-recipe") |> render_click()

    html =
      view
      |> form("#recipe-form", recipe: recipe_params("Bad", "bad type!", "90", "30"))
      |> render_change()

    assert html =~ "use lowercase letters, numbers and underscores"
    assert html =~ "The min value must be minor of the max"
  end

  test "suggests preset types and the ones reported by nodes", %{conn: conn} do
    sensor_fixture(node_fixture(), sensor_type: "co2")
    {:ok, view, _html} = live(conn, ~p"/recipes")

    view |> element("#btn-add-recipe") |> render_click()

    assert has_element?(view, "#recipe-sensor-types option[value='soil_moisture']")
    assert has_element?(view, "#recipe-sensor-types option[value='co2']")
  end

  test "editing keeps the stored types and saves changes", %{conn: conn} do
    recipe = recipe_fixture(name: "Basil", ranges: [{"air_humidity", 40, 70}])
    {:ok, view, _html} = live(conn, ~p"/recipes")

    view |> element("#edit-recipe-#{recipe.id}") |> render_click()

    # Regression: types outside a fixed list used to render as "Pick a type..."
    assert has_element?(
             view,
             "#recipe-form input[name='recipe[property_ranges][0][sensor_type]'][value='air_humidity']"
           )

    view
    |> form("#recipe-form", recipe: %{property_ranges: %{"0" => %{max_value: "75"}}})
    |> render_submit()

    assert [%{max_value: 75.0}] = Recipes.find_by_id(recipe.id).property_ranges
  end

  test "adds another range row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes")
    view |> element("#btn-add-recipe") |> render_click()

    view |> element("#btn-add-range") |> render_click()

    assert has_element?(view, "input[name='recipe[property_ranges][1][sensor_type]']")
  end

  describe "deleting" do
    test "asks for confirmation and deletes on confirm", %{conn: conn} do
      recipe = recipe_fixture(name: "Basil")
      {:ok, view, _html} = live(conn, ~p"/recipes")

      view |> element("#delete-recipe-#{recipe.id}") |> render_click()
      assert has_element?(view, "#delete-recipe-dialog", "Basil")
      # Nothing is deleted until the user confirms
      assert Recipes.find_by_id(recipe.id)

      view |> element("#delete-recipe-dialog-confirm") |> render_click()

      refute has_element?(view, "#delete-recipe-dialog")
      refute has_element?(view, "#edit-recipe-#{recipe.id}")
      assert render(view) =~ "Recipe &quot;Basil&quot; deleted"
      assert Recipes.find_by_id(recipe.id) == nil
    end

    test "cancel keeps the recipe", %{conn: conn} do
      recipe = recipe_fixture()
      {:ok, view, _html} = live(conn, ~p"/recipes")

      view |> element("#delete-recipe-#{recipe.id}") |> render_click()
      view |> element("#delete-recipe-dialog-cancel") |> render_click()

      refute has_element?(view, "#delete-recipe-dialog")
      assert has_element?(view, "#edit-recipe-#{recipe.id}")
    end

    test "Escape closes the dialog", %{conn: conn} do
      recipe = recipe_fixture()
      {:ok, view, _html} = live(conn, ~p"/recipes")

      view |> element("#delete-recipe-#{recipe.id}") |> render_click()

      view |> element("#delete-recipe-dialog") |> render_keydown(%{"key" => "Escape"})

      refute has_element?(view, "#delete-recipe-dialog")
    end

    test "a recipe used by batches can not be deleted", %{conn: conn} do
      recipe = recipe_fixture()
      batch_fixture(area_fixture(), recipe)
      {:ok, view, _html} = live(conn, ~p"/recipes")

      view |> element("#delete-recipe-#{recipe.id}") |> render_click()

      assert has_element?(view, "#delete-recipe-dialog", "used by 1 production batch")
      refute has_element?(view, "#delete-recipe-dialog-confirm")
    end
  end
end
