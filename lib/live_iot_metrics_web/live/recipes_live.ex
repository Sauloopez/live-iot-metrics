defmodule LiveMetricsWeb.RecipesLive do
  alias LiveMetricsWeb.Components.{ConfirmDialog, RecipeModal}
  alias LiveMetrics.Models.Recipes
  use LiveMetricsWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    recipes = Recipes.find_all()

    socket =
      socket
      |> assign(:recipes, recipes)
      |> assign(:modal_is_open, false)
      |> assign(:editing_recipe, nil)
      |> assign(:deleting, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LiveMetricsWeb.Layouts.app flash={@flash}>
      <div class="flex justify-between items-center mb-10">
        <h1 class="text-3xl font-bold text-primary">Recipes</h1>
        <button id="btn-add-recipe" phx-click="show_add_recipe" class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="w-4 h-4 mr-2" /> Add Recipe
        </button>
      </div>
      <.table id="recipes_table" rows={@recipes}>
        <:col :let={recipe} label="Recipe name">{recipe.name}</:col>
        <:col :let={recipe} label="Ranges">
          <%= for range <- recipe.property_ranges do %>
            <div class="badge badge-primary flex items-center my-2">
              <span class="text-sm">{range.sensor_type}</span>
              <span class="text-sm">: {range.min_value} - {range.max_value}</span>
            </div>
          <% end %>
        </:col>
        <:col :let={recipe} label="Actions">
          <.button
            id={"edit-recipe-#{recipe.id}"}
            type="button"
            class="btn btn-sm btn-ghost"
            phx-click="edit_recipe"
            phx-value-id={recipe.id}
          >
            <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
          </.button>
          <.button
            id={"delete-recipe-#{recipe.id}"}
            type="button"
            class="btn btn-sm btn-ghost text-error"
            phx-click="ask_delete_recipe"
            phx-value-id={recipe.id}
          >
            <.icon name="hero-trash" class="w-4 h-4" /> Delete
          </.button>
        </:col>
      </.table>
      <%= if @modal_is_open do %>
        <.live_component id="recipe_modal" editing_recipe={@editing_recipe} module={RecipeModal} />
      <% end %>

      <ConfirmDialog.confirm_dialog
        :if={@deleting}
        id="delete-recipe-dialog"
        title={
          if @deleting.batch_count > 0,
            do: "Recipe in use",
            else: "Delete recipe \"#{@deleting.recipe.name}\"?"
        }
        on_confirm="delete_recipe"
        on_cancel="cancel_delete_recipe"
        blocked={@deleting.batch_count > 0}
      >
        <%= if @deleting.batch_count > 0 do %>
          <p>
            <span class="font-semibold">{@deleting.recipe.name}</span>
            is used by {@deleting.batch_count} production batch(es).
            Delete those batches first; deleting the recipe would remove them too.
          </p>
        <% else %>
          <p>
            Its {length(@deleting.recipe.property_ranges)} sensor range(s) will be deleted.
            This can not be undone.
          </p>
        <% end %>
      </ConfirmDialog.confirm_dialog>
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

    {:noreply,
     socket
     |> assign(:editing_recipe, recipe)
     |> assign(:modal_is_open, true)}
  end

  @impl true
  def handle_event("close_add_recipe", _, socket) do
    {:noreply, socket |> assign(:editing_recipe, nil) |> assign(:modal_is_open, false)}
  end

  @impl true
  def handle_event("ask_delete_recipe", %{"id" => id}, socket) do
    recipe = Recipes.find_by_id(id)

    {:noreply,
     assign(socket, :deleting, %{recipe: recipe, batch_count: Recipes.count_batches(recipe)})}
  end

  @impl true
  def handle_event("cancel_delete_recipe", _params, socket) do
    {:noreply, assign(socket, :deleting, nil)}
  end

  @impl true
  def handle_event("delete_recipe", _params, socket) do
    %{recipe: recipe} = socket.assigns.deleting

    socket =
      case Recipes.delete(recipe) do
        {:ok, _} ->
          put_flash(socket, :info, "Recipe \"#{recipe.name}\" deleted")

        {:error, {:in_use, count}} ->
          put_flash(socket, :error, "Recipe is used by #{count} batch(es) and was not deleted")

        {:error, _changeset} ->
          put_flash(socket, :error, "Could not delete the recipe")
      end

    {:noreply,
     socket
     |> assign(:deleting, nil)
     |> assign(:recipes, Recipes.find_all())}
  end

  @impl true
  def handle_info({:recipe_saved, _recipe}, socket) do
    socket =
      socket
      |> assign(:recipes, Recipes.find_all())
      |> assign(:modal_is_open, false)
      |> assign(:editing_recipe, nil)

    {:noreply, socket}
  end
end
