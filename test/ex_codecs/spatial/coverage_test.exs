defmodule ExCodecs.Spatial.CoverageTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial
  alias ExCodecs.Spatial.{Bounds, Gaussian, GaussianCloud, Metadata, Point, PointCloud}
  alias ExCodecs.Spatial.Codec.{Binary, Gsplat, PLY}
  alias ExCodecs.Spatial.Stream, as: SpatialStream

  describe "binary codec edges" do
    test "xyz-only round-trip" do
      cloud = PointCloud.new([Point.new(1.0, 2.0, 3.0), Point.new(4.0, 5.0, 6.0)])
      assert {:ok, bin} = Binary.encode(cloud)
      assert {:ok, decoded} = Binary.decode(bin)
      assert Enum.map(decoded.points, & &1.color) == [nil, nil]
    end

    test "unsupported version and truncation" do
      assert {:error, _} = Binary.decode(<<"EXCP", 99::little-16, 0::little-16, 1::little-64>>)
      assert {:error, _} = Binary.decode(<<"EXCP", 1::little-16, 1::little-16, 1::little-64, 0, 1>>)

      assert [{:error, _}] =
               Binary.stream_decode(<<"nope">>) |> Enum.to_list()
    end

    test "encode rejects non-cloud" do
      assert {:error, %{codec: :spatial_binary}} = Binary.encode(%{})
    end
  end

  describe "gsplat edges" do
    test "unsupported version and truncation" do
      assert {:error, _} =
               Gsplat.decode(<<"GSPL", 9::little-16, 0::little-16, 1::little-64, 0::little-16>>)

      assert {:error, _} =
               Gsplat.decode(
                 <<"GSPL", 1::little-16, 0::little-16, 1::little-64, 0::little-16, 1, 2>>
               )

      assert [{:error, _}] = Gsplat.stream_decode(<<"nope">>) |> Enum.to_list()
      assert {:error, _} = Gsplat.encode(%{})
    end
  end

  describe "PLY typed properties" do
    test "ascii double / int / uchar mix" do
      data = """
      ply
      format ascii 1.0
      comment typed
      element vertex 1
      property double x
      property double y
      property double z
      property int label
      property ushort code
      property short delta
      property uint big
      property char tiny
      end_header
      1.0 2.0 3.0 7 100  -3  999  -1
      """

      assert {:ok, cloud} = PLY.decode(data)
      [p] = cloud.points
      assert_in_delta p.x, 1.0, 0.0001
      assert p.attributes["label"] == 7
    end

    test "binary_le with mixed numeric types" do
      # Build via encode then is float/uchar; craft header+body manually for doubles
      x = 1.25
      y = 2.5
      z = 3.75
      label = 42

      header = """
      ply
      format binary_little_endian 1.0
      element vertex 1
      property float x
      property float y
      property float z
      property int label
      end_header
      """

      body =
        <<x::little-float-32, y::little-float-32, z::little-float-32, label::little-signed-32>>

      assert {:ok, cloud} = PLY.decode(header <> body)
      assert hd(cloud.points).attributes["label"] == 42
    end

    test "binary_be floats" do
      header = """
      ply
      format binary_big_endian 1.0
      element vertex 1
      property float x
      property float y
      property float z
      property ushort code
      property uchar red
      property uchar green
      property uchar blue
      end_header
      """

      body =
        <<1.0::big-float-32, 2.0::big-float-32, 3.0::big-float-32, 7::big-unsigned-16, 10, 20, 30>>

      assert {:ok, cloud} = PLY.decode(header <> body)
      assert hd(cloud.points).color == {10, 20, 30}
      assert hd(cloud.points).attributes["code"] == 7
    end

    test "missing magic / format / vertex element" do
      assert {:error, _} = PLY.decode("format ascii 1.0\nend_header\n")
      assert {:error, _} = PLY.decode("ply\nelement vertex 0\nend_header\n")

      assert {:error, _} =
               PLY.decode("ply\nformat ascii 1.0\nend_header\n")
    end

    test "list properties unsupported" do
      data = """
      ply
      format ascii 1.0
      element vertex 0
      property list uchar int vertex_indices
      end_header
      """

      assert {:error, _} = PLY.decode(data)
    end

    test "stream_decode file path" do
      path = Path.join(System.tmp_dir!(), "ex_codecs_ply_#{System.unique_integer([:positive])}.ply")
      on_exit(fn -> File.rm(path) end)

      cloud = PointCloud.new([Point.new(9.0, 8.0, 7.0)])
      {:ok, bin} = PLY.encode(cloud)
      File.write!(path, bin)

      assert [%Point{x: x}] = PLY.stream_decode(path) |> Enum.to_list()
      assert_in_delta x, 9.0, 0.0001
    end

    test "Gaussian ascii with f_rest" do
      cloud =
        GaussianCloud.new([
          Gaussian.new({0, 0, 0}, sh: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6], [0.7, 0.8, 0.9]])
        ])

      assert {:ok, bin} = PLY.encode(cloud, format: :ascii, comments: ["sh test"])
      assert bin =~ "f_rest_0"
      assert {:ok, decoded} = PLY.decode(bin, as: :gaussian_cloud)
      assert hd(decoded.gaussians).sh != nil
    end
  end

  describe "stream helpers" do
    test "encode_to_file with enumerable and bad path" do
      path = Path.join(System.tmp_dir!(), "ex_codecs_pts_#{System.unique_integer([:positive])}.ply")
      on_exit(fn -> File.rm(path) end)

      assert :ok =
               SpatialStream.encode_to_file([Point.new(1, 2, 3)], path, format: :ply)

      assert {:error, _} =
               SpatialStream.encode_to_file([Point.new(1, 2, 3)], "/no/such/dir/x.ply",
                 format: :ply
               )
    end

    test "stream_decode reads spatial_binary file" do
      path =
        Path.join(System.tmp_dir!(), "ex_codecs_bin_#{System.unique_integer([:positive])}.excp")

      on_exit(fn -> File.rm(path) end)

      {:ok, bin} = Spatial.encode(PointCloud.new([Point.new(1, 2, 3)]), format: :spatial_binary)
      File.write!(path, bin)

      assert [%Point{}] =
               Spatial.stream_decode(path, format: :spatial_binary) |> Enum.to_list()
    end

    test "stream encode error tuples" do
      assert {:error, _} =
               Spatial.stream_encode([{:error, :boom}], format: :ply)
    end

    test "unsupported empty format" do
      assert {:error, %{reason: :unsupported_codec}} =
               Spatial.stream_encode([], format: :sog)
    end
  end

  describe "point cloud remaining branches" do
    test "explicit bounds and mixed color detection" do
      bounds = Bounds.new({0, 0, 0}, {1, 1, 1})

      cloud =
        PointCloud.new([Point.new(0, 0, 0, color: {1, 2, 3}), Point.new(1, 1, 1)],
          bounds: bounds,
          metadata: Metadata.new(comments: ["x"])
        )

      assert cloud.bounds == bounds
      refute PointCloud.colored?(cloud)
      refute PointCloud.has_normals?(cloud)
    end
  end

  describe "encode_to_file extras" do
    test "gaussian cloud and gsplat file stream" do
      path = Path.join(System.tmp_dir!(), "ex_codecs_g_#{System.unique_integer([:positive])}.gspl")
      on_exit(fn -> File.rm(path) end)

      cloud = GaussianCloud.new([Gaussian.new({1.0, 2.0, 3.0})])
      assert :ok = SpatialStream.encode_to_file(cloud, path, format: :gsplat)

      assert [%Gaussian{}] =
               Spatial.stream_decode(path, format: :gsplat) |> Enum.to_list()
    end

    test "propagates encode errors" do
      assert {:error, _} =
               SpatialStream.encode_to_file([Point.new(0, 0, 0)], "/tmp/x.gspl", format: :gsplat)
    end
  end
end
