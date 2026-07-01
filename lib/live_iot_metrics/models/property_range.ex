defmodule LiveMetrics.Models.PropertyRange do
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "property_range" do
    field :sensor_type, :string
    field :min_value, :float
    field :max_value, :float

    belongs_to :recipe, LiveMetrics.Models.Recipes, foreign_key: :recipe_id

    timestamps()
  end

  def changeset(property_range, attrs) do
    property_range
    |> cast(attrs, [:sensor_type, :min_value, :max_value, :recipe_id])
    |> validate_required([:sensor_type, :min_value, :max_value, :recipe_id])
  end
end
