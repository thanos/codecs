defmodule ExCodecs.Spatial.Codec.PLYExtraTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}
  alias ExCodecs.Spatial.Codec.PLY

  test "binary big-endian round-trip" do
    cloud = PointCloud.new([Point.new(1.5, 2.5, 3.5, color: {9, 8, 7})])
    assert {:ok, bin} = PLY.encode(cloud, format: :binary_be)
    assert bin =~ "binary_big_endian"
    assert {:ok, decoded} = PLY.decode(bin)
    assert_in_delta hd(decoded.points).x, 1.5, 0.0001
    assert hd(decoded.points).color == {9, 8, 7}
  end

  test "Gaussian binary PLY with SH" do
    cloud =
      GaussianCloud.new([
        Gaussian.new({0.0, 1.0, 2.0},
          color: {0.1, 0.2, 0.3},
          sh: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
        )
      ])

    assert {:ok, bin} = PLY.encode(cloud, format: :binary)
    assert {:ok, decoded} = PLY.decode(bin)
    assert %GaussianCloud{} = decoded
    assert hd(decoded.gaussians).sh != nil
  end

  test "encode rejects non-cloud" do
    assert {:error, %{reason: :invalid_data}} = PLY.encode(:nope)
  end

  test "stream_decode from binary and missing file path content" do
    cloud = PointCloud.new([Point.new(0.0, 0.0, 1.0)])
    {:ok, bin} = PLY.encode(cloud)

    points = PLY.stream_decode(bin) |> Enum.to_list()
    assert length(points) == 1

    # Non-existent path-like string without separators is treated as binary PLY data
    bad = PLY.stream_decode("not a ply file at all") |> Enum.to_list()
    assert [{:error, %{reason: :invalid_data}}] = bad
  end

  test "truncated vertex body" do
    header = """
    ply
    format ascii 1.0
    element vertex 2
    property float x
    property float y
    property float z
    end_header
    0 0 0
    """

    assert {:error, %{reason: :invalid_data}} = PLY.decode(header)
  end

  test "unsupported format line" do
    data = """
    ply
    format weird 1.0
    element vertex 0
    end_header
    """

    assert {:error, %{reason: :invalid_data}} = PLY.decode(data)
  end
end
