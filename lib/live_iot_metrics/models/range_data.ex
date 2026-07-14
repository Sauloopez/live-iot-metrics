defmodule LiveIotMetrics.Models.RangeData do
  use Ecto.Schema
	import Ecto.Changeset

	@primary_key false
	embedded_schema do
    field :sensor_type, :string
    field :min, :float
    field :max, :float
  end

  def changeset(struct, attrs) do
    struct
      |>cast(attrs, [:sensor_type, :min, :max])
      |>validate_required([:sensor_type, :min, :max])
      |>validate_min_max()
  end

  defp validate_min_max(changeset) do
    min = get_field(changeset, :min)
    max = get_field(changeset, :max)

    if min && max && min >= max do
      add_error(changeset, :min, "The min value must be minor of the max")
    else
      changeset
    end
  end

end
