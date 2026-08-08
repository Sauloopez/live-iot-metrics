defmodule LiveMetrics.Models.BatchSensor do
  use LiveMetrics.BaseSchema
  alias LiveMetrics.Models.{RecipeBatch, Sensor}
  alias LiveMetrics.Repo

  import Ecto.Changeset
  import Ecto.Query

  schema "batch_sensors" do
    field :min_value, :float
    field :max_value, :float
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :recipe_batch, RecipeBatch, foreign_key: :recipe_batch_id
    belongs_to :sensor, Sensor
  end

  def changeset(batch_sensor, attrs) do
    batch_sensor
    |> cast(attrs, [:min_value, :max_value, :recipe_batch_id, :sensor_id, :started_at, :ended_at])
    |> validate_required([
      :min_value,
      :max_value,
      :recipe_batch_id,
      :sensor_id,
      :started_at
    ])
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def create_many(entries) do
    Repo.transaction(fn ->
      Enum.map(entries, fn attrs ->
        case create(attrs) do
          {:ok, batch_sensor} -> batch_sensor
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  def end_tracking_for_node(recipe_batch_id, node_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(bs in __MODULE__,
      join: s in assoc(bs, :sensor),
      where:
        bs.recipe_batch_id == ^recipe_batch_id and
          s.node_id == ^node_id and
          is_nil(bs.ended_at)
    )
    |> Repo.update_all(set: [ended_at: now])
  end
end
