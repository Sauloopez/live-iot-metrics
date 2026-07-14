defmodule LiveIotMetricsWeb.Dashboard.AreaRecipes do
  alias LiveIotMetricsWeb.Dashboard.RecipeBatchCard
  use LiveMetricsWeb, :html

  attr :area_recipes, :list, required: true

  def grid(assigns) do
    ~H"""
    <div class="grid grid-cols-4 gap-4 bg-base-200 rounded-box p-6 space-y-6 mt-4">
      <%= for batch <- @area_recipes do %>
        <RecipeBatchCard.card recipe_batch={batch} />
      <% end %>
    </div>
    """
  end
end
