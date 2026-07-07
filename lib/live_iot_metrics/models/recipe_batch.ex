defmodule LiveMetrics.Models.RecipeBatch do
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "recipe_batch" do
    field :name, :string
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :recipe, LiveMetrics.Models.Recipes, foreign_key: :recipe_id
    has_many :batch_sensors, LiveMetrics.Models.BatchSensor

    timestamps()
  end

  def changeset(recipe_batch, attrs) do
    recipe_batch
    |> cast(attrs, [:name, :started_at, :ended_at, :recipe_id])
    |> validate_required([:name, :started_at, :recipe_id])
  end
end
