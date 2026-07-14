defmodule LiveMetrics.Models.Recipes do
  alias LiveMetrics.Repo
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "recipes" do
    field :name, :string
    field :description, :string

    has_many :batches, LiveMetrics.Models.RecipeBatch, foreign_key: :recipe_id
    has_many :property_ranges, LiveMetrics.Models.PropertyRange, foreign_key: :recipe_id, on_replace: :delete
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> cast_assoc(:property_ranges, required: true)
  end

  def find_all() do
    __MODULE__
    |> Repo.all()
    |> Repo.preload(:property_ranges)
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def find_by_id(id) do
    __MODULE__
    |> Repo.get(id)
    |> Repo.preload(:property_ranges)
  end

  def update(recipe, attrs) do
    recipe
    |> changeset(attrs)
    |> Repo.update()
  end
end
