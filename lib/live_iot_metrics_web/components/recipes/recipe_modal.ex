defmodule LiveMetricsWeb.Components.RecipeModal do
  require Logger
  alias LiveMetrics.Models.{PropertyRange, Recipes, Sensor}
  use LiveMetricsWeb, :live_component

  # Types used by the firmware presets (see the README mounting examples)
  @common_sensor_types ~w(temperature air_temperature air_humidity light soil_moisture water_temperature simulated)

  @impl true
  def update(assigns, socket) do
    recipe_struct = assigns[:editing_recipe] || %Recipes{property_ranges: [%PropertyRange{}]}
    changeset = Recipes.changeset(recipe_struct, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:recipe_struct, recipe_struct)
     |> assign_new(:sensor_types, fn ->
       Enum.uniq(@common_sensor_types ++ Sensor.distinct_types())
     end)
     |> assign(:form, to_form(changeset, as: :recipe))}
  end

  attr :editing_recipe, :any, default: nil, required: false

  @impl true
  def render(assigns) do
    ~H"""
    <dialog class="modal modal-open">
      <div class="modal-box max-w-3xl">
        <h3 class="font-bold text-lg mb-4">
          {if @recipe_struct.id, do: "Edit recipe", else: "Save recipe"}
        </h3>
        <.form
          for={@form}
          id="recipe-form"
          phx-submit="save"
          phx-change="validate"
          phx-target={@myself}
        >
          <fieldset class="fieldset bg-base-200 border-base-300 rounded-box w-full border p-4">
            <legend class="fieldset-legend">Name</legend>
            <.input
              field={@form[:name]}
              type="text"
              class="input input-bordered w-full"
              placeholder="Name..."
            />
          </fieldset>

          <fieldset class="fieldset bg-base-200 border-base-300 rounded-box w-full border p-4 mt-4">
            <legend class="fieldset-legend">Description</legend>
            <.input
              field={@form[:description]}
              type="textarea"
              class="textarea textarea-bordered h-24 w-full"
              placeholder="Description..."
            />
          </fieldset>

          <div class="space-y-4 bg-base-100 p-6 rounded-box shadow-sm border border-base-200 mt-4">
            <h3 class="text-lg font-bold text-base-content mb-2">Sensor Thresholds Configuration</h3>
            <p class="text-xs text-base-content/60 -mt-1">
              Type must match the sensor <span class="font-mono">type</span>
              configured on the node. Pick a suggestion or write a new one.
            </p>
            <datalist id="recipe-sensor-types">
              <option :for={type <- @sensor_types} value={type} />
            </datalist>
            <div class="space-y-3">
              <.inputs_for :let={range_field} field={@form[:property_ranges]}>
                <div class="flex flex-col md:flex-row gap-4 items-end bg-base-200 p-4 rounded-xl relative group">
                  <.input field={range_field[:id]} type="hidden" />
                  <div class="w-full">
                    <.input
                      field={range_field[:sensor_type]}
                      type="text"
                      label="Sensor Type"
                      list="recipe-sensor-types"
                      placeholder="e.g. soil_moisture"
                      autocomplete="off"
                      class="input input-bordered w-full font-mono"
                    />
                  </div>

                  <div class="w-full">
                    <.input
                      field={range_field[:min_value]}
                      type="number"
                      step="any"
                      label="Min Value"
                      placeholder="0.0"
                    />
                  </div>

                  <div class="w-full">
                    <.input
                      field={range_field[:max_value]}
                      type="number"
                      step="any"
                      label="Max Value"
                      placeholder="100.0"
                    />
                  </div>

                  <button
                    type="button"
                    class="btn btn-error btn-square btn-sm md:mb-2"
                    phx-click="remove_range"
                    phx-value-index={range_field.index}
                    phx-target={@myself}
                  >
                    ✕
                  </button>
                </div>
              </.inputs_for>
            </div>

            <div class="flex justify-between items-center pt-4 border-t border-base-200">
              <button
                id="btn-add-range"
                type="button"
                class="btn btn-outline btn-sm"
                phx-click="add_range"
                phx-target={@myself}
              >
                + Add Sensor Range
              </button>
            </div>
          </div>

          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_add_recipe">Cancel</button>
            <button type="submit" class="btn btn-primary">Save</button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end

  defp get_current_ranges(socket) do
    current_params = socket.assigns.form.params

    case Map.get(current_params, "property_ranges") do
      raw_ranges when is_map(raw_ranges) ->
        Map.values(raw_ranges)

      raw_ranges when is_list(raw_ranges) ->
        raw_ranges

      nil ->
        (socket.assigns.recipe_struct.property_ranges || [])
        |> Enum.map(fn r ->
          %{
            "id" => r.id,
            "sensor_type" => r.sensor_type,
            "min_value" => r.min_value,
            "max_value" => r.max_value
          }
        end)
    end
  end

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    changeset =
      socket.assigns.recipe_struct
      |> Recipes.changeset(recipe_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :recipe))}
  end

  @impl true
  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    result =
      if socket.assigns.recipe_struct.id do
        Recipes.update(socket.assigns.recipe_struct, recipe_params)
      else
        Recipes.create(recipe_params)
      end

    case result do
      {:ok, recipe} ->
        send(self(), {:recipe_saved, recipe})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :recipe))}
    end
  end

  @impl true
  def handle_event("add_range", _params, socket) do
    ranges = get_current_ranges(socket)
    new_range = %{"sensor_type" => "", "min_value" => nil, "max_value" => nil}
    updated_ranges = ranges ++ [new_range]

    updated_params = Map.put(socket.assigns.form.params, "property_ranges", updated_ranges)
    changeset = Recipes.changeset(socket.assigns.recipe_struct, updated_params)

    {:noreply, assign(socket, :form, to_form(changeset, as: :recipe))}
  end

  @impl true
  def handle_event("remove_range", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    ranges = get_current_ranges(socket)

    updated_ranges = List.delete_at(ranges, index)

    updated_params = Map.put(socket.assigns.form.params, "property_ranges", updated_ranges)

    changeset =
      socket.assigns.recipe_struct
      |> Recipes.changeset(updated_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :recipe))}
  end
end
