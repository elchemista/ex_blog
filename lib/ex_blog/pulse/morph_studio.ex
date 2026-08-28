defmodule ExBlog.Pulse.MorphStudio do
  @moduledoc """
  ExBlog's governed Morph operation for Spectre Studio.

  The upstream Pulse bridge intentionally knows nothing about a host's replay
  policy. ExBlog handles only the Morph proposal envelope here so it can supply
  the exact protected corpus sealed into its active Definition. Authentication,
  principal binding, granted scope, Agent exposure, and live-Instance routing
  are checked with the same Pulse boundaries as the built-in Studio bridge.
  """

  alias ExBlog.Agent.MorphEvaluation
  alias Spectre.Morph
  alias Spectre.Morph.Change
  alias Spectre.Pulse.AgentDescriptor
  alias Spectre.Pulse.Codec.JSON
  alias Spectre.Pulse.Connection
  alias Spectre.Pulse.ConnectionRegistry
  alias Spectre.Pulse.Envelope
  alias Spectre.Pulse.Error
  alias Spectre.Pulse.InstanceTarget
  alias Spectre.Pulse.Receipt

  require Logger

  @operation "studio.morph.propose_skill"
  @scope "spectre.morph.propose"

  @type handled ::
          :not_morph
          | {:ok, Receipt.t(), binary()}
          | {:error, Error.t()}

  @doc "Handles only ExBlog's Morph proposal operation; all other frames pass through."
  @spec handle_frame(binary(), Connection.t()) :: handled()
  def handle_frame(frame, %Connection{} = connection) when is_binary(frame) do
    if morph_frame?(frame) do
      with {:ok, envelope} <- JSON.decode(frame, []),
           result <- safe_perform(connection, envelope),
           {:ok, response} <- response(envelope, result),
           {:ok, encoded} <- JSON.encode(response, []) do
        {:ok, Receipt.accepted(envelope.id, via: :websocket, route_id: :ex_blog_morph_studio),
         encoded}
      end
    else
      :not_morph
    end
  end

  def handle_frame(_frame, %Connection{}), do: :not_morph

  defp morph_frame?(frame) do
    case Jason.decode(frame) do
      {:ok, %{"payload" => %{"type" => @operation}}} -> true
      _other -> false
    end
  end

  defp safe_perform(connection, envelope) do
    perform(connection, envelope)
  rescue
    _exception -> {:error, :studio_operation_failed}
  catch
    _kind, _reason -> {:error, :studio_operation_failed}
  end

  defp perform(connection, envelope) do
    with {:ok, agent} <- authorize(connection, envelope),
         {:ok, data} <- request_data(envelope),
         {:ok, subject} <- required_text(data, "subject"),
         {:ok, actor} <- required_text(data, "by"),
         {:ok, reason} <- required_text(data, "reason"),
         {:ok, mount_id} <- required_text(data, "mount_id"),
         {:ok, match} <- required_text(data, "match"),
         {:ok, reply} <- required_text(data, "reply"),
         {:ok, target} <-
           InstanceTarget.resolve(
             agent,
             subject,
             connection.id,
             Spectre.Instance.Registry,
             @scope,
             :studio
           ) do
      change =
        target.pid
        |> Morph.change(by: actor, reason: reason)
        |> put_operation(Map.get(data, "action"), mount_id, data, match, reply)
        |> MorphEvaluation.evaluate()

      morph_result(change)
    end
  end

  defp authorize(connection, envelope) do
    with :ok <- require_principal(connection, envelope),
         :ok <- require_scope(connection),
         :ok <- require_exposed(connection, envelope.to),
         {:ok, %AgentDescriptor{module: agent}} when is_atom(agent) <-
           ConnectionRegistry.local_agent(envelope.to) do
      {:ok, agent}
    else
      :error -> {:error, Error.not_sent(:routing, :unknown_local_agent)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp require_principal(connection, envelope) do
    if envelope.from == connection.principal.identity,
      do: :ok,
      else: {:error, Error.not_sent(:authorization, :connection_principal_mismatch)}
  end

  defp require_scope(connection) do
    if @scope in connection.granted_scopes,
      do: :ok,
      else: {:error, Error.not_sent(:authorization, {:connection_scope_required, @scope})}
  end

  defp require_exposed(connection, address) do
    if address in connection.local_agent_addresses,
      do: :ok,
      else: {:error, Error.not_sent(:authorization, :agent_not_exposed_on_connection)}
  end

  defp request_data(%Envelope{payload: %{data: data}}) when is_map(data), do: {:ok, data}
  defp request_data(%Envelope{}), do: {:error, :invalid_morph_request}

  defp put_operation(change, "replace", mount_id, data, match, reply) do
    Morph.replace_skill(change, mount_id, morph_opts(data, match, reply))
  end

  defp put_operation(change, _action, mount_id, data, match, reply) do
    Morph.mount_skill(change, mount_id, morph_opts(data, match, reply))
  end

  defp morph_opts(data, match, reply) do
    [match: match, reply: reply]
    |> put_optional(:scopes, string_list(Map.get(data, "scopes")))
    |> put_optional(:token_cap, positive_integer(Map.get(data, "token_cap")))
  end

  defp morph_result(%Change{error: nil} = change) do
    Logger.info(
      "pulse_morph evaluated candidate_ref=#{candidate_ref(change.ref)} " <>
        "operations=#{length(change.operations)} activated=false"
    )

    {:ok,
     %{
       "state" => Atom.to_string(change.state),
       "candidate_ref" => candidate_ref(change.ref),
       "mount_ids" => change.mount_ids,
       "operation_count" => length(change.operations),
       "approved" => change.state == :approved,
       "activated" => false
     }}
  end

  defp morph_result(%Change{error: error}) do
    Logger.warning("pulse_morph failed code=#{reason_code(error)}")
    {:error, error}
  end

  defp response(envelope, {:ok, data}),
    do: Envelope.reply(envelope, @operation <> ".result", data)

  defp response(envelope, {:error, %Error{} = error}),
    do: Envelope.reply(envelope, @operation <> ".error", error_data(error.kind, error.reason))

  defp response(envelope, {:error, reason}),
    do: Envelope.reply(envelope, @operation <> ".error", error_data(:request, reason))

  defp error_data(kind, reason) do
    %{"kind" => wire_value(kind), "code" => reason_code(reason)}
  end

  defp required_text(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:required, key}}, else: {:ok, value}

      _other ->
        {:error, {:required, key}}
    end
  end

  defp string_list(values) when is_list(values),
    do: values |> Enum.map(&wire_value/1) |> Enum.filter(&is_binary/1)

  defp string_list(_values), do: []

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil

  defp put_optional(opts, _key, value) when value in [nil, []], do: opts
  defp put_optional(opts, key, value), do: Keyword.put(opts, key, value)

  defp candidate_ref(nil), do: nil
  defp candidate_ref(ref), do: to_string(ref)

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_code(reason) when is_tuple(reason) and tuple_size(reason) > 0,
    do: reason |> elem(0) |> wire_value()

  defp reason_code(_reason), do: "operation_failed"

  defp wire_value(nil), do: nil
  defp wire_value(value) when is_boolean(value), do: value
  defp wire_value(value) when is_atom(value), do: Atom.to_string(value)
  defp wire_value(value) when is_binary(value) or is_number(value), do: value
  defp wire_value(value), do: inspect(value)
end
