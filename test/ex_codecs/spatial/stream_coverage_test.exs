defmodule ExCodecs.Spatial.StreamCoverageTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}
  alias ExCodecs.Spatial.Codec.{Binary, Gsplat, PLY}
  alias ExCodecs.Spatial.Stream, as: SpatialStream

  defp tmp(ext) do
    Path.join(
      System.tmp_dir!(),
      "ex_codecs_stream_cov_#{System.unique_integer([:positive])}#{ext}"
    )
  end

  describe "Binary stream_encode_to_file edges" do
    test "rejects non-Point elements" do
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)

      assert {:error, %{reason: :invalid_data, codec: :spatial_binary}} =
               Binary.stream_encode_to_file([Point.new(0, 0, 0), :nope], path, schema: [])
    end

    test "accepts map schema, keyword schema, alpha, and nil color fill" do
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)

      assert :ok =
               Binary.stream_encode_to_file([Point.new(1, 2, 3)], path,
                 schema: %{color: true, normal: false}
               )

      assert :ok =
               Binary.stream_encode_to_file(
                 [Point.new(1, 2, 3, color: {1, 2, 3, 4}, normal: {0, 1, 0})],
                 path,
                 schema: [color: true, alpha: true, normal: true]
               )

      assert {:ok, decoded} = Binary.decode(File.read!(path))
      assert hd(decoded.points).color == {1, 2, 3, 4}

      assert :ok =
               Binary.stream_encode_to_file([Point.new(9, 8, 7)], path, schema: [:color, :alpha])

      assert {:ok, filled} = Binary.decode(File.read!(path))
      assert hd(filled.points).color == {0, 0, 0, 255}
    end

    test "rejects unknown and non-list/map schemas and unwritable paths" do
      assert {:error, %{reason: :invalid_options}} =
               Binary.stream_encode_to_file([Point.new(0, 0, 0)], tmp(".excp"), schema: [:bogus])

      assert {:error, %{reason: :invalid_options}} =
               Binary.stream_encode_to_file([Point.new(0, 0, 0)], tmp(".excp"), schema: [foo: true])

      assert {:error, %{reason: :invalid_options}} =
               Binary.stream_encode_to_file([Point.new(0, 0, 0)], tmp(".excp"), schema: :color)

      assert {:error, %{reason: :io_error}} =
               Binary.stream_encode_to_file([Point.new(0, 0, 0)], "/no/such/dir/x.excp", schema: [])
    end
  end

  describe "Binary stream_decode file edges" do
    test "unsupported version, empty file, short header, eof after full record" do
      bad_ver = tmp(".excp")
      empty = tmp(".excp")
      short = tmp(".excp")
      eof_mid = tmp(".excp")
      on_exit(fn -> Enum.each([bad_ver, empty, short, eof_mid], &File.rm/1) end)

      File.write!(
        bad_ver,
        <<"EXCP", 99::little-unsigned-16, 0::little-unsigned-16, 1::little-unsigned-64>>
      )

      File.write!(empty, "")
      File.write!(short, "EXCP")

      # count=2 but only one xyz record → second read hits :eof
      one = <<1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32>>

      File.write!(
        eof_mid,
        <<"EXCP", 1::little-unsigned-16, 0::little-unsigned-16, 2::little-unsigned-64, one::binary>>
      )

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(bad_ver, source: :file) |> Enum.to_list()

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(empty, source: :file) |> Enum.to_list()

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(short, source: :file) |> Enum.to_list()

      items = Binary.stream_decode(eof_mid, source: :file) |> Enum.to_list()
      assert match?([%Point{}, {:error, %{reason: :invalid_data}}], items)
    end

    test "early halt closes open file handle" do
      cloud = PointCloud.new([Point.new(1, 2, 3), Point.new(4, 5, 6)])
      {:ok, bin} = Binary.encode(cloud)
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)
      File.write!(path, bin)

      assert [%Point{}] =
               Binary.stream_decode(path, source: :file) |> Stream.take(1) |> Enum.to_list()
    end

    test "source: :binary and alpha stride decode from file" do
      cloud = PointCloud.new([Point.new(1, 2, 3, color: {1, 2, 3, 4})])
      {:ok, bin} = Binary.encode(cloud)
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)
      File.write!(path, bin)

      assert [%Point{color: {1, 2, 3, 4}}] =
               Binary.stream_decode(bin, source: :binary) |> Enum.to_list()

      assert [%Point{color: {1, 2, 3, 4}}] =
               Binary.stream_decode(path, source: :file) |> Enum.to_list()
    end

    test "schema color without alpha zero-fills missing RGB and keeps RGB triples" do
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)

      assert :ok =
               Binary.stream_encode_to_file([Point.new(1, 2, 3)], path, schema: [:color])

      assert {:ok, decoded} = Binary.decode(File.read!(path))
      assert hd(decoded.points).color == {0, 0, 0}

      assert :ok =
               Binary.stream_encode_to_file(
                 [Point.new(1, 2, 3, color: {9, 8, 7}), Point.new(0, 0, 0, color: {1, 2, 3, 4})],
                 path,
                 schema: [:color]
               )

      assert {:ok, colored} = Binary.decode(File.read!(path))
      assert Enum.map(colored.points, & &1.color) == [{9, 8, 7}, {1, 2, 3}]
    end

    test "schema keyword tuples cover known and unknown keys" do
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)

      assert :ok =
               Binary.stream_encode_to_file([Point.new(1, 2, 3)], path,
                 schema: [{:color, true}, {:normal, false}]
               )

      assert {:error, %{reason: :invalid_options}} =
               Binary.stream_encode_to_file([Point.new(1, 2, 3)], path,
                 schema: [{:color, true}, {:wat, true}]
               )
    end
  end

  describe "Gsplat stream_encode_to_file edges" do
    test "rejects non-Gaussian elements and bad schemas" do
      path = tmp(".gspl")
      on_exit(fn -> File.rm(path) end)

      assert {:error, %{reason: :invalid_data, codec: :gsplat}} =
               Gsplat.stream_encode_to_file([Gaussian.new({0, 0, 0}), :nope], path, schema: [])

      assert {:error, %{reason: :invalid_options}} =
               Gsplat.stream_encode_to_file([Gaussian.new({0, 0, 0})], path, schema: [:bogus])

      assert {:error, %{reason: :invalid_options}} =
               Gsplat.stream_encode_to_file([Gaussian.new({0, 0, 0})], path, schema: [sh_rest: -1])

      assert {:error, %{reason: :invalid_options}} =
               Gsplat.stream_encode_to_file([Gaussian.new({0, 0, 0})], path, schema: "nope")

      assert {:error, %{reason: :io_error}} =
               Gsplat.stream_encode_to_file([Gaussian.new({0, 0, 0})], "/no/such/dir/x.gspl",
                 schema: []
               )
    end

    test "map schema and sh_rest round-trip" do
      path = tmp(".gspl")
      on_exit(fn -> File.rm(path) end)

      g =
        Gaussian.new({1.0, 2.0, 3.0},
          color: {0.1, 0.2, 0.3},
          sh: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
        )

      assert :ok = Gsplat.stream_encode_to_file([g], path, schema: %{sh_rest: 3})
      assert {:ok, decoded} = Gsplat.decode(File.read!(path))
      assert length(decoded.gaussians) == 1

      assert :ok = Gsplat.stream_encode_to_file([g], path, schema: [:sh_rest])
    end
  end

  describe "Gsplat stream_decode file edges" do
    test "unsupported version, empty, short header, eof after full record" do
      bad_ver = tmp(".gspl")
      empty = tmp(".gspl")
      short = tmp(".gspl")
      eof_mid = tmp(".gspl")
      on_exit(fn -> Enum.each([bad_ver, empty, short, eof_mid], &File.rm/1) end)

      File.write!(
        bad_ver,
        <<"GSPL", 9::little-unsigned-16, 0::little-unsigned-16, 1::little-unsigned-64,
          0::little-unsigned-16>>
      )

      File.write!(empty, "")
      File.write!(short, "GSPL")

      zeros = :binary.copy(<<0>>, 56)

      File.write!(
        eof_mid,
        <<"GSPL", 1::little-unsigned-16, 0::little-unsigned-16, 2::little-unsigned-64,
          0::little-unsigned-16, zeros::binary>>
      )

      assert [{:error, %{reason: :invalid_data}}] =
               Gsplat.stream_decode(bad_ver, source: :file) |> Enum.to_list()

      assert [{:error, %{reason: :invalid_data}}] =
               Gsplat.stream_decode(empty, source: :file) |> Enum.to_list()

      assert [{:error, %{reason: :invalid_data}}] =
               Gsplat.stream_decode(short, source: :file) |> Enum.to_list()

      items = Gsplat.stream_decode(eof_mid, source: :file) |> Enum.to_list()
      assert match?([%Gaussian{}, {:error, %{reason: :invalid_data}}], items)
    end

    test "early halt and source: :binary" do
      cloud = GaussianCloud.new([Gaussian.new({0, 0, 0}), Gaussian.new({1, 1, 1})])
      {:ok, bin} = Gsplat.encode(cloud)
      path = tmp(".gspl")
      on_exit(fn -> File.rm(path) end)
      File.write!(path, bin)

      assert [%Gaussian{}] =
               Gsplat.stream_decode(path, source: :file) |> Stream.take(1) |> Enum.to_list()

      assert [%Gaussian{}, %Gaussian{}] =
               Gsplat.stream_decode(bin, source: :binary) |> Enum.to_list()
    end
  end

  describe "PLY stream_decode file edges" do
    test "truncated ascii body and blank lines" do
      path = tmp(".ply")
      on_exit(fn -> File.rm(path) end)

      File.write!(path, """
      ply
      format ascii 1.0
      element vertex 2
      property float x
      property float y
      property float z
      end_header
      1.0 2.0 3.0

      """)

      items = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert match?([%Point{}, {:error, %{reason: :invalid_data}}], items)
    end

    test "ascii early halt closes open handle" do
      cloud = PointCloud.new([Point.new(1, 2, 3), Point.new(4, 5, 6)])
      {:ok, bin} = PLY.encode(cloud, format: :ascii)
      path = tmp(".ply")
      on_exit(fn -> File.rm(path) end)
      File.write!(path, bin)

      assert [%Point{}] =
               PLY.stream_decode(path, source: :file) |> Stream.take(1) |> Enum.to_list()
    end

    test "ascii last vertex without trailing newline" do
      path = tmp(".ply")
      on_exit(fn -> File.rm(path) end)

      File.write!(
        path,
        "ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n1.5 2.5 3.5"
      )

      assert [%Point{x: x}] = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert_in_delta x, 1.5, 0.0001
    end

    test "corrupt header after end_header marker and oversized header" do
      bad = tmp(".ply")
      huge = tmp(".ply")
      on_exit(fn -> Enum.each([bad, huge], &File.rm/1) end)

      File.write!(bad, "notply\nend_header\n")

      assert [{:error, %{reason: :invalid_data}}] =
               PLY.stream_decode(bad, source: :file) |> Enum.to_list()

      # > 1 MiB without end_header
      File.write!(huge, ["ply\nformat ascii 1.0\n"] ++ List.duplicate("comment pad\n", 90_000))

      assert [{:error, %{reason: :invalid_data, message: message}}] =
               PLY.stream_decode(huge, source: :file) |> Enum.to_list()

      assert message =~ "exceeds"
    end

    test "empty file, early halt, and binary_be stream" do
      empty = tmp(".ply")
      be = tmp(".ply")
      on_exit(fn -> Enum.each([empty, be], &File.rm/1) end)

      File.write!(empty, "")

      assert [{:error, %{reason: :invalid_data}}] =
               PLY.stream_decode(empty, source: :file) |> Enum.to_list()

      cloud = PointCloud.new([Point.new(1, 2, 3), Point.new(4, 5, 6)])
      {:ok, bin} = PLY.encode(cloud, ply_format: :binary_be)
      File.write!(be, bin)

      assert [%Point{}] =
               PLY.stream_decode(be, source: :file) |> Stream.take(1) |> Enum.to_list()

      assert [%Point{}, %Point{}] =
               PLY.stream_decode(be, source: :file) |> Enum.to_list()
    end

    test "missing end_header at eof" do
      path = tmp(".ply")
      on_exit(fn -> File.rm(path) end)
      File.write!(path, "ply\nformat ascii 1.0\nelement vertex 0\n")

      assert [{:error, %{reason: :invalid_data}}] =
               PLY.stream_decode(path, source: :file) |> Enum.to_list()
    end

    test "binary body split across header-scan chunk boundary" do
      path = tmp(".ply")
      on_exit(fn -> File.rm(path) end)

      # First 4096-byte read ends with end_header + 4 body bytes (< 12-byte stride);
      # the rest of the vertex is in the next read (covers take_exact_bytes refill).
      header = """
      ply
      format binary_little_endian 1.0
      element vertex 1
      property float x
      property float y
      property float z
      end_header
      """

      body = <<1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32>>
      pad_len = 4096 - byte_size(header) - 4
      assert pad_len > 0
      # comments must appear before end_header — pad inside header instead
      comment = "comment " <> String.duplicate("p", 60) <> "\n"

      base =
        "ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\n"

      suffix = "end_header\n"
      need = 4096 - 4 - byte_size(base) - byte_size(suffix)
      comments = String.duplicate(comment, div(need, byte_size(comment)) + 2)
      header2 = base <> binary_part(comments, 0, need) <> suffix
      assert byte_size(header2) == 4096 - 4

      File.write!(path, header2 <> body)

      assert [%Point{x: x}] = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert_in_delta x, 1.0, 0.0001
    end

    test "ascii vertex line split across read chunks" do
      path = tmp(".ply")
      on_exit(fn -> File.rm(path) end)

      base = """
      ply
      format ascii 1.0
      element vertex 1
      property float x
      property float y
      property float z
      """

      suffix = "end_header\n"
      # Leave "1.0 2.0 3" in the first 4096 chunk and "0\n" in the next.
      partial = "1.0 2.0 3"
      rest = "0\n"
      need = 4096 - byte_size(base) - byte_size(suffix) - byte_size(partial)
      comments = String.duplicate("comment padline\n", div(need, 16) + 2)
      header = base <> binary_part(comments, 0, need) <> suffix
      assert byte_size(header <> partial) == 4096

      File.write!(path, header <> partial <> rest)

      assert [%Point{z: z}] = PLY.stream_decode(path, source: :file) |> Enum.to_list()
      assert_in_delta z, 30.0, 0.0001
    end
  end

  describe "Spatial.Stream encode_to_file schema routing" do
    test "streams GSPL from GaussianCloud and rejects unsupported format" do
      path = tmp(".gspl")
      list_path = tmp(".gspl")
      on_exit(fn -> Enum.each([path, list_path], &File.rm/1) end)
      cloud = %GaussianCloud{gaussians: [Gaussian.new({1.0, 2.0, 3.0})]}

      assert :ok =
               SpatialStream.encode_to_file(cloud, path, format: :gsplat, schema: [sh_rest: 0])

      assert [%Gaussian{}] =
               Spatial.stream_decode(path, format: :gsplat, source: :file) |> Enum.to_list()

      assert :ok =
               SpatialStream.encode_to_file([Gaussian.new({0.0, 1.0, 2.0})], list_path,
                 format: :gsplat,
                 schema: []
               )

      assert {:error, %{reason: :unsupported_codec}} =
               SpatialStream.encode_to_file([Point.new(0, 0, 0)], tmp(".bin"),
                 format: :sog,
                 schema: []
               )
    end

    test "streams EXCP from PointCloud" do
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)
      cloud = PointCloud.new([Point.new(1, 2, 3, color: {9, 8, 7})])

      assert :ok =
               SpatialStream.encode_to_file(cloud, path,
                 format: :spatial_binary,
                 schema: [:color]
               )

      assert [%Point{color: {9, 8, 7}}] =
               Spatial.stream_decode(path, format: :spatial_binary, source: :file)
               |> Enum.to_list()
    end
  end
end
