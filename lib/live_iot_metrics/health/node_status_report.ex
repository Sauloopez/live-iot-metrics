defmodule LiveMetrics.Health.NodeStatusReport do
  @moduledoc """
  A health report of a node: battery, clock, storage and power counters
  (docs/tundra/PLAN.md, section 7).

  Built from the node's `status` response, which uses one or two character keys
  (docs/tundra/SERIAL_API.md):

      %{"c" => %{"t", "v"}, "b" => %{"mv", "p"},
        "st" => %{"n", "a", "pd", "f", "tt", "fw"}, "pw" => %{"bc", "aw", "rr"}}
  """
  use Ecto.Schema
  import Ecto.Query

  alias LiveMetrics.Models.Nodes
  alias LiveMetrics.Repo

  @transports ~w(usb coap lora)

  schema "node_status_reports" do
    field :mac, :string
    field :variant, :string
    field :transport, :string
    field :reported_at, :utc_datetime_usec
    field :battery_mv, :integer
    field :battery_percent, :integer
    field :clock_ts, :integer
    field :clock_valid, :boolean
    field :next_seq, :integer
    field :acked_seq, :integer
    field :pending, :integer
    field :storage_free_bytes, :integer
    field :storage_total_bytes, :integer
    field :failed_writes, :integer
    field :boot_count, :integer
    field :awake_ms, :integer
    field :reset_reason, :integer
  end

  @doc """
  Stores a `status` response of `mac`. The node is registered if the server did not know it
  yet, so an isolated node shows up in Devices from its first USB connection.
  """
  def record(mac, variant, transport, status) when transport in @transports and is_map(status) do
    mac = mac |> String.trim() |> String.upcase()
    {:ok, _node} = Nodes.ensure(mac)

    clock = Map.get(status, "c", %{})
    battery = Map.get(status, "b", %{})
    storage = Map.get(status, "st", %{})
    power = Map.get(status, "pw", %{})

    Repo.insert(%__MODULE__{
      mac: mac,
      variant: variant,
      transport: transport,
      reported_at: DateTime.utc_now(),
      battery_mv: int(battery["mv"]),
      battery_percent: int(battery["p"]),
      clock_ts: int(clock["t"]),
      clock_valid: clock["v"] == true,
      next_seq: int(storage["n"]),
      acked_seq: int(storage["a"]),
      pending: int(storage["pd"]),
      storage_free_bytes: int(storage["f"]),
      storage_total_bytes: int(storage["tt"]),
      failed_writes: int(storage["fw"]),
      boot_count: int(power["bc"]),
      awake_ms: int(power["aw"]),
      reset_reason: int(power["rr"])
    })
  end

  @doc "The two most recent reports of every node: `%{mac => [latest, previous]}`."
  def latest_two_by_mac(macs) do
    ranked =
      from(r in __MODULE__,
        where: r.mac in ^macs,
        select: %{id: r.id, rank: over(row_number(), :by_mac)},
        windows: [by_mac: [partition_by: r.mac, order_by: [desc: r.reported_at, desc: r.id]]]
      )

    from(r in __MODULE__,
      join: k in subquery(ranked),
      on: k.id == r.id,
      where: k.rank <= 2,
      order_by: [asc: r.mac, desc: r.reported_at, desc: r.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.mac)
  end

  @doc "Most recent reports of a node, newest first."
  def recent(mac, limit \\ 10) do
    from(r in __MODULE__,
      where: r.mac == ^String.upcase(mac),
      order_by: [desc: r.reported_at, desc: r.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp int(value) when is_integer(value), do: value
  defp int(value) when is_float(value), do: round(value)
  defp int(_), do: nil
end
