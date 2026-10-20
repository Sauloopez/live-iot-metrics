defmodule LiveMetrics.Models.Sensor do
  alias LiveMetrics.Repo
  use LiveMetrics.BaseSchema
  import Ecto.Changeset
  import Ecto.Query

  schema "sensors" do
    belongs_to :node, LiveMetrics.Models.Nodes
    field :node_sensor_id, :integer
    field :sensor_type, :string
    field :precision, :float
    field :active, :boolean, default: true
    field :inactivated_at, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:node_id, :node_sensor_id, :sensor_type, :precision])
    |> validate_required([:node_id, :node_sensor_id, :sensor_type, :precision])
  end

  def update_or_create(node, sensor_id, sensor_type, precision) do
    sensor =
      Repo.get_by(LiveMetrics.Models.Sensor, node_sensor_id: sensor_id, node_id: node.id) ||
        %LiveMetrics.Models.Sensor{}

    sensor
    |> changeset(%{
      node_id: node.id,
      node_sensor_id: sensor_id,
      sensor_type: sensor_type,
      precision: precision
    })
    |> Repo.insert_or_update()
  end

  @doc "Distinct sensor types reported by the nodes, sorted by name."
  def distinct_types do
    from(s in __MODULE__, distinct: true, select: s.sensor_type, order_by: s.sensor_type)
    |> Repo.all()
  end

  def deactivate(sensor) do
    sensor
    |> change(active: false, inactivated_at: DateTime.utc_now())
    |> Repo.update()
  end

  def activate(sensor) do
    sensor
    |> change(active: true, inactivated_at: nil)
    |> Repo.update()
  end
end
