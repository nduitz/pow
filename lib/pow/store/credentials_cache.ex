defmodule Pow.Store.CredentialsCache do
  @moduledoc """
  Default module for credentials session storage.

  A key (session id) is used to store, fetch, or delete credentials. The
  credentials are expected to take the form of
  `{credentials, session_metadata}`, where session metadata is data exclusive
  to the session id.

  This module also adds two utility methods:

    * `users/2` - to list all current users
    * `sessions/2` - to list all current sessions
  """
  alias Pow.{Config, Operations, Store.Base}

  use Base,
    ttl: :timer.minutes(30),
    namespace: "credentials"

  @doc """
  List all user for a certain user struct.

  Sessions for a user can be looked up with `sessions/3`.
  """
  @spec users(Config.t(), module()) :: [any()]
  def users(config, struct) do
    config
    |> Base.all(backend_config(config), [struct, :user, :_])
    |> Enum.map(fn {[^struct, :user, _id], user} ->
      user
    end)
  end

  @doc """
  List all existing sessions for the user fetched from the backend store.
  """
  @spec sessions(Config.t(), map()) :: [binary()]
  def sessions(config, user) do
    {struct, id} = user_to_struct_id!(user, [])

    config
    |> Base.all(backend_config(config), [struct, :user, id, :session, :_])
    |> Enum.map(fn {[^struct, :user, ^id, :session, session_id], _value} ->
      session_id
    end)
  end

  @doc """
  Add user credentials with the session id to the backend store.

  The credentials are expected to be in the format of
  `{credentials, metadata}`.

  This following three key-value will be inserted:

    - `{session_id, {[user_struct, :user, user_id], metadata}}`
    - `{[user_struct, :user, user_id], user}`
    - `{[user_struct, :user, user_id, :session, session_id], inserted_at}`

  If metadata has `:fingerprint` any active sessions for the user with the same
  `:fingerprint` in metadata will be deleted.
  """
  @impl true
  def put(config, session_id, {user, metadata}) do
    {struct, id} = user_to_struct_id!(user, [])
    user_key     = [struct, :user, id]
    session_key  = [struct, :user, id, :session, session_id]
    records      = [
      {session_id, {user_key, metadata}},
      {user_key, user},
      {session_key, :os.system_time(:millisecond)}
    ]

    delete_user_sessions_with_fingerprint(config, user, metadata)

    Base.put(config, backend_config(config), records)
  end

  @doc """
  Delete the user credentials data from the backend store.

  This following two key-value will be deleted:

  - `{session_id, {[user_struct, :user, user_id], metadata}}`
  - `{[user_struct, :user, user_id, :session, session_id], inserted_at}`

  The `{[user_struct, :user, user_id], user}` key-value is expected to expire
  when reaching its TTL.
  """
  @impl true
  def delete(config, session_id) do
    backend_config = backend_config(config)

    case Base.get(config, backend_config, session_id) do
      {[struct, :user, key_id], _metadata} ->
        session_key = [struct, :user, key_id, :session, session_id]

        Base.delete(config, backend_config, session_id)
        Base.delete(config, backend_config, session_key)

      :not_found ->
        :ok
    end
  end

  @doc """
  Fetch user credentials from the backend store from session id.
  """
  @impl true
  @spec get(Config.t(), binary()) :: {map(), list()} | :not_found
  def get(config, session_id) do
    backend_config = backend_config(config)

    with {user_key, metadata} when is_list(user_key) <- Base.get(config, backend_config, session_id),
         user when is_map(user)                      <- Base.get(config, backend_config, user_key) do
      {user, metadata}
    end
  end

  defp user_to_struct_id!(%mod{} = user, config) do
    key_values =
      user
      |> fetch_primary_key_values!(config)
      |> Enum.sort(&elem(&1, 0) < elem(&2, 0))
      |> case do
        [id: id] -> id
        clauses  -> clauses
      end

    {mod, key_values}
  end
  defp user_to_struct_id!(_user, _config), do: raise_error "Only structs can be stored as credentials"

  defp fetch_primary_key_values!(user, config) do
    user
    |> Operations.fetch_primary_key_values(config)
    |> case do
      {:error, error} -> raise_error error
      {:ok, clauses}  -> clauses
    end
  end

  defp delete_user_sessions_with_fingerprint(config, user, metadata) do
    case Keyword.get(metadata, :fingerprint) do
      nil         -> :ok
      fingerprint -> do_delete_user_sessions_with_fingerprint(config, user, fingerprint)
    end
  end

  defp do_delete_user_sessions_with_fingerprint(config, user, fingerprint) do
    backend_config = backend_config(config)

    config
    |> sessions(user)
    |> Enum.each(fn session_id ->
      with {_user_key, metadata} when is_list(metadata) <- Base.get(config, backend_config, session_id),
           ^fingerprint <- Keyword.get(metadata, :fingerprint) do
        delete(config, session_id)
      end
    end)
  end

  @spec raise_error(binary()) :: no_return()
  defp raise_error(message), do: raise message
end
