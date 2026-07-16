defmodule ExCodecs.Spatial.Codec.BinaryTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.Codec.Binary
  alias ExCodecs.Spatial.{Point, PointCloud}

  test "round-trips colored points with normals" do
    cloud =
      PointCloud.new([
        Point.new(1.0, 2.0, 3.0, color: {10, 20, 30}, normal: {0.0, 1.0, 0.0}),
        Point.new(4.0, 5.0, 6.0, color: {40, 50, 60}, normal: {1.0, 0.0, 0.0})
      ])

    assert {:ok, bin} = Binary.encode(cloud)
    assert String.starts_with?(bin, "EXCP")
    assert {:ok, decoded} = Binary.decode(bin)
    assert length(decoded.points) == 2
    assert hd(decoded.points).color == {10, 20, 30}
    assert hd(decoded.points).normal == {0.0, 1.0, 0.0}
  end

  test "round-trips RGBA" do
    cloud = PointCloud.new([Point.new(0, 0, 0, color: {1, 2, 3, 4})])
    assert {:ok, bin} = Binary.encode(cloud)
    assert {:ok, decoded} = Binary.decode(bin)
    assert hd(decoded.points).color == {1, 2, 3, 4}
  end

  test "rejects bad magic" do
    assert {:error, %{reason: :invalid_data}} =
             Binary.decode(<<"XXXX", 0, 1, 0, 0, 0, 0, 0, 0, 0, 0>>)
  end
end
