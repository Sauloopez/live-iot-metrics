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
    |> update_change(:sensor_type, &normalize_sensor_type/1)
    |> validate_required([:sensor_type, :min_value, :max_value])
    |> validate_format(:sensor_type, ~r/^[a-z0-9_]+$/,
      message: "use lowercase letters, numbers and underscores"
    )
    |> validate_min_max()
  end

  # Nodes report types in lowercase (the CoAP server downcases them), so ranges must match
  defp normalize_sensor_type(type) when is_binary(type) do
    type |> String.trim() |> String.downcase()
  end

  defp normalize_sensor_type(type), do: type

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
