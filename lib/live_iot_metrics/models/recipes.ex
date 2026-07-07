defmodule LiveMetrics.Models.Recipes do
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "recipes" do
    field :name, :string
    field :description, :string
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    has_many :batches, LiveMetrics.Models.RecipeBatch, foreign_key: :recipe_id
    has_many :property_ranges, LiveMetrics.Models.PropertyRange, foreign_key: :recipe_id

    timestamps()
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:name, :description, :started_at, :ended_at])
    |> validate_required([:name, :started_at])
  end
end
