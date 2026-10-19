defmodule LiveIotMetricsWeb.Dashboard.StartBatchModal do
  require Logger
  alias LiveMetrics.Models.AreaBatch
  alias LiveMetrics.Models.RecipeBatch
  alias LiveMetrics.Models.Recipes
  use LiveMetricsWeb, :live_component

  @impl true
  def update(assigns, socket) do
    recipe_options = Recipes.find_select_options()
    batch_struct = %RecipeBatch{:area_batch => %AreaBatch{area_id: assigns.area_id}}

    changeset_form =
      to_form(RecipeBatch.changeset(batch_struct, %{:started_at => DateTime.utc_now()}),
        as: :recipe_batch
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:batch_struct, batch_struct)
     |> assign(:recipe_options, recipe_options)
     |> assign(:form, changeset_form)}
  end

  attr :area_id, :integer, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <dialog class="modal modal-open">
      <div class="modal-box max-w-3xl">
        <h3 class="font-bold text-lg mb-4">
          Start Recipe Batch
        </h3>
        <.form for={@form} phx-submit="save" phx-change="validate" phx-target={@myself}>
          <.input
            field={@form[:name]}
            type="text"
            label="Batch name"
            class="input input-bordered w-full"
            placeholder="Name..."
          />

          <.input
            field={@form[:recipe_id]}
            type="select"
            label="Recipe"
            options={[{"Pick a recipe...", ""}] ++ @recipe_options}
            class="select select-bordered w-full"
          />

          <.input
            field={@form[:started_at]}
            type="datetime-local"
            label="Starts time"
            class="input input-bordered w-full"
          />

          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_start_batch">Cancel</button>
            <button type="submit" class="btn btn-primary">Save</button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end

  @impl true
  def handle_event("validate", %{"recipe_batch" => batch_params}, socket) do
    changeset =
      RecipeBatch.changeset(socket.assigns.batch_struct, batch_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :recipe_batch))}
  end

  @impl true
  def handle_event("save", %{"recipe_batch" => batch_params}, socket) do
    case RecipeBatch.create(socket.assigns.batch_struct, batch_params) do
      {:ok, batch} ->
        send(self(), {:batch_created, batch})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :recipe_batch))}
    end
  end
end
