defmodule LiveMetricsWeb.Components.AreasTabs do
  use LiveMetricsWeb, :html

  attr :areas, :list, required: true
  attr :active_area_id, :any, required: true

  def render(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-lift">
      <%= for area <- @areas do %>
        <a
          role="tab"
          class={[
            "tab tab-lg",
            @active_area_id == area.id && "tab-active font-bold"
          ]}
          phx-click="select_area"
          phx-value-id={area.id}
        >
          {area.name}
        </a>
      <% end %>
    </div>
    """
  end
end
