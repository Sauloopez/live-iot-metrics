defmodule LiveMetrics.Models.PropertyRange do
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "property_range" do
    field :sensor_type, :string
    field :min_value, :float
    field :max_value, :float

    belongs_to :recipe, LiveMetrics.Models.Recipes, foreign_key: :recipe_id
  end

  def changeset(property_range, attrs) do
    property_range
    |> cast(attrs, [:sensor_type, :min_value, :max_value])
    |> validate_required([:sensor_type, :min_value, :max_value])
    |> validate_min_max()
  end

  defp validate_min_max(changeset) do
    min = get_field(changeset, :min_value)
    max = get_field(changeset, :max_value)

    if min && max && min >= max do
      add_error(changeset, :min_value, "The min value must be minor of the max")
    else
      changeset
    end
  end
end
