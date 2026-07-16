defmodule ExCodecs.Spatial.BoundsTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.{Bounds, Point}

  test "computes bounds from points" do
    points = [Point.new(0, 0, 0), Point.new(2, 4, 6)]
    bounds = Bounds.from_points(points)

    assert bounds.min_x == 0.0
    assert bounds.max_z == 6.0
    assert Bounds.center(bounds) == {1.0, 2.0, 3.0}
    assert Bounds.size(bounds) == {2.0, 4.0, 6.0}
    assert Bounds.contains?(bounds, {1.0, 1.0, 1.0})
    refute Bounds.contains?(bounds, {10.0, 0.0, 0.0})
  end

  test "empty enumerable yields nil" do
    assert Bounds.from_points([]) == nil
  end
end
