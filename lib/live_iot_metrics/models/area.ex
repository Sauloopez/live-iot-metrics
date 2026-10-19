defmodule LiveMetrics.Models.Area do
  use LiveMetrics.BaseSchema
  alias LiveMetrics.Repo
  import Ecto.{Changeset, Query}
  alias LiveMetrics.Models.{RecipeBatch, AreaBatch}

  schema "areas" do
    field :name, :string
    field :description, :string

    has_many :area_batches, AreaBatch

    many_to_many :batches, RecipeBatch,
      join_through: AreaBatch,
      join_keys: [area_id: :id, batch_id: :id]
  end

  @doc false
  def changeset(area, attrs) do
    area
    |> cast(attrs, [:name, :description])
    |> validate_required([:name, :description])
  end

  def create_area(attrs) do
    %LiveMetrics.Models.Area{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def find_all_sorted_by_name do
    __MODULE__
    |> order_by(:name)
    |> Repo.all()
  end
end
