defmodule ExCodecs.Spatial.PointTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.Point

  doctest ExCodecs.Spatial.Point

  test "creates points with optional color and normal" do
    p =
      Point.new(1, 2, 3,
        color: {10, 20, 30, 255},
        normal: {0.0, 1.0, 0.0},
        attributes: %{"intensity" => 0.5}
      )

    assert Point.coords(p) == {1.0, 2.0, 3.0}
    assert Point.colored?(p)
    assert Point.has_normal?(p)
    assert p.attributes["intensity"] == 0.5
  end

  test "normalizes atom attribute keys to strings" do
    p = Point.new(0, 0, 0, attributes: %{:intensity => 0.25, "label" => "a"})
    assert p.attributes == %{"intensity" => 0.25, "label" => "a"}
  end
end
