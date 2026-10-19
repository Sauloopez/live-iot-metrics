# Sends sensor readings to the running server over real CoAP/UDP, like the ESP32 does.
# Usage: elixir inject.exs <mac> <mode> [count] [delay_ms]
#   mode "register" -> one in-range reading per sensor
#   mode "live"     -> readings that drift and leave the target range
defmodule CoapInject do
  @host {127, 0, 0, 1}
  @port 5683

  def packet(msg_id, payload) do
    # ver=1 CON TKL=0 | POST | msg id | Uri-Path "metrics" | Content-Format 50 (json) | payload
    <<0x40, 0x02, msg_id::16, 0xB7, "metrics", 0x11, 50, 0xFF, payload::binary>>
  end

  def send_reading(sock, msg_id, mac, sensor_id, type, value) do
    payload = JSON.encode!(%{"m" => mac, "s" => sensor_id, "t" => type, "p" => 1.0, "v" => value})
    :ok = :gen_udp.send(sock, @host, @port, packet(msg_id, payload))

    case :gen_udp.recv(sock, 0, 2000) do
      {:ok, {_, _, <<_::4, _::4, code, _::binary>>}} ->
        IO.puts("sent #{type}=#{Float.round(value, 2)} -> ack code #{div(code, 32)}.#{rem(code, 32)}")

      {:error, reason} ->
        IO.puts("sent #{type}=#{value} -> no ack (#{inspect(reason)})")
    end
  end
end

[mac, mode | rest] = System.argv()
count = rest |> Enum.at(0, "1") |> String.to_integer()
delay = rest |> Enum.at(1, "1000") |> String.to_integer()
{:ok, sock} = :gen_udp.open(0, [:binary, active: false])

sensors = [{1, "temperature"}, {2, "air_humidity"}, {3, "light"}]

for i <- 1..count do
  for {sid, type} <- sensors do
    value =
      case {mode, type} do
        {"register", "temperature"} -> 24.0
        {"register", "air_humidity"} -> 55.0
        {"register", "light"} -> 60.0
        # temperature climbs past 30, humidity dips under 40, light stays in range
        {"live", "temperature"} -> 27.0 + i * 0.6 + :rand.uniform()
        {"live", "air_humidity"} -> 50.0 - i * 1.5 + :rand.uniform() * 2
        {"live", "light"} -> 55.0 + :rand.uniform() * 15
      end

    CoapInject.send_reading(sock, :rand.uniform(65_000), mac, sid, type, value)
  end

  if i < count, do: Process.sleep(delay)
end
