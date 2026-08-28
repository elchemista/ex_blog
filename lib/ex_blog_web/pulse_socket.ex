defmodule ExBlogWeb.PulseSocket do
  @moduledoc """
  Phoenix transport for the `:studio` Spectre Pulse connection.

  Phoenix owns the HTTP upgrade, TLS, and origin policy; Pulse owns protocol
  validation, the authenticated connection state, Agent exposure, and the
  lifetime of every monitoring subscription created over this socket. The
  generated module implements `Phoenix.Socket.Transport` — it is not a Channel,
  and one socket carries every exposed Agent rather than one process per Agent.

  The `:studio` identifier must match `ExBlog.Pulse.connection_id/0`; the macro
  needs a literal, so `ExBlog.Pulse` keeps the authoritative copy and
  `test/ex_blog/pulse_test.exs` asserts the two agree. When no connection is
  configured, the specification cannot be resolved and the upgrade is rejected
  before any credential is read.
  """

  @behaviour Phoenix.Socket.Transport

  require Logger

  alias ExBlog.Config
  alias ExBlog.Pulse.MorphStudio
  alias Spectre.Pulse.ConnectionRegistry
  alias Spectre.Pulse.Error
  alias Spectre.Pulse.Phoenix.Frame
  alias Spectre.Pulse.Phoenix.Socket, as: PulseTransport

  @pulse_options [connection: :studio]

  @impl Phoenix.Socket.Transport
  def child_spec(_opts), do: :ignore

  @impl Phoenix.Socket.Transport
  def connect(transport_info) do
    case PulseTransport.connect(transport_info, @pulse_options) do
      {:ok, _ticket} = accepted ->
        Logger.info("pulse_connection handshake_ready")
        accepted

      {:error, reason} = rejected ->
        Logger.warning(
          "pulse_connection rejected code=#{reason_code(reason)} " <>
            "reason=#{inspect(safe_reason(reason))}"
        )

        rejected
    end
  end

  @impl Phoenix.Socket.Transport
  def init(pending) do
    case PulseTransport.init(pending) do
      {:ok, state} = connected ->
        Logger.info(
          "pulse_connection ready connection_id=#{inspect(state.connection.id)} " <>
            "principal_id=#{inspect(state.connection.principal.id)}"
        )

        connected

      {:stop, reason} = stopped ->
        Logger.warning(
          "pulse_connection init_failed code=#{reason_code(reason)} " <>
            "reason=#{inspect(safe_reason(reason))}"
        )

        stopped
    end
  end

  @impl Phoenix.Socket.Transport
  def handle_in(frame, state) do
    started_at = System.monotonic_time()
    request = request_context(frame)
    result = handle_pulse_frame(frame, state)

    log_request_result(result, request, elapsed_ms(started_at))
    result
  end

  defp handle_pulse_frame({payload, _opts} = frame, state) when is_binary(payload) do
    case MorphStudio.handle_frame(payload, state.connection) do
      {:ok, receipt, response_frame} ->
        send(self(), {:spectre_pulse_frame, response_frame})
        {:reply, :ok, {:text, Frame.receipt(receipt)}, touch(state)}

      :not_morph ->
        PulseTransport.handle_in(frame, state)

      {:error, %Error{} = error} ->
        {:reply, :error, {:text, Frame.error(error)}, touch(state)}
    end
  end

  defp handle_pulse_frame(frame, state), do: PulseTransport.handle_in(frame, state)

  @impl Phoenix.Socket.Transport
  def handle_info(message, state), do: PulseTransport.handle_info(message, state)

  @impl Phoenix.Socket.Transport
  def handle_control(frame, state), do: PulseTransport.handle_control(frame, state)

  @impl Phoenix.Socket.Transport
  def terminate(reason, state) do
    Logger.info("pulse_connection closed code=#{reason_code(reason)}")
    PulseTransport.terminate(reason, state)
  end

  defp log_request_result({:reply, :ok, _frame, _state}, request, duration_ms) do
    Logger.info("pulse_request completed #{request_log(request)} duration_ms=#{duration_ms}")
  end

  defp log_request_result({:reply, :error, {:text, frame}, _state}, request, duration_ms) do
    error = public_error(frame)

    Logger.warning(
      "pulse_request failed #{request_log(request)} kind=#{inspect(error.kind)} " <>
        "code=#{inspect(error.code)} request_id=#{inspect(error.request_id)} " <>
        "duration_ms=#{duration_ms}"
    )
  end

  defp log_request_result({:stop, reason, _state}, request, duration_ms) do
    Logger.warning(
      "pulse_request stopped #{request_log(request)} code=#{reason_code(reason)} " <>
        "duration_ms=#{duration_ms}"
    )
  end

  defp request_context({frame, _opts}) when is_binary(frame) do
    case Jason.decode(frame) do
      {:ok, %{"type" => type} = decoded} when is_binary(type) ->
        %{
          type: bounded(type, 120),
          agent_address: bounded(Map.get(decoded, "agent_address"), 200),
          request_id: bounded(Map.get(decoded, "request_id"), 128)
        }

      {:ok, %{"payload" => %{"type" => type}} = decoded} when is_binary(type) ->
        %{
          type: "envelope:" <> bounded(type, 110),
          agent_address: bounded(Map.get(decoded, "to"), 200),
          request_id: bounded(Map.get(decoded, "id"), 128)
        }

      _invalid ->
        %{type: "unrecognized", agent_address: nil, request_id: nil}
    end
  end

  defp request_context(_frame),
    do: %{type: "non_text", agent_address: nil, request_id: nil}

  defp request_log(request) do
    "type=#{inspect(request.type)} agent_address=#{inspect(request.agent_address)} " <>
      "client_request_id=#{inspect(request.request_id)}"
  end

  defp bounded(value, limit) when is_binary(value), do: String.slice(value, 0, limit)
  defp bounded(_value, _limit), do: nil

  defp touch(state) do
    case ConnectionRegistry.touch(state.connection.id) do
      {:ok, connection} -> %{state | connection: connection}
      _unavailable -> state
    end
  end

  defp public_error(frame) do
    case Jason.decode(frame) do
      {:ok, %{"error" => error}} when is_map(error) ->
        %{
          kind: Map.get(error, "kind", "unknown"),
          code: Map.get(error, "code", "unknown"),
          request_id: Map.get(error, "request_id")
        }

      _invalid ->
        %{kind: "unknown", code: "invalid_error_frame", request_id: nil}
    end
  end

  defp elapsed_ms(started_at) do
    started_at
    |> then(&(System.monotonic_time() - &1))
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp reason_code(%{reason: reason}), do: reason_code(reason)
  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_code(reason) when is_tuple(reason) and tuple_size(reason) > 0,
    do: reason |> elem(0) |> reason_code()

  defp reason_code(_reason), do: "unknown"

  defp safe_reason(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 1_000)
    |> Config.redact()
  end
end
