defmodule LiveMetrics.Models.Nodes do
  use LiveMetrics.BaseSchema
  alias LiveMetrics.Repo
  alias LiveMetrics.Models.{Sensor, BatchSensor}
  import Ecto.Changeset
  import Ecto.Query

  schema "nodes" do
    has_many :sensors, LiveMetrics.Models.Sensor, foreign_key: :node_id
    field :name, :string
    field :mac, :string
    field :description, :string
    timestamps()
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [:name, :description, :mac])
    |> validate_required([:name, :mac])
    |> validate_format(:mac, ~r/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/)
  end

  @doc "Nodes with no sensor currently being actively tracked by any batch."
  def find_available do
    actively_tracked_node_ids =
      from(s in Sensor,
        join: bs in BatchSensor,
        on: bs.sensor_id == s.id,
        where: is_nil(bs.ended_at),
        select: s.node_id
      )

    __MODULE__
    |> where([n], n.id not in subquery(actively_tracked_node_ids))
    |> order_by([n], n.name)
    |> Repo.all()
  end

  def find_with_sensors(id) do
    __MODULE__
    |> Repo.get(id)
    |> Repo.preload(:sensors)
  end

  def find_all do
    __MODULE__
    |> order_by([n], n.name)
    |> Repo.all()
    |> Repo.preload(:sensors)
  end
end
