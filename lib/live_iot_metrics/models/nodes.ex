defmodule LiveMetrics.Models.Nodes do
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "nodes" do
    belongs_to :area, LiveMetrics.Models.Area
    has_many :sensors, LiveMetrics.Models.Sensor, foreign_key: :node_id
    field :name, :string
    field :mac, :string
    field :description, :string
    timestamps()
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [:name, :description, :area_id, :mac])
    |> validate_required([:name, :mac])
    |> validate_format(:mac, ~r/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/)
  end
end
