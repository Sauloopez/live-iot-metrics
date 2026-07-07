defmodule LiveMetrics.Repo.Migrations.ReadingsNotifying do
  use Ecto.Migration

  def change do
    sql = """
      CREATE OR REPLACE FUNCTION after_insert_sensor_reading_notify()
      RETURNS TRIGGER
      LANGUAGE plpgsql
      AS $$
      BEGIN
        PERFORM pg_notify('sensor_reading', to_jsonb(NEW)::TEXT);
        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE TRIGGER trg_after_insert_sensor_reading
      AFTER INSERT ON sensor_readings
      FOR EACH ROW
      EXECUTE FUNCTION after_insert_sensor_reading_notify();
    """

    down_sql = "DROP FUNCTION IF EXISTS after_insert_sensor_reading_notify CASCADE"

    execute(sql, down_sql)
  end
end
