defmodule ExCodecs.Spatial.Codec.PLYTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.Codec.PLY
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}

  describe "point cloud ASCII PLY" do
    test "round-trips XYZRGB" do
      cloud =
        PointCloud.new([
          Point.new(1.0, 2.0, 3.0, color: {255, 128, 0}),
          Point.new(-1.0, 0.5, 9.0, color: {0, 255, 64})
        ])

      assert {:ok, binary} = PLY.encode(cloud, format: :ascii)
      assert String.starts_with?(binary, "ply\n")
      assert binary =~ "format ascii 1.0"
      assert binary =~ "property uchar red"

      assert {:ok, decoded} = PLY.decode(binary)
      assert length(decoded.points) == 2
      assert hd(decoded.points).color == {255, 128, 0}
      assert Float.round(hd(decoded.points).x, 5) == 1.0
    end

    test "round-trips XYZ + normal + attributes" do
      cloud =
        PointCloud.new([
          Point.new(0.0, 1.0, 2.0,
            normal: {0.0, 1.0, 0.0},
            attributes: %{"intensity" => 0.75}
          )
        ])

      assert {:ok, binary} = PLY.encode(cloud)
      assert {:ok, decoded} = PLY.decode(binary)
      [p] = decoded.points
      assert p.normal == {0.0, 1.0, 0.0}
      assert_in_delta p.attributes["intensity"], 0.75, 0.0001
    end

    test "round-trips binary little-endian PLY" do
      cloud =
        PointCloud.new([
          Point.new(1.25, 2.5, 3.75, color: {1, 2, 3, 4})
        ])

      assert {:ok, binary} = PLY.encode(cloud, format: :binary)
      assert binary =~ "binary_little_endian"
      assert {:ok, decoded} = PLY.decode(binary)
      [p] = decoded.points
      assert_in_delta p.x, 1.25, 0.0001
      assert p.color == {1, 2, 3, 4}
    end
  end

  describe "Gaussian PLY" do
    test "round-trips Gaussian clouds" do
      cloud =
        GaussianCloud.new([
          Gaussian.new({1.0, 2.0, 3.0},
            color: {0.1, 0.2, 0.3},
            opacity: 0.8,
            scale: {0.5, 0.6, 0.7},
            rotation: {1.0, 0.0, 0.0, 0.0}
          )
        ])

      assert {:ok, binary} = PLY.encode(cloud, format: :ascii)
      assert binary =~ "f_dc_0"
      assert binary =~ "opacity"

      assert {:ok, decoded} = PLY.decode(binary)
      assert %GaussianCloud{} = decoded
      [g] = decoded.gaussians
      assert_in_delta elem(g.position, 0), 1.0, 0.0001
      assert_in_delta elem(g.color, 1), 0.2, 0.0001
      assert_in_delta g.opacity, 0.8, 0.0001
    end

    test "can force point_cloud interpretation" do
      cloud =
        GaussianCloud.new([
          Gaussian.new({0.0, 0.0, 0.0}, color: {0.5, 0.5, 0.5})
        ])

      assert {:ok, binary} = PLY.encode(cloud)
      assert {:ok, %PointCloud{}} = PLY.decode(binary, as: :point_cloud)
    end
  end

  test "rejects non-PLY data" do
    assert {:error, %{reason: :invalid_data}} = PLY.decode("not a ply file")
  end

  describe "stream_decode from file" do
    test "streams ASCII vertices without materializing the whole body" do
      cloud =
        PointCloud.new([
          Point.new(1.0, 2.0, 3.0, color: {255, 0, 0}),
          Point.new(4.0, 5.0, 6.0, color: {0, 255, 0})
        ])

      assert {:ok, bin} = PLY.encode(cloud, format: :ascii)

      path =
        Path.join(
          System.tmp_dir!(),
          "ex_codecs_ply_ascii_stream_#{System.unique_integer([:positive])}.ply"
        )

      on_exit(fn -> File.rm(path) end)
      File.write!(path, bin)

      points = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert length(points) == 2
      assert hd(points).color == {255, 0, 0}
      assert_in_delta List.last(points).x, 4.0, 0.0001
    end

    test "streams binary little-endian vertices" do
      cloud =
        PointCloud.new([
          Point.new(1.25, 2.5, 3.75, color: {1, 2, 3}),
          Point.new(-1.0, 0.0, 9.0, color: {4, 5, 6})
        ])

      assert {:ok, bin} = PLY.encode(cloud, ply_format: :binary_le)

      path =
        Path.join(
          System.tmp_dir!(),
          "ex_codecs_ply_bin_stream_#{System.unique_integer([:positive])}.ply"
        )

      on_exit(fn -> File.rm(path) end)
      File.write!(path, bin)

      points = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert length(points) == 2
      assert_in_delta hd(points).x, 1.25, 0.0001
      assert hd(points).color == {1, 2, 3}
    end

    test "streams Gaussian ASCII PLY as Gaussians" do
      cloud = GaussianCloud.new([Gaussian.new({1.0, 2.0, 3.0}, opacity: 0.7)])
      assert {:ok, bin} = PLY.encode(cloud, format: :ascii)

      path =
        Path.join(
          System.tmp_dir!(),
          "ex_codecs_ply_gauss_stream_#{System.unique_integer([:positive])}.ply"
        )

      on_exit(fn -> File.rm(path) end)
      File.write!(path, bin)

      assert [%Gaussian{} = g] = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert_in_delta g.opacity, 0.7, 0.0001
    end

    test "truncated binary body yields invalid_data" do
      cloud = PointCloud.new([Point.new(1.0, 2.0, 3.0), Point.new(4.0, 5.0, 6.0)])
      assert {:ok, bin} = PLY.encode(cloud, ply_format: :binary_le)
      truncated = binary_part(bin, 0, byte_size(bin) - 4)

      path =
        Path.join(
          System.tmp_dir!(),
          "ex_codecs_ply_trunc_#{System.unique_integer([:positive])}.ply"
        )

      on_exit(fn -> File.rm(path) end)
      File.write!(path, truncated)

      items = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert Enum.any?(items, &match?({:error, %{reason: :invalid_data, codec: :ply}}, &1))
    end
  end
end
