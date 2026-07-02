defmodule LiveMetricsWeb.Components.AddAreaModal do
  use LiveMetricsWeb, :live_component

  def render(assigns) do
    ~H"""
    <dialog class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">Add New Area</h3>
        <form phx-submit="save_area" phx-target={@myself}>
          <fieldset class="fieldset bg-base-200 border-base-300 rounded-box w-full border p-4">
            <legend class="fieldset-legend">Name</legend>
            <input
              type="text"
              name="name"
              class="input input-bordered w-full"
              required
              placeholder="E.g. Greenhouse 1"
            />
          </fieldset>
          <fieldset class="fieldset bg-base-200 border-base-300 rounded-box w-full border p-4 mt-4">
            <legend class="fieldset-legend">Description</legend>
            <textarea
              name="description"
              class="textarea textarea-bordered h-24 w-full"
              required
              placeholder="Description of the area..."
            ></textarea>
          </fieldset>
          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_add_area">Cancel</button>
            <button type="submit" class="btn btn-primary">Save Area</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop" phx-click="close_add_area">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  def handle_event("save_area", %{"name" => name, "description" => desc}, socket) do
    case LiveMetrics.Models.Area.create_area(%{name: name, description: desc}) do
      {:ok, area} ->
        send(self(), {:area_created, area})
        {:noreply, socket}

      {:error, _changeset} ->
        send(self(), {:area_creation_failed, "Error creating area"})
        {:noreply, socket}
    end
  end
end
