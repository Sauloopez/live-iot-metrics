defmodule LiveMetrics.Nodes do
  alias LiveMetrics.Repo
  use LiveMetrics.BaseSchema
  import Ecto.Changeset

  schema "nodes" do
    belongs_to :area, LiveMetrics.Area
    field :name, :string
    field :mac, :binary
    field :description, :string
    timestamps()
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [:name, :description, :area_id, :mac])
    |> validate_required([:name, :mac])
    |> validate_format(:mac, ~r/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/)
    |> transform_mac_address()
  end

  defp transform_mac_address(changeset) do
    case get_change(changeset, :mac) do
      mac_str when is_binary(mac_str) ->
        clean_mac = String.replace(mac_str, ":", "")

        case Base.decode16(clean_mac, case: :mixed) do
          {:ok, binary_mac} -> put_change(changeset, :mac, binary_mac)
          :error -> add_error(changeset, :mac, "invalid MAC")
        end

      _ ->
        changeset
    end
  end

  def get_or_insert(mac_address) do
    binary_mac =
      case Base.decode16(String.replace(mac_address, ":", ""), case: :mixed) do
        {:ok, decoded} -> decoded
        :error -> mac_address
      end

    case Repo.get_by(LiveMetrics.Nodes, mac: binary_mac) do
      %LiveMetrics.Nodes{} = node ->
        {:ok, node}

      nil ->
        %LiveMetrics.Nodes{}
        |> LiveMetrics.Nodes.changeset(%{
          mac: mac_address,
          name: "Node-#{Base.encode16(binary_mac)}"
        })
        |> Repo.insert()
    end
  end
end
