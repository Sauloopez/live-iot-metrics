defmodule LiveMetrics.Repo.Migrations.SkipInactiveSensorsInBatchInsert do
  use Ecto.Migration

  def up do
    sql = """
      CREATE OR REPLACE FUNCTION insert_reading_in_batch(entries JSONB)
      RETURNS VOID
      LANGUAGE plpgsql
      AS $$
      BEGIN
        WITH typed_entries AS (
          SELECT * FROM jsonb_to_recordset(entries) AS x(
            mac TEXT,
            sensor_id INTEGER,
            sensor_type TEXT,
            precision NUMERIC,
            value NUMERIC,
            reading_time TEXT
          )
        ), new_nodes AS (
          INSERT INTO nodes(name, mac)
          SELECT DISTINCT(x.mac, x.mac) FROM typed_entries
          ON CONFLICT (mac, name) DO NOTHING
          RETURNING *
        ), new_sensors AS (
          INSERT INTO sensors (node_id, node_sensor_id, sensor_type, precision)
          SELECT y.id, x.sensor_id, x.sensor_type, x.precision
          FROM typed_entries
          JOIN new_nodes y ON x.mac = y.mac
          ON CONFLICT (node_id, node_sensor_id) DO UPDATE SET
            sensor_type = x.sensor_type,
            precision = x.precision
          RETURNING *
        ) INSERT INTO sensor_readings (sensor_id, value, reading_time)
        SELECT y.id, x.value, x.reading_time
        FROM typed_entries
        JOIN new_sensors y ON x.sensor_id = y.node_sensor_id
        WHERE y.active;

        RETURN;
      END;
      $$;
    """

    execute sql
  end

  def down do
    sql = """
      CREATE OR REPLACE FUNCTION insert_reading_in_batch(entries JSONB)
      RETURNS VOID
      LANGUAGE plpgsql
      AS $$
      BEGIN
        WITH typed_entries AS (
          SELECT * FROM jsonb_to_recordset(entries) AS x(
            mac TEXT,
            sensor_id INTEGER,
            sensor_type TEXT,
            precision NUMERIC,
            value NUMERIC,
            reading_time TEXT
          )
        ), new_nodes AS (
          INSERT INTO nodes(name, mac)
          SELECT DISTINCT(x.mac, x.mac) FROM typed_entries
          ON CONFLICT (mac, name) DO NOTHING
          RETURNING *
        ), new_sensors AS (
          INSERT INTO sensors (node_id, node_sensor_id, sensor_type, precision)
          SELECT y.id, x.sensor_id, x.sensor_type, x.precision
          FROM typed_entries
          JOIN new_nodes y ON x.mac = y.mac
          ON CONFLICT (node_id, node_sensor_id) DO UPDATE SET
            sensor_type = x.sensor_type,
            precision = x.precision
          RETURNING *
        ) INSERT INTO sensor_readings (sensor_id, value, reading_time)
        SELECT y.id, x.value, x.reading_time
        FROM typed_entries
        JOIN new_sensors y ON x.sensor_id = y.node_sensor_id;

        RETURN;
      END;
      $$;
    """

    execute sql
  end
end
