defmodule ExBlogWeb.OAuthController do
  @moduledoc "HTTP boundary for dynamic registration and OAuth authorization-code flows."

  use ExBlogWeb, :controller

  alias ExBlog.ChatGPT.OAuth
  alias ExBlog.Config

  def register(conn, params) do
    case OAuth.register_client(params) do
      {:ok, client} ->
        conn
        |> put_status(:created)
        |> no_store()
        |> json(client)

      {:error, reason} ->
        oauth_error(conn, reason)
    end
  end

  def authorize(conn, params) do
    case OAuth.validate_authorization_request(params) do
      {:ok, request} -> render_consent(conn, params, request)
      {:error, reason} -> oauth_error(conn, reason)
    end
  end

  def decide(conn, %{"oauth" => params}) do
    case OAuth.validate_authorization_request(params) do
      {:ok, request} -> decide_authorization(conn, params["decision"], request)
      {:error, reason} -> oauth_error(conn, reason)
    end
  end

  def decide(conn, _params), do: oauth_error(conn, :invalid_request)

  def token(conn, params) do
    result =
      case params["grant_type"] do
        "authorization_code" -> OAuth.exchange_authorization_code(params)
        "refresh_token" -> OAuth.refresh_access_token(params)
        _grant_type -> {:error, :unsupported_grant_type}
      end

    case result do
      {:ok, token} -> conn |> no_store() |> json(token)
      {:error, reason} -> oauth_error(conn, reason)
    end
  end

  def revoke(conn, params) do
    _revoke_result =
      case params["token"] do
        token when is_binary(token) -> OAuth.revoke(token)
        _missing -> :ok
      end

    conn
    |> no_store()
    |> send_resp(:ok, "")
  end

  defp render_consent(conn, params, request) do
    config = Config.get()

    form =
      params
      |> Map.take([
        "client_id",
        "redirect_uri",
        "response_type",
        "scope",
        "state",
        "resource",
        "code_challenge",
        "code_challenge_method"
      ])
      |> Phoenix.Component.to_form(as: :oauth)

    render(conn, :authorize,
      request: request,
      form: form,
      current_scope: conn.assigns.current_scope,
      current_language: config.default_language,
      supported_languages: config.supported_languages,
      page_title: "Autorizza ChatGPT",
      meta_description: "Consenso amministratore per la connessione MCP di ChatGPT.",
      robots: "noindex,nofollow,noarchive",
      canonical_url: OAuth.public_base_url() <> "/oauth/authorize"
    )
  end

  defp decide_authorization(conn, "approve", request), do: approve(conn, request)

  defp decide_authorization(conn, "deny", request) do
    redirect_with_oauth_result(conn, request.redirect_uri, %{
      "error" => "access_denied",
      "state" => request.state
    })
  end

  defp decide_authorization(conn, _decision, _request) do
    oauth_error(conn, :invalid_request)
  end

  defp approve(conn, request) do
    case OAuth.issue_authorization_code(request) do
      {:ok, code} ->
        redirect_with_oauth_result(conn, request.redirect_uri, %{
          "code" => code,
          "state" => request.state
        })

      {:error, _reason} ->
        oauth_error(conn, :server_error)
    end
  end

  defp redirect_with_oauth_result(conn, redirect_uri, params) do
    uri = URI.parse(redirect_uri)

    oauth_query =
      params
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> URI.encode_query()

    query = if uri.query, do: uri.query <> "&" <> oauth_query, else: oauth_query
    redirect(conn, external: URI.to_string(%{uri | query: query}))
  end

  defp oauth_error(conn, reason) do
    {error, status} = oauth_error_details(reason)

    conn
    |> put_status(status)
    |> no_store()
    |> json(%{error: error})
  end

  defp oauth_error_details(:invalid_client), do: {"invalid_client", :unauthorized}
  defp oauth_error_details(:invalid_grant), do: {"invalid_grant", :bad_request}
  defp oauth_error_details(:invalid_scope), do: {"invalid_scope", :bad_request}
  defp oauth_error_details(:invalid_target), do: {"invalid_target", :bad_request}
  defp oauth_error_details(:invalid_redirect_uri), do: {"invalid_request", :bad_request}
  defp oauth_error_details(:unsupported_grant_type), do: {"unsupported_grant_type", :bad_request}

  defp oauth_error_details(:invalid_client_metadata),
    do: {"invalid_client_metadata", :bad_request}

  defp oauth_error_details(:server_error), do: {"server_error", :internal_server_error}

  defp oauth_error_details({:storage_write_failed, _reason}),
    do: {"server_error", :internal_server_error}

  defp oauth_error_details(_reason), do: {"invalid_request", :bad_request}

  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end
end
