defmodule LiveMetricsWeb.DashboardLiveTest do
  use LiveMetricsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LiveMetrics.Fixtures

  describe "without areas" do
    test "shows the empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#no-areas")
      refute has_element?(view, "#btn-start-batch")
    end

    test "creates the first area", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#btn-create-first-area") |> render_click()

      view
      |> form("#add-area-form", %{name: "Greenhouse 1", description: "North side"})
      |> render_submit()

      [area] = LiveMetrics.Models.Area.find_all_sorted_by_name()
      assert has_element?(view, "#area-tab-#{area.id}.tab-active", "Greenhouse 1")
      refute has_element?(view, "#no-areas")
      refute has_element?(view, "#add-area-form")
    end
  end

  describe "with areas and batches" do
    setup do
      greenhouse = area_fixture(name: "A Greenhouse")
      nursery = area_fixture(name: "B Nursery")
      recipe = recipe_fixture(name: "Basil", ranges: [{"light", 30, 90}])

      basil = batch_fixture(greenhouse, recipe, name: "Basil batch")
      batch_sensor_fixture(basil, sensor_fixture(node_fixture(), sensor_type: "light"))

      seedlings = batch_fixture(nursery, recipe, name: "Seedlings")

      %{
        greenhouse: greenhouse,
        nursery: nursery,
        recipe: recipe,
        basil: basil,
        seedlings: seedlings
      }
    end

    test "shows the active batches of the first area with their sensors", %{
      conn: conn,
      greenhouse: greenhouse,
      basil: basil,
      seedlings: seedlings
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#area-tab-#{greenhouse.id}.tab-active")
      assert has_element?(view, "#batch-card-#{basil.id}", "Basil batch")
      # Regression: the card reads batch_sensor.sensor, which must be preloaded
      assert has_element?(view, "#batch-card-#{basil.id}", "light")
      refute has_element?(view, "#batch-card-#{seedlings.id}")
    end

    test "switching areas shows that area's batches", %{
      conn: conn,
      nursery: nursery,
      basil: basil,
      seedlings: seedlings
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#area-tab-#{nursery.id}") |> render_click()

      assert has_element?(view, "#area-tab-#{nursery.id}.tab-active")
      assert has_element?(view, "#batch-card-#{seedlings.id}")
      refute has_element?(view, "#batch-card-#{basil.id}")
    end

    test "ended batches are not listed", %{conn: conn, basil: basil} do
      basil
      |> Ecto.Changeset.change(ended_at: DateTime.utc_now())
      |> LiveMetrics.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#batch-card-#{basil.id}")
    end

    test "starts a batch in the active area", %{conn: conn, recipe: recipe} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#btn-start-batch") |> render_click()

      view
      |> form("#start-batch-form",
        recipe_batch: %{name: "Mint batch", recipe_id: recipe.id, started_at: "2026-10-20T08:00"}
      )
      |> render_submit()

      assert render(view) =~ "Reading started successfully"
      assert has_element?(view, "#area-batches", "Mint batch")
    end

    test "a batch card opens the batch detail", %{conn: conn, basil: basil} do
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, detail, _html} =
        view |> element("#open-batch-#{basil.id}") |> render_click() |> follow_redirect(conn)

      assert has_element?(detail, "#btn-attach-node")
    end
  end
end
