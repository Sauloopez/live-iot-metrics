defmodule LiveMetricsWeb.Components.AddNodeModal do
  use LiveMetricsWeb, :live_component

  attr :unassigned_nodes, :list, default: []
  attr :format_mac_fun, :any, required: true

  def render(assigns) do
    ~H"""
    <dialog class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <h3 class="font-bold text-lg mb-4">Assign Devices to Area</h3>

        <%= if Enum.empty?(@unassigned_nodes) do %>
          <div class="alert alert-info">
            <.icon name="hero-information-circle" class="w-6 h-6" />
            <span>
              No available unassigned devices found. Device nodes will appear here when they connect and send data.
            </span>
          </div>
          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_add_node">Close</button>
          </div>
        <% else %>
          <form phx-submit="save_nodes" phx-target={@myself}>
            <div class="overflow-x-auto max-h-96">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>Select</th>
                    <th>Name</th>
                    <th>MAC Address</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for node <- @unassigned_nodes do %>
                    <tr>
                      <td>
                        <input
                          type="checkbox"
                          name="node_ids[]"
                          value={node.id}
                          class="checkbox checkbox-primary"
                        />
                      </td>
                      <td class="font-medium">{node.name}</td>
                      <td class="font-mono text-sm">{@format_mac_fun.(node.mac)}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
            <div class="modal-action mt-6">
              <button type="button" class="btn" phx-click="close_add_node">Cancel</button>
              <button type="submit" class="btn btn-primary">Assign Selected</button>
            </div>
          </form>
        <% end %>
      </div>
      <form method="dialog" class="modal-backdrop" phx-click="close_add_node">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  def handle_event("save_nodes", %{"node_ids" => node_ids}, socket) do
    send(self(), {:assign_nodes, node_ids})
    {:noreply, socket}
  end

  def handle_event("save_nodes", _, socket) do
    send(self(), {:close_node_modal})
    {:noreply, socket}
  end
end
