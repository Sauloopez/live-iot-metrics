# Simulates a CoAP node with local storage pushing its measurements to the running server
# over real CoAP/UDP, like iot-node's RemoteSync: sensor list, status, DATA frames in sequence
# with a window of unconfirmed measurements, watermark queries, and one frame lost on purpose.
#
# Usage (server running, from the project root): mix run --no-start e2e/coap_sync.exs <mac> [n]
# Prints ACKED=<n> EXCHANGES=<n> RESENT=<n> at the end.
defmodule FakeCoapNode do
  import Bitwise

  @host {127, 0, 0, 1}
  @port 5683
  @per_frame 16
  @window 64
  @stall_limit 3
  @session_pause_ms 300
  @t0 1_762_164_450

  def post(sock, path, payload, format) do
    id = :rand.uniform(65_000)
    path_option = <<0xB0 ||| byte_size(path), path::binary>>
    # Content-Format option (12): delta 1 from Uri-Path (11)
    packet = <<0x40, 0x02, id::16>> <> path_option <> <<0x11, format, 0xFF>> <> payload
    :ok = :gen_udp.send(sock, @host, @port, packet)

    case :gen_udp.recv(sock, 0, 3000) do
      {:ok,
       {_, _,
        <<_ver::2, _type::2, tkl::4, code, ^id::16, _token::binary-size(tkl), rest::binary>>}}
      when div(code, 32) == 2 ->
        {:ok, body(rest)}

      other ->
        {:error, other}
    end
  end

  # Skips the CoAP options of a response (RFC 7252, 3.1) and returns its payload
  defp body(<<>>), do: <<>>
  defp body(<<0xFF, payload::binary>>), do: payload

  defp body(<<delta::4, len::4, rest::binary>>) do
    {_, rest} = extended(delta, rest)
    {len, rest} = extended(len, rest)
    <<_value::binary-size(len), rest::binary>> = rest
    body(rest)
  end

  defp extended(13, <<v, rest::binary>>), do: {v + 13, rest}
  defp extended(14, <<v::16, rest::binary>>), do: {v + 269, rest}
  defp extended(n, rest), do: {n, rest}

  def record(seq) do
    <<0x84, 0x1A, seq::32, 0x1A, @t0 + seq * 60::32, 0x01, 0xFA,
      20.0 + rem(seq, 10) / 4::float-32>>
  end

  def frame(first, count) do
    records = for seq <- first..(first + count - 1)//1, into: <<>>, do: record(seq)
    LiveMetrics.Sync.DataFrame.build(0, first, count, records)
  end

  def run(mac, total) do
    {:ok, sock} = :gen_udp.open(0, [:binary, active: false])

    mac_bytes =
      mac |> String.split(":") |> Enum.map(&String.to_integer(&1, 16)) |> :binary.list_to_bin()

    json = 50

    {:ok, _} =
      post(
        sock,
        "sensors",
        Jason.encode!(%{
          "mc" => mac,
          "d" => [%{"i" => 1, "t" => "water_temperature", "pr" => 1}]
        }),
        json
      )

    {:ok, _} =
      post(
        sock,
        "status",
        Jason.encode!(%{
          "mc" => mac,
          "v" => "coap",
          "b" => %{"mv" => 3950, "p" => 74},
          "c" => %{"t" => System.os_time(:second), "v" => true},
          "st" => %{
            "n" => total + 1,
            "a" => 0,
            "pd" => total,
            "f" => 1_900_000,
            "tt" => 2_228_224
          }
        }),
        json
      )

    loop(%{
      sock: sock,
      mac: mac_bytes,
      total: total,
      cursor: 1,
      acked: 0,
      exchanges: 0,
      sent: 0,
      lost_once: false,
      stalls: 0
    })
  end

  defp loop(%{acked: acked, total: total} = s) when acked >= total, do: s
  defp loop(%{exchanges: n} = s) when n > 400, do: s

  defp loop(s) do
    window_full = s.cursor - 1 - s.acked >= @window
    nothing_new = s.cursor > s.total

    {payload, next_cursor, sent} =
      if window_full or nothing_new do
        {frame(s.cursor, 0), s.cursor, 0}
      else
        count = min(@per_frame, s.total - s.cursor + 1)
        {frame(s.cursor, count), s.cursor + count, count}
      end

    # The second data frame never reaches the server
    lose? = not s.lost_once and sent > 0 and s.cursor > @per_frame

    s =
      if lose? do
        %{s | cursor: next_cursor, sent: s.sent + sent, lost_once: true}
      else
        {:ok, <<acked::little-32, _time::little-32>>} = post(s.sock, "sync", s.mac <> payload, 42)
        moved? = acked > s.acked
        s = %{s | acked: max(acked, s.acked), exchanges: s.exchanges + 1, sent: s.sent + sent}

        cond do
          not (window_full or nothing_new) ->
            %{s | cursor: next_cursor}

          moved? ->
            %{s | stalls: 0}

          true ->
            # Same as RemoteSync: wait for the server (next session); only after
            # @stall_limit queries without progress, resend from the watermark
            Process.sleep(@session_pause_ms)
            stalls = s.stalls + 1

            if stalls >= @stall_limit,
              do: %{s | cursor: s.acked + 1, stalls: 0},
              else: %{s | stalls: stalls}
        end
      end

    loop(s)
  end
end

[mac | rest] = System.argv()
total = rest |> Enum.at(0, "500") |> String.to_integer()
result = FakeCoapNode.run(mac, total)
IO.puts("ACKED=#{result.acked} EXCHANGES=#{result.exchanges} RESENT=#{result.sent - total}")
