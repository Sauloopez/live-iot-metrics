defmodule LiveMetrics.Area do
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "areas" do
    field :name, :string
    field :description, :string
    has_many :nodes, LiveMetrics.Nodes

    timestamps()
  end

  @doc false
  def changeset(area, attrs) do
    area
    |> cast(attrs, [:name, :description])
    |> validate_required([:name, :description])
  end

  def create_area(attrs) do
    %LiveMetrics.Area{}
    |> changeset(attrs)
    |> LiveMetrics.Repo.insert()
  end

  def add_node(area, nodes) do
    area
    |> LiveMetrics.Repo.preload(:nodes)
    |> cast(%{}, [])
    |> put_assoc(:nodes, nodes)
    |> LiveMetrics.Repo.update()
  end
end
