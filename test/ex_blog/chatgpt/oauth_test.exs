defmodule ExBlog.ChatGPT.OAuthTest do
  use ExBlog.DataCase

  alias ExBlog.ChatGPT.OAuth
  alias ExBlog.Storage

  @redirect_uri "https://chatgpt.com/connector/oauth/ex-blog"
  @verifier String.duplicate("v", 64)

  test "persists only hashes and keeps renewable credentials valid across requests" do
    {client, request} = registered_authorization()

    assert {:ok, code} = OAuth.issue_authorization_code(request)
    refute persisted_terms() =~ code

    assert {:ok, token} =
             OAuth.exchange_authorization_code(exchange_params(client.client_id, code))

    assert token.token_type == "Bearer"
    assert token.expires_in == 900
    assert token.resource == OAuth.resource_url()
    assert token.scope == "offline_access articles:read articles:write"

    persisted = persisted_terms()
    refute persisted =~ token.access_token
    refute persisted =~ token.refresh_token

    assert {:ok, principal, scopes} = OAuth.authenticate_access_token(token.access_token)
    assert principal == %{subject: :admin, client_id: client.client_id}
    assert MapSet.member?(scopes, "articles:read")
    assert MapSet.member?(scopes, "articles:write")

    assert {:ok, rotated} =
             OAuth.refresh_access_token(%{
               "grant_type" => "refresh_token",
               "refresh_token" => token.refresh_token,
               "client_id" => client.client_id,
               "resource" => OAuth.resource_url()
             })

    assert {:error, :invalid_token} = OAuth.authenticate_access_token(token.access_token)
    assert {:ok, _principal, _scopes} = OAuth.authenticate_access_token(rotated.access_token)

    assert {:error, :invalid_grant} =
             OAuth.refresh_access_token(%{
               "grant_type" => "refresh_token",
               "refresh_token" => token.refresh_token,
               "client_id" => client.client_id,
               "resource" => OAuth.resource_url()
             })

    assert :ok = OAuth.revoke(rotated.refresh_token)
    assert {:error, :invalid_token} = OAuth.authenticate_access_token(rotated.access_token)
  end

  test "enforces PKCE and consumes each authorization code exactly once" do
    {client, request} = registered_authorization()
    assert {:ok, code} = OAuth.issue_authorization_code(request)

    wrong_params =
      exchange_params(client.client_id, code)
      |> Map.put("code_verifier", String.duplicate("x", 64))

    assert {:error, :invalid_grant} = OAuth.exchange_authorization_code(wrong_params)

    params = exchange_params(client.client_id, code)
    assert {:ok, _token} = OAuth.exchange_authorization_code(params)
    assert {:error, :invalid_grant} = OAuth.exchange_authorization_code(params)
  end

  test "rejects untrusted callbacks, downgraded PKCE, foreign resources, and scope escalation" do
    assert {:error, :invalid_redirect_uri} =
             OAuth.register_client(%{
               "client_name" => "Untrusted client",
               "redirect_uris" => ["https://example.com/oauth/callback"]
             })

    {client, params} = registration_and_params()

    assert {:error, :invalid_request} =
             params
             |> Map.put("code_challenge_method", "plain")
             |> OAuth.validate_authorization_request()

    assert {:error, :invalid_target} =
             params
             |> Map.put("resource", "https://attacker.example/mcp")
             |> OAuth.validate_authorization_request()

    assert {:ok, request} =
             params
             |> Map.put("scope", "articles:read")
             |> OAuth.validate_authorization_request()

    assert {:ok, code} = OAuth.issue_authorization_code(request)

    assert {:ok, token} =
             OAuth.exchange_authorization_code(exchange_params(client.client_id, code))

    assert {:error, :invalid_scope} =
             OAuth.refresh_access_token(%{
               "grant_type" => "refresh_token",
               "refresh_token" => token.refresh_token,
               "client_id" => client.client_id,
               "resource" => OAuth.resource_url(),
               "scope" => "articles:read articles:write"
             })
  end

  test "publishes DCR, PKCE, rotation, resource, and scope metadata" do
    authorization = OAuth.authorization_server_metadata()
    protected = OAuth.protected_resource_metadata()

    assert authorization.code_challenge_methods_supported == ["S256"]
    assert authorization.token_endpoint_auth_methods_supported == ["none"]
    assert authorization.grant_types_supported == ["authorization_code", "refresh_token"]
    assert authorization.registration_endpoint == OAuth.public_base_url() <> "/oauth/register"
    assert protected.resource == OAuth.resource_url()
    assert protected.authorization_servers == [OAuth.public_base_url()]

    challenge =
      OAuth.authorization_challenge(
        "articles:read",
        "insufficient_scope",
        "Authentication required"
      )

    assert challenge =~ ~s(resource_metadata="#{OAuth.resource_metadata_url()}")
    assert challenge =~ ~s(scope="articles:read")
    refute challenge =~ "\n"
  end

  defp registered_authorization do
    {client, params} = registration_and_params()
    assert {:ok, request} = OAuth.validate_authorization_request(params)
    {client, request}
  end

  defp registration_and_params do
    assert {:ok, client} =
             OAuth.register_client(%{
               "client_name" => "ChatGPT",
               "redirect_uris" => [@redirect_uri],
               "grant_types" => ["authorization_code", "refresh_token"],
               "response_types" => ["code"],
               "token_endpoint_auth_method" => "none"
             })

    params = %{
      "response_type" => "code",
      "client_id" => client.client_id,
      "redirect_uri" => @redirect_uri,
      "scope" => "offline_access articles:read articles:write",
      "code_challenge" => challenge(),
      "code_challenge_method" => "S256",
      "resource" => OAuth.resource_url(),
      "state" => "opaque-state"
    }

    {client, params}
  end

  defp exchange_params(client_id, code) do
    %{
      "grant_type" => "authorization_code",
      "code" => code,
      "client_id" => client_id,
      "redirect_uri" => @redirect_uri,
      "code_verifier" => @verifier,
      "resource" => OAuth.resource_url()
    }
  end

  defp challenge do
    :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  end

  defp persisted_terms do
    Storage.all()
    |> :erlang.term_to_binary()
  end
end
