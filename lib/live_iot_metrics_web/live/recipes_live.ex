defmodule LiveMetricsWeb.RecipesLive do
  require Logger
  alias LiveMetricsWeb.Components.RecipeModal
  alias LiveMetrics.Models.Recipes
  use LiveMetricsWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    recipes = Recipes.find_all()
    socket = socket
    |> assign(:recipes, recipes)
    |> assign(:modal_is_open, false)
    |> assign(:editing_recipe, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LiveMetricsWeb.Layouts.app flash={@flash}>
      <div class="flex justify-between items-center mb-10">
        <h1 class="text-3xl font-bold text-primary">Recipes</h1>
        <button phx-click="show_add_recipe" class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="w-4 h-4 mr-2" /> Add Recipe
        </button>
      </div>
      <.table id="recipes_table" rows={@recipes}>
        <:col :let={recipe} label="Recipe name">{recipe.name}</:col>
        <:col :let={recipe} label="Ranges">
          <%= for range <- recipe.property_ranges do %>
            <div class="badge badge-primary flex items-center my-2">
              <span class="text-sm"><%= range.sensor_type %></span>
              <span class="text-sm">: <%= range.min_value %> - <%= range.max_value %></span>
            </div>
          <% end %>
        </:col>
        <:col :let={recipe} label="Actions">
          <button
            class="btn btn-sm btn-ghost"
            phx-click="edit_recipe"
            phx-value-id={recipe.id}
          >
            <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
          </button>
        </:col>
      </.table>
      <%=if @modal_is_open do %>
        <.live_component id="recipe_modal" editing_recipe={@editing_recipe} module={RecipeModal} />
      <% end %>
    </LiveMetricsWeb.Layouts.app>
    """
  end

  @impl true
  def handle_event("show_add_recipe", _, socket) do
    {:noreply, assign(socket, :modal_is_open, true)}
  end

  @impl true
  def handle_event("edit_recipe", %{"id" => id}, socket) do
    recipe = Recipes.find_by_id(id)
    {:noreply, socket
      |>assign(:editing_recipe, recipe)
      |>assign( :modal_is_open, true)
    }
  end

  @impl true
  def handle_event("close_add_recipe", _, socket) do
    {:noreply, socket |>assign(:editing_recipe, nil)|> assign(:modal_is_open, false)}
  end

  @impl true
  def handle_info({:recipe_saved, _recipe}, socket) do
    socket = socket
    |> assign(:recipes, Recipes.find_all())
    |> assign(:modal_is_open, false)
    |> assign(:editing_recipe, nil)
    {:noreply, socket}
  end
end
