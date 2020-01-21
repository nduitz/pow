defmodule PowPersistentSession.Store.PersistentSessionCache do
  @moduledoc false
  use Pow.Store.Base,
    ttl: :timer.hours(24) * 30,
    namespace: "persistent_session"

  alias Pow.Store.Base

  @impl true
  def get(config, id) do
    backend_config = backend_config(config)

    config
    |> Base.get(backend_config, id)
    |> convert_old_value()
  end

  defp convert_old_value(:not_found), do: :not_found
  defp convert_old_value({user, metadata}), do: {user, metadata}
  # TODO: Remove by 1.1.0
  defp convert_old_value(clauses) when is_list(clauses), do: {clauses, []}
end
