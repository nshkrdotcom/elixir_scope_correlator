defmodule ElixirScope.CorrelatorTest do
  use ExUnit.Case
  doctest ElixirScope.Correlator

  test "greets the world" do
    assert ElixirScope.Correlator.hello() == :world
  end
end
