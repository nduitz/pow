defmodule Pow.Store.Backend.EtsCacheTest do
  use ExUnit.Case
  doctest Pow.Store.Backend.EtsCache

  alias Pow.{Config, Store.Backend.EtsCache}

  @default_config [namespace: "pow:test", ttl: :timer.hours(1)]

  setup do
    start_supervised!({EtsCache, []})

    pid    = self()
    events = [
      [:pow, EtsCache, :cache],
      [:pow, EtsCache, :delete],
      [:pow, EtsCache, :invalidate]
    ]

    :telemetry.attach_many("event-handler-#{inspect pid}", events, fn event, measurements, metadata, send_to: pid ->
      send(pid, {:event, event, measurements, metadata})
    end, send_to: pid)

    :ok
  end

  test "can put, get and delete records" do
    assert EtsCache.get(@default_config, "key") == :not_found

    EtsCache.put(@default_config, {"key", "value"})
    assert_receive {:event, [:pow, EtsCache, :cache], _measurements, %{records: {"key", "value"}}}
    assert EtsCache.get(@default_config, "key") == "value"

    EtsCache.delete(@default_config, "key")
    assert_receive {:event, [:pow, EtsCache, :delete], _measurements, %{key: "key"}}
    assert EtsCache.get(@default_config, "key") == :not_found
  end

  test "can put multiple records at once" do
    EtsCache.put(@default_config, [{"key1", "1"}, {"key2", "2"}])
    :timer.sleep(100)
    assert EtsCache.get(@default_config, "key1") == "1"
    assert EtsCache.get(@default_config, "key2") == "2"
  end

  test "with no `:ttl` option" do
    config = [namespace: "pow:test"]

    EtsCache.put(config, {"key", "value"})
    :timer.sleep(100)
    assert EtsCache.get(config, "key") == "value"

    EtsCache.delete(config, "key")
    :timer.sleep(100)
  end

  test "can match fetch all" do
    EtsCache.put(@default_config, {"key1", "value"})
    EtsCache.put(@default_config, {"key2", "value"})
    EtsCache.put(@default_config, {["namespace", "key"], "value"})
    :timer.sleep(100)

    assert EtsCache.all(@default_config, :_) ==  [{"key1", "value"}, {"key2", "value"}]
    assert EtsCache.all(@default_config, ["namespace", :_]) ==  [{["namespace", "key"], "value"}]
  end

  test "records auto purge" do
    config = Config.put(@default_config, :ttl, 100)

    EtsCache.put(config, {"key", "value"})
    EtsCache.put(config, [{"key1", "1"}, {"key2", "2"}])
    :timer.sleep(50)
    assert EtsCache.get(config, "key") == "value"
    assert EtsCache.get(config, "key1") == "1"
    assert EtsCache.get(config, "key2") == "2"
    assert_receive {:event, [:pow, EtsCache, :invalidate], _measurements, %{key: "key"}}
    assert EtsCache.get(config, "key") == :not_found
    assert EtsCache.get(config, "key1") == :not_found
    assert EtsCache.get(config, "key2") == :not_found
  end

  # TODO: Remove by 1.1.0
  test "backwards compatible" do
    assert EtsCache.put(@default_config, "key", "value") == :ok
    :timer.sleep(50)
    assert EtsCache.keys(@default_config) == [{"key", "value"}]
  end
end
