defmodule LiveMetricsWeb.RecipesLive do
  alias LiveMetricsWeb.Components.{ConfirmDialog, RecipeModal}
  alias LiveMetrics.Models.{RecipeBatch, Recipes}
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
        <h1 class="text-3xl font-bold text-primary">Reading definitions</h1>
        <button id="btn-add-recipe" phx-click="show_add_recipe" class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="w-4 h-4 mr-2" /> Add definition
        </button>
      </div>
      <.table id="recipes_table" rows={@recipes}>
        <:col :let={recipe} label="Name">{recipe.name}</:col>
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
            do: "Definition in use",
            else: "Delete definition \"#{@deleting.recipe.name}\"?"
        }
        on_confirm="delete_recipe"
        on_cancel="cancel_delete_recipe"
        blocked={@deleting.batch_count > 0}
      >
        <%= if @deleting.batch_count > 0 do %>
          <p>
            <span class="font-semibold">{@deleting.recipe.name}</span>
            is used by {@deleting.batch_count} reading(s).
            Delete those readings first; deleting the definition would remove them too.
          </p>
          <ul
            id="recipe-batches-in-use"
            class="divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li
              :for={batch <- @deleting.batches}
              id={"recipe-batch-in-use-#{batch.id}"}
              class="flex items-center justify-between gap-3 px-3 py-2"
            >
              <div class="min-w-0">
                <p class="font-medium text-base-content truncate">{batch.name}</p>
                <p class="text-xs">
                  {Calendar.strftime(batch.started_at, "%Y-%m-%d")} ·
                  <%= if batch.area_batch && batch.area_batch.area do %>
                    {batch.area_batch.area.name}
                  <% else %>
                    <span class="text-warning">No area (not shown on the dashboard)</span>
                  <% end %>
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <span class={[
                  "badge badge-sm",
                  if(batch.ended_at, do: "badge-ghost", else: "badge-warning badge-soft")
                ]}>
                  {if batch.ended_at, do: "Ended", else: "Active"}
                </span>
                <.link
                  id={"open-recipe-batch-#{batch.id}"}
                  navigate={~p"/recipe-batch/#{batch.id}"}
                  class="btn btn-ghost btn-xs"
                >
                  Open <.icon name="hero-arrow-right" class="w-3 h-3" />
                </.link>
              </div>
            </li>
          </ul>
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
    batches = RecipeBatch.list_by_recipe(recipe.id)

    {:noreply,
     assign(socket, :deleting, %{recipe: recipe, batches: batches, batch_count: length(batches)})}
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
          put_flash(socket, :info, "Definition \"#{recipe.name}\" deleted")

        {:error, {:in_use, count}} ->
          put_flash(
            socket,
            :error,
            "Definition is used by #{count} reading(s) and was not deleted"
          )

        {:error, _changeset} ->
          put_flash(socket, :error, "Could not delete the definition")
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
