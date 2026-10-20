defmodule LiveMetrics.Models.Recipes do
  require Logger
  alias LiveMetrics.Repo
  use LiveMetrics.BaseSchema
  import Ecto.Changeset
  import Ecto.Query

  schema "recipes" do
    field :name, :string
    field :description, :string

    has_many :batches, LiveMetrics.Models.RecipeBatch, foreign_key: :recipe_id

    has_many :property_ranges, LiveMetrics.Models.PropertyRange,
      foreign_key: :recipe_id,
      on_replace: :delete
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

  @doc "Number of production batches (active or ended) created from the recipe."
  def count_batches(%__MODULE__{id: id}) do
    from(b in LiveMetrics.Models.RecipeBatch, where: b.recipe_id == ^id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Deletes the recipe and its ranges. Recipes used by batches are kept: the database would
  cascade the delete to every batch, so those batches must be deleted explicitly first.
  """
  def delete(%__MODULE__{} = recipe) do
    case count_batches(recipe) do
      0 -> Repo.delete(recipe)
      count -> {:error, {:in_use, count}}
    end
  end

  def find_select_options() do
    from(r in __MODULE__, select: {r.name, r.id})
    |> Repo.all()
  end
end
