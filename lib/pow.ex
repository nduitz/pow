defmodule Pow do
  @moduledoc false

  alias Pow.Config

  @doc """
  Checks for version requirement in dependencies.
  """
  @spec dependency_vsn_match?(atom(), binary()) :: boolean()
  def dependency_vsn_match?(dep, req) do
    case :application.get_key(dep, :vsn) do
      {:ok, actual} ->
        actual
        |> List.to_string()
        |> Version.match?(req)

      _any ->
        false
    end
  end

  @doc """
  Dispatches a telemetry event.

  This will dispatch an event with `:telemetry`, if `:telemetry` is available.

  You can attach to these event in Pow. Here's a common example of attaching
  to the telemetry events of session lifecycle to log them:

      defmodule MyApp.LogHandler do
        require Logger

        @otp_app :my_app

        def handle_event([@otp_app, :pow, Pow.Plug.Session, :create], _measurements, metadata, _config) do
          Logger.info("[Pow.Plug.Session] Session \#{session_id(metadata)} initiated for user \#{user_id(metadata)} with fingerprint \#{session_fingerprint(metadata)}")
        end
        def handle_event([@otp_app, :pow, Pow.Plug.Session, :delete], _measurements, metadata, _config) do
          Logger.info("[Pow.Plug.Session] Session \#{session_id(metadata)} has been terminated")
        end

        defp session_id(%{key: session_id}), do: hash(session_id)

        defp user_id(%{value: {user, _metadata}}), do: user.id

        defp session_fingerprint(%{value: {_user, metadata}}) do
          case Keyword.get(metadata, :fingerprint) do
            nil         -> session_fingerprint(nil)
            fingerprint -> hash(fingerprint)
          end
        end
        defp session_fingerprint(_any), do: "N/A"

        # You SHOULD NOT expose session IDs in logs
        defp hash(value) do
          salt = Application.get_env(@otp_app, :hash_salt, "")

          :sha256
          |> :crypto.hash([value, salt])
          |> Base.encode16()
        end
      end

      defmodule MyApp.Application do
        use Application

        @otp_app :my_app

        def start(_type, _args) do
          children = [
            MyApp.Repo,
            MyAppWeb.Endpoint,
            # ...
          ]

          attach_telemetry_log()

          opts = [strategy: :one_for_one, name: MyAppWeb.Supervisor]
          Supervisor.start_link(children, opts)
        end

        defp attach_telemetry_log() do
          events = [
            [@otp_app, :pow, Pow.Plug.Session, :create],
            [@otp_app, :pow, Pow.Plug.Session, :delete]
          ]

          :ok = :telemetry.attach_many("log-handler", events, &MyApp.LogHandler.handle_event/4, nil)
        end

        # ...
      end
  """
  @spec telemetry_event(Config.t(), module(), atom(), map(), map()) :: :ok
  def telemetry_event(config, module, event_name, measurements, metadata) do
    if Code.ensure_loaded?(:telemetry) do
      event_name =
        config
        |> Config.get(:otp_app)
        |> telemetry_event_name(module, event_name)

      :telemetry.execute(event_name, measurements, metadata)
    end
  end

  defp telemetry_event_name(nil, module, event_name), do: [:pow, module, event_name]
  defp telemetry_event_name(otp_app, module, event_name), do: [otp_app, :pow, module, event_name]
end
