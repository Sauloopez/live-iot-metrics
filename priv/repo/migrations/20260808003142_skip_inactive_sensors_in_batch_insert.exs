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
            precision DOUBLE PRECISION,
            value DOUBLE PRECISION,
            reading_time TIMESTAMPTZ
          )
        ), upserted_nodes AS (
          -- DO UPDATE (instead of DO NOTHING) so existing nodes are returned too
          INSERT INTO nodes (id, name, mac)
          SELECT gen_random_uuid(), e.mac, e.mac
          FROM (SELECT DISTINCT mac FROM typed_entries) e
          ON CONFLICT (mac) DO UPDATE SET updated_at = now()
          RETURNING id, mac
        ), upserted_sensors AS (
          -- One row per node sensor: a batch may hold several readings of the same sensor
          INSERT INTO sensors (id, node_id, node_sensor_id, sensor_type, precision)
          SELECT DISTINCT ON (n.id, e.sensor_id)
            gen_random_uuid(), n.id, e.sensor_id, e.sensor_type, e.precision
          FROM typed_entries e
          JOIN upserted_nodes n ON n.mac = e.mac
          ORDER BY n.id, e.sensor_id, e.reading_time DESC
          ON CONFLICT (node_id, node_sensor_id) DO UPDATE SET
            sensor_type = EXCLUDED.sensor_type,
            precision = EXCLUDED.precision,
            updated_at = now()
          RETURNING id, node_id, node_sensor_id, active
        )
        INSERT INTO sensor_readings (sensor_id, value, reading_time)
        SELECT s.id, e.value, e.reading_time
        FROM typed_entries e
        JOIN upserted_nodes n ON n.mac = e.mac
        JOIN upserted_sensors s ON s.node_id = n.id AND s.node_sensor_id = e.sensor_id
        WHERE s.active;

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
            precision DOUBLE PRECISION,
            value DOUBLE PRECISION,
            reading_time TIMESTAMPTZ
          )
        ), upserted_nodes AS (
          -- DO UPDATE (instead of DO NOTHING) so existing nodes are returned too
          INSERT INTO nodes (id, name, mac)
          SELECT gen_random_uuid(), e.mac, e.mac
          FROM (SELECT DISTINCT mac FROM typed_entries) e
          ON CONFLICT (mac) DO UPDATE SET updated_at = now()
          RETURNING id, mac
        ), upserted_sensors AS (
          -- One row per node sensor: a batch may hold several readings of the same sensor
          INSERT INTO sensors (id, node_id, node_sensor_id, sensor_type, precision)
          SELECT DISTINCT ON (n.id, e.sensor_id)
            gen_random_uuid(), n.id, e.sensor_id, e.sensor_type, e.precision
          FROM typed_entries e
          JOIN upserted_nodes n ON n.mac = e.mac
          ORDER BY n.id, e.sensor_id, e.reading_time DESC
          ON CONFLICT (node_id, node_sensor_id) DO UPDATE SET
            sensor_type = EXCLUDED.sensor_type,
            precision = EXCLUDED.precision,
            updated_at = now()
          RETURNING id, node_id, node_sensor_id
        )
        INSERT INTO sensor_readings (sensor_id, value, reading_time)
        SELECT s.id, e.value, e.reading_time
        FROM typed_entries e
        JOIN upserted_nodes n ON n.mac = e.mac
        JOIN upserted_sensors s ON s.node_id = n.id AND s.node_sensor_id = e.sensor_id;

        RETURN;
      END;
      $$;
    """

    execute sql
  end
end
