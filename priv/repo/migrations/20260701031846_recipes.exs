defmodule LiveMetrics.Repo.Migrations.Recipes do
  use Ecto.Migration

  def change do
    create table("recipes", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :name, :string
      add :description, :string
      add :started_at, :timestamptz
      add :ended_at, :timestamptz, null: true
    end

    create table("recipe_batch", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :recipe_id, references("recipes", on_delete: :delete_all, type: :binary_id), null: false
      add :name, :string
      add :started_at, :timestamptz
      add :ended_at, :timestamptz, null: true
    end

    create table("property_range", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :recipe_id, references("recipes", on_delete: :delete_all, type: :binary_id), null: false
      add :sensor_type, :string
      add :min_value, :float
      add :max_value, :float
    end

    create index("property_range", :recipe_id)

    create table("batch_sensors", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true

      add :recipe_batch_id, references("recipe_batch", on_delete: :delete_all, type: :binary_id),
        null: false

      add :sensor_id, references("sensors", on_delete: :delete_all, type: :binary_id), null: false

      add :started_at, :timestamptz, null: false, default: fragment("now()")
      add :ended_at, :timestamptz, null: true
    end

    create index("batch_sensors", :recipe_batch_id)
    create index("batch_sensors", :sensor_id)

    # a recipe sensor can only have one active sensor per recipe at a time
    create(
      unique_index("batch_sensors", [:sensor_id],
        where: "ended_at IS NULL",
        name: :active_sensor_per_batch
      )
    )

    after_update_recipe_ends_sql = """
      CREATE OR REPLACE FUNCTION after_update_batch_ended_at_update_sensors()
      RETURNS TRIGGER
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF OLD.ended_at IS DISTINCT FROM NEW.ended_at THEN
          UPDATE batch_sensors
          SET ended_at = NEW.ended_at
          WHERE recipe_id = NEW.id;
        END IF;
        RETURN NEW;
      END;
      $$;
    """

    trigger_sql = """
    CREATE OR REPLACE TRIGGER trg_after_update_batch_ended_at_update_sensors
    AFTER UPDATE OF ended_at ON recipe_batch
    FOR EACH ROW
    EXECUTE FUNCTION after_update_batch_ended_at_update_sensors();
    """

    down_sql = "DROP FUNCTION IF EXISTS after_update_batch_ended_at_update_sensors CASCADE"
    execute after_update_recipe_ends_sql, down_sql
    execute trigger_sql
  end
end
