defmodule ExCodecs.CoverageBoostTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Compression.{Bzip2, Lz4, Snappy, Zstd}
  alias ExCodecs.NIF
  alias ExCodecs.Spatial
  alias ExCodecs.Spatial.Codec.{Binary, Gsplat, PLY}
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}
  alias ExCodecs.Spatial.Stream, as: SpatialStream

  describe "point cloud bounds expansion and add_points" do
    test "expands existing bounds and bulk-adds points" do
      cloud = PointCloud.new([Point.new(0, 0, 0)])
      cloud = PointCloud.add_point(cloud, Point.new(2, -1, 3))
      assert cloud.bounds.min_x == 0.0
      assert cloud.bounds.max_x == 2.0
      assert cloud.bounds.min_y == -1.0
      assert cloud.bounds.max_z == 3.0

      cloud = PointCloud.add_points(cloud, [Point.new(5, 5, 5), Point.new(-2, 0, 0)])
      assert PointCloud.size(cloud) == 4
      assert cloud.bounds.max_x == 5.0
      assert cloud.bounds.min_x == -2.0
    end
  end

  describe "compression invalid_data catch-alls" do
    test "encode/decode reject non-binaries" do
      for {mod, codec} <- [
            {Zstd, :zstd},
            {Lz4, :lz4},
            {Snappy, :snappy},
            {Bzip2, :bzip2}
          ] do
        assert {:error, %ExCodecs.Error{reason: :invalid_data, codec: ^codec}} =
                 mod.encode(123, [])

        assert {:error, %ExCodecs.Error{reason: :invalid_data, codec: ^codec}} =
                 mod.decode(123, [])
      end
    end
  end

  describe "top-level catch-alls and NIF helpers" do
    test "encode/decode reject completely invalid argument shapes" do
      assert {:error, %ExCodecs.Error{reason: :invalid_data}} =
               ExCodecs.encode("not-an-atom", "data")

      assert {:error, %ExCodecs.Error{reason: :invalid_data}} =
               ExCodecs.decode("not-an-atom", "data")
    end

    test "NIF wrap and safe_call edge paths" do
      assert NIF.default_max_output_size() == 268_435_456

      assert {:error, %ExCodecs.Error{reason: :invalid_data, message: message}} =
               NIF.wrap(:zstd, :unexpected)

      assert message =~ "Unexpected NIF return"

      assert {:error, %ExCodecs.Error{reason: :nif_not_loaded, codec: :lz4}} =
               NIF.safe_call(:lz4, fn -> raise ErlangError, original: :nif_not_loaded end)

      assert {:error, %ExCodecs.Error{reason: :invalid_data, codec: :lz4, details: :boom}} =
               NIF.safe_call(:lz4, fn -> raise ErlangError, original: :boom end)

      assert {:error, %ExCodecs.Error{reason: :invalid_data, codec: :snappy, message: msg}} =
               NIF.safe_call(:snappy, fn -> raise ArgumentError, message: "bad arg" end)

      assert msg =~ "bad arg"
    end
  end

  describe "spatial stream edges" do
    test "missing format and file/binary source resolution" do
      assert [{:error, %{reason: :invalid_options}}] =
               SpatialStream.decode(<<"ply">>, []) |> Enum.to_list()

      assert {:error, %{reason: :invalid_options}} =
               SpatialStream.encode([Point.new(0, 0, 0)], [])

      path =
        Path.join(System.tmp_dir!(), "ex_codecs_cov_#{System.unique_integer([:positive])}.excp")

      on_exit(fn -> File.rm(path) end)

      cloud = PointCloud.new([Point.new(1, 2, 3)])
      assert :ok = SpatialStream.encode_to_file(cloud, path, format: :spatial_binary)

      assert [%Point{}] =
               Spatial.stream_decode(path, format: :spatial_binary, source: :file)
               |> Enum.to_list()

      {:ok, bin} = Spatial.encode(cloud, format: :spatial_binary)

      assert [%Point{}] =
               Spatial.stream_decode(bin, format: :spatial_binary, source: :binary)
               |> Enum.to_list()

      assert [{:error, %{reason: :io_error}}] =
               Spatial.stream_decode("/no/such/ex_codecs_file.excp",
                 format: :spatial_binary,
                 source: :file
               )
               |> Enum.to_list()

      assert [{:error, %{reason: :io_error}}] =
               Spatial.stream_decode("/no/such/ex_codecs_file.gspl",
                 format: :gsplat,
                 source: :file
               )
               |> Enum.to_list()
    end
  end

  describe "binary codec nil-color and truncation" do
    test "encodes mixed color presence and rejects truncated payloads" do
      rgb_cloud =
        PointCloud.new([
          Point.new(0, 0, 0, color: {1, 2, 3}),
          Point.new(1, 1, 1)
        ])

      assert {:ok, rgb_bin} = Binary.encode(rgb_cloud)
      assert {:ok, _} = Binary.decode(rgb_bin)

      rgba_cloud =
        PointCloud.new([
          Point.new(0, 0, 0, color: {1, 2, 3, 4}),
          Point.new(1, 1, 1, color: {5, 6, 7}),
          Point.new(2, 2, 2)
        ])

      assert {:ok, rgba_bin} = Binary.encode(rgba_cloud)
      assert {:ok, decoded} = Binary.decode(rgba_bin)
      assert length(decoded.points) == 3

      normal_cloud =
        PointCloud.new([
          Point.new(0, 0, 0, normal: {0.0, 1.0, 0.0}),
          Point.new(1, 1, 1)
        ])

      assert {:ok, _} = Binary.encode(normal_cloud)

      # flags: color
      assert {:error, %{message: message}} =
               Binary.decode(
                 <<"EXCP", 1::little-16, 1::little-16, 1::little-64, 0::float-32-little,
                   0::float-32-little, 0::float-32-little, 1, 2>>
               )

      assert message =~ "Truncated RGB"

      # flags: alpha
      assert {:error, %{message: message}} =
               Binary.decode(
                 <<"EXCP", 1::little-16, 3::little-16, 1::little-64, 0::float-32-little,
                   0::float-32-little, 0::float-32-little, 1, 2, 3>>
               )

      assert message =~ "Truncated RGBA"

      # flags: normal
      assert {:error, %{message: message}} =
               Binary.decode(
                 <<"EXCP", 1::little-16, 4::little-16, 1::little-64, 0::float-32-little,
                   0::float-32-little, 0::float-32-little, 1, 2, 3>>
               )

      assert message =~ "Truncated normal"
    end
  end

  describe "gsplat SH list shapes" do
    test "encodes flat SH lists and rejects truncated SH payloads" do
      g =
        struct(Gaussian,
          position: {0.0, 0.0, 0.0},
          color: {0.1, 0.2, 0.3},
          sh: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        )

      cloud = GaussianCloud.new([g])
      assert {:ok, bin} = Gsplat.encode(cloud, accel: false)
      # Flat SH must drop 3 DC floats → sh_rest=3 (not 5 from dropping only the head).
      assert byte_size(bin) == 18 + 56 + 12
      assert {:ok, decoded} = Gsplat.decode(bin, accel: false)
      assert [[_, _, _], [r1, r2, r3]] = hd(decoded.gaussians).sh
      assert_in_delta r1, 0.4, 1.0e-6
      assert_in_delta r2, 0.5, 1.0e-6
      assert_in_delta r3, 0.6, 1.0e-6

      # Valid header with one gaussian requiring SH floats that are missing.
      header = <<"GSPL", 1::little-16, 0::little-16, 1::little-64, 3::little-16>>
      base = :binary.copy(<<0::float-32-little>>, 14)
      assert {:error, %{message: message}} = Gsplat.decode(header <> base <> <<1, 2>>)
      assert message =~ "Truncated SH"
    end
  end

  describe "PLY typed encode/decode coverage" do
    test "format aliases, property aliases, and mixed binary types" do
      cloud = PointCloud.new([Point.new(1, 2, 3)])

      assert {:ok, _} = PLY.encode(cloud, format: :binary_le)
      assert {:ok, _} = PLY.encode(cloud, format: :little)
      assert {:ok, _} = PLY.encode(cloud, format: :big)

      assert {:error, %{reason: :invalid_options}} =
               PLY.encode(cloud, format: :unknown_defaults_ascii)

      assert {:error, %{reason: :invalid_data}} = PLY.decode(123)

      ascii = """
      ply
      format ascii 1.0
      element vertex 1
      property float32 x
      property float32 y
      property float32 z
      property int8 tiny
      property uint8 utiny
      property int16 s16
      property uint16 u16
      property int32 i32
      property uint32 u32
      property float64 d
      end_header
      1 2 3 -1 2 -3 4 -5 6 7.5
      """

      assert {:ok, decoded} = PLY.decode(ascii)
      attrs = hd(decoded.points).attributes
      assert attrs["tiny"] == -1
      assert attrs["utiny"] == 2
      assert attrs["d"] == 7.5

      le_header = """
      ply
      format binary_little_endian 1.0
      element vertex 1
      property double x
      property double y
      property double z
      property char tiny
      property ushort code
      property short delta
      property uint big
      property int label
      end_header
      """

      le_body =
        <<1.0::little-float-64, 2.0::little-float-64, 3.0::little-float-64, -2::signed-8,
          9::little-unsigned-16, -4::little-signed-16, 11::little-unsigned-32,
          12::little-signed-32>>

      assert {:ok, le_cloud} = PLY.decode(le_header <> le_body)
      assert hd(le_cloud.points).attributes["label"] == 12

      be_header = """
      ply
      format binary_big_endian 1.0
      element vertex 1
      property double x
      property double y
      property double z
      property short delta
      property uint big
      property int label
      end_header
      """

      be_body =
        <<1.0::big-float-64, 2.0::big-float-64, 3.0::big-float-64, -4::big-signed-16,
          11::big-unsigned-32, 12::big-signed-32>>

      assert {:ok, be_cloud} = PLY.decode(be_header <> be_body)
      assert hd(be_cloud.points).attributes["big"] == 11
    end

    test "encode rescue paths, header helpers, and stream sources" do
      bad_point_cloud =
        PointCloud.new([Point.new(0, 0, 0, attributes: %{"intensity" => :not_a_number})])

      assert {:error, %{message: message}} = PLY.encode(bad_point_cloud, format: :binary)
      assert message =~ "PLY encode failed"

      bad_gaussian =
        %GaussianCloud{
          gaussians: [
            struct(Gaussian, position: {0.0, 0.0, 0.0}, sh: :not_a_list)
          ]
        }

      assert {:error, %{message: message}} = PLY.encode(bad_gaussian)
      assert message =~ "PLY encode failed"

      assert {:ok, _parsed, _body} =
               PLY.decode_header_and_body("""
               ply
               format ascii 1.0
               element vertex 0
               end_header
               """)

      path =
        Path.join(System.tmp_dir!(), "ex_codecs_ply_cov_#{System.unique_integer([:positive])}.ply")

      on_exit(fn -> File.rm(path) end)
      {:ok, bin} = PLY.encode(PointCloud.new([Point.new(0, 0, 1)]))
      File.write!(path, bin)

      assert [%Point{}] = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert [%Point{}] = PLY.stream_decode(bin, source: :binary) |> Enum.to_list()

      assert [{:error, %{reason: :io_error}}] =
               PLY.stream_decode("/no/such/ply_cov.ply", source: :file) |> Enum.to_list()

      # Corrupt file contents through the file stream path.
      File.write!(path, "not-ply")

      assert [{:error, %{reason: :invalid_data}}] =
               PLY.stream_decode(path, source: :file) |> Enum.to_list()
    end

    test "gaussian stream decode and sparse attributes" do
      gcloud = GaussianCloud.new([Gaussian.new({0.0, 1.0, 2.0})])
      {:ok, gbin} = PLY.encode(gcloud, format: :ascii)
      assert [%Gaussian{}] = PLY.stream_decode(gbin) |> Enum.to_list()

      cloud =
        GaussianCloud.new([
          struct(Gaussian, position: {0.0, 1.0, 2.0}, sh: nil),
          struct(Gaussian, position: {1.0, 1.0, 1.0}, sh: [])
        ])

      assert {:ok, bin} = PLY.encode(cloud, format: :ascii)
      assert {:ok, _} = PLY.decode(bin, as: :gaussian_cloud)

      assert {:ok, gspl} =
               Gsplat.encode(
                 GaussianCloud.new([struct(Gaussian, position: {0.0, 0.0, 0.0}, sh: [])])
               )

      assert {:ok, _} = Gsplat.decode(gspl)

      sparse =
        PointCloud.new([
          Point.new(0, 0, 0, attributes: %{"intensity" => 1.0}),
          Point.new(1, 1, 1)
        ])

      assert {:ok, _} = PLY.encode(sparse, format: :ascii)

      assert {:error, %{reason: :invalid_data}} =
               PLY.decode("""
               ply
               format ascii 1.0
               element vertex 1
               property float x
               property float y
               property float z
               property float weird
               end_header
               1 2 3 not-a-number
               """)

      assert {:ok, _} =
               PLY.decode("ply\nformat ascii 1.0\nelement vertex 0\nend_header")

      assert {:error, _} =
               PLY.decode("""
               ply
               format ascii 1.0
               element vertex 1
               property float x
               property float y
               property float z
               property notatype name
               end_header
               1 2 3 4
               """)

      assert {:error, _} =
               PLY.decode("""
               ply
               format ascii 1.0
               element vertex nope
               property float x
               property float y
               property float z
               end_header
               """)

      assert {:error, _} =
               PLY.decode("""
               ply
               format ascii 1.0
               element vertex -1
               property float x
               property float y
               property float z
               end_header
               """)

      # Extra tokens on the element vertex line.
      assert {:error, %{message: "Malformed element vertex line in PLY"}} =
               PLY.decode("""
               ply
               format ascii 1.0
               element vertex 1 extra
               property float x
               end_header
               1
               """)

      # Property line missing its name.
      assert {:error, %{message: "Invalid PLY property"}} =
               PLY.decode("""
               ply
               format ascii 1.0
               element vertex 1
               property float
               end_header
               1
               """)

      path =
        Path.join(System.tmp_dir!(), "ex_codecs_auto_#{System.unique_integer([:positive])}.excp")

      on_exit(fn -> File.rm(path) end)
      {:ok, excp} = Spatial.encode(PointCloud.new([Point.new(1, 2, 3)]), format: :spatial_binary)
      File.write!(path, excp)

      assert [%Point{}] =
               Spatial.stream_decode(path, format: :spatial_binary, source: :file)
               |> Enum.to_list()
    end
  end
end
