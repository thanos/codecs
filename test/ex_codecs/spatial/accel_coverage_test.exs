defmodule ExCodecs.Spatial.AccelCoverageTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.Accel
  alias ExCodecs.Spatial.Codec.{Binary, Gsplat, PLY}
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}

  defp tmp(ext) do
    Path.join(
      System.tmp_dir!(),
      "ex_codecs_accel_cov_#{System.unique_integer([:positive])}#{ext}"
    )
  end

  setup do
    if Accel.available?() do
      :ok
    else
      {:skip, "spatial Accel NIF not loaded"}
    end
  end

  describe "Accel facade" do
    test "chunk_size, ply_type_tag, pack/unpack, mmap, and append_file" do
      assert Accel.chunk_size() == 4096

      for t <- [:char, :uchar, :short, :ushort, :int, :uint, :float, :double] do
        assert is_integer(Accel.ply_type_tag(t))
      end

      points = [
        Point.new(1.0, 2.0, 3.0, color: {1, 2, 3}, normal: {0.0, 1.0, 0.0}),
        Point.new(4.0, 5.0, 6.0)
      ]

      assert {:ok, body} = Accel.excp_pack(points, 0b101)
      assert {:ok, {decoded, _}} = Accel.excp_unpack(body, 0b101, 0, 10)
      assert length(decoded) == 2

      gs = [
        Gaussian.new({0.0, 0.0, 0.0}, sh: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]),
        struct(Gaussian,
          position: {1.0, 1.0, 1.0},
          color: {0.2, 0.3, 0.4},
          sh: [0.2, 0.3, 0.4, 0.5, 0.6, 0.7]
        )
      ]

      assert {:ok, gbody} = Accel.gspl_pack(gs, 3)
      assert {:ok, {gdecoded, _}} = Accel.gspl_unpack(gbody, 3, 0, 10)
      assert length(gdecoded) == 2

      # PLY binary body: 3 floats
      ply_body = <<1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32>>

      assert {:ok, {[[x, y, z]], _}} =
               Accel.ply_binary_unpack(ply_body, [:float, :float, :float], :binary_le, 0, 1)

      assert_in_delta x, 1.0, 1.0e-5
      assert_in_delta y, 2.0, 1.0e-5
      assert_in_delta z, 3.0, 1.0e-5

      assert {:ok, {[[_, _, _]], _}} =
               Accel.ply_binary_unpack(ply_body, [:float, :float, :float], true, 0, 1)

      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)
      {:ok, bin} = Binary.encode(PointCloud.new(points), accel: false)
      File.write!(path, bin)

      assert {:ok, ref} = Accel.mmap_open(path)
      assert {:ok, len} = Accel.mmap_len(ref)
      assert len == byte_size(bin)

      assert {:ok, {mmap_pts, _}} = Accel.excp_unpack_mmap(ref, 0b101, 16, 10)
      assert length(mmap_pts) == 2

      gpath = tmp(".gspl")
      on_exit(fn -> File.rm(gpath) end)
      {:ok, gbin} = Gsplat.encode(GaussianCloud.new(gs), accel: false)
      File.write!(gpath, gbin)
      assert {:ok, gref} = Accel.mmap_open(gpath)
      assert {:ok, _} = Accel.gspl_unpack_mmap(gref, 3, 18, 10)

      ppath = tmp(".ply")
      on_exit(fn -> File.rm(ppath) end)
      {:ok, pbin} = PLY.encode(PointCloud.new([Point.new(1, 2, 3)]), ply_format: :binary_le)
      File.write!(ppath, pbin)
      assert {:ok, pref} = Accel.mmap_open(ppath)
      # body offset after a typical small header — unpack may return 0 or more
      assert {:ok, {_rows, _}} =
               Accel.ply_binary_unpack_mmap(pref, [:float, :float, :float], :binary_le, 0, 1)

      append_path = tmp(".bin")
      on_exit(fn -> File.rm(append_path) end)
      assert :ok = Accel.append_file(append_path, <<"hello">>)
      assert File.read!(append_path) == "hello"

      assert {:error, _} = Accel.mmap_open("/no/such/ex_codecs_mmap")
      assert {:error, _} = Accel.append_file("/no/such/dir/x.bin", <<"x">>)
      # Short bodies yield an empty chunk (not a NIF error).
      assert {:ok, {[], _}} = Accel.excp_unpack(<<"short">>, 0, 0, 1)
      assert {:ok, {[], _}} = Accel.gspl_unpack(<<"short">>, 0, 0, 1)

      assert {:error, :invalid_data} = Accel.excp_pack([:not_a_point], 0)
      assert {:error, :invalid_data} = Accel.gspl_pack([:not_a_gaussian], 0)

      # Default arity / offset forms
      assert {:ok, {_, _}} = Accel.excp_unpack(body, 0b101)
      assert {:ok, {_, _}} = Accel.gspl_unpack(gbody, 3)
      assert {:ok, {_, _}} = Accel.ply_binary_unpack(ply_body, [:float, :float, :float], :little)
      assert {:ok, {_, _}} = Accel.excp_unpack_mmap(ref, 0b101)
      assert {:ok, {_, _}} = Accel.gspl_unpack_mmap(gref, 3)

      assert {:ok, {_, _}} =
               Accel.ply_binary_unpack_mmap(pref, [:float, :float, :float], :binary_be)

      # Bad resource / args exercise safe/1 rescue paths
      assert {:error, _} = Accel.mmap_len(:not_a_resource)
      assert {:error, _} = Accel.excp_unpack_mmap(:not_a_resource, 0, 0, 1)

      # Valid struct shape but invalid color for Rust pack → nif_binary error path
      bad = struct(Point, x: 1.0, y: 2.0, z: 3.0, color: :nope, normal: nil)
      assert {:error, _} = Accel.excp_pack([bad], 0b001)

      bad_g = struct(Gaussian, position: {0.0, 0.0, 0.0}, color: :nope, sh: nil)
      assert {:error, _} = Accel.gspl_pack([bad_g], 0)
    end

    test "row helpers cover nil SH and nested SH" do
      p = Point.new(1, 2, 3, color: {1, 2, 3, 4}, normal: nil)
      assert {1.0, 2.0, 3.0, {1, 2, 3, 4}, nil} = Accel.point_to_row(p)
      assert %Point{} = Accel.row_to_point(Accel.point_to_row(p))

      g0 = Gaussian.new({0, 0, 0}, sh: nil)
      row0 = Accel.gaussian_to_row(g0, 0)
      assert %Gaussian{sh: nil} = Accel.row_to_gaussian(row0, 0)

      g1 = Gaussian.new({0, 0, 0}, color: {0.1, 0.2, 0.3}, sh: [[0.1, 0.2, 0.3], [1.0, 2.0, 3.0]])
      row1 = Accel.gaussian_to_row(g1, 3)
      assert %Gaussian{} = Accel.row_to_gaussian(row1, 3)
    end
  end

  describe "Binary accel: false elixir paths" do
    test "encode/decode/stream_encode/stream_decode without Accel" do
      cloud =
        PointCloud.new([
          Point.new(1.0, 2.0, 3.0, color: {1, 2, 3}, normal: {0.0, 1.0, 0.0}),
          Point.new(4.0, 5.0, 6.0, color: {4, 5, 6, 7})
        ])

      assert {:ok, bin} = Binary.encode(cloud, accel: false)
      assert {:ok, decoded} = Binary.decode(bin, accel: false)
      assert length(decoded.points) == 2

      assert [%Point{}, %Point{}] =
               Binary.stream_decode(bin, source: :binary, accel: false) |> Enum.to_list()

      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)

      assert :ok =
               Binary.stream_encode_to_file(cloud.points, path,
                 schema: [:color, :alpha, :normal],
                 accel: false
               )

      assert [%Point{}, %Point{}] =
               Binary.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      # early halt on IO path
      assert [%Point{}] =
               Binary.stream_decode(path, source: :file, accel: false)
               |> Stream.take(1)
               |> Enum.to_list()
    end

    test "stream_decode binary accel path errors and truncated file IO path" do
      bad_ver = <<"EXCP", 99::little-16, 0::little-16, 1::little-64>>

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(bad_ver, source: :binary, accel: true) |> Enum.to_list()

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(<<"nope">>, source: :binary, accel: true) |> Enum.to_list()

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(<<"nope">>, source: :binary, accel: false) |> Enum.to_list()

      cloud = PointCloud.new([Point.new(1, 2, 3), Point.new(4, 5, 6)])
      {:ok, bin} = Binary.encode(cloud, accel: false)
      truncated = binary_part(bin, 0, 20)
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)
      File.write!(path, truncated)

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      # eof after one full record on IO path
      one = <<1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32>>

      File.write!(
        path,
        <<"EXCP", 1::little-16, 0::little-16, 2::little-64, one::binary>>
      )

      items = Binary.stream_decode(path, source: :file, accel: false) |> Enum.to_list()
      assert match?([%Point{}, {:error, %{reason: :invalid_data}}], items)

      File.write!(path, "")

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      File.write!(path, "EXCP")

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      File.write!(
        path,
        <<"EXCP", 99::little-16, 0::little-16, 0::little-64>>
      )

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      # bad magic via mmap header path
      File.write!(path, <<"XXXX", 1::little-16, 0::little-16, 0::little-64>>)

      assert [{:error, %{reason: :invalid_data}}] =
               Binary.stream_decode(path, source: :file, accel: true) |> Enum.to_list()
    end

    test "truncated mmap stream and empty cloud" do
      assert {:ok, empty} = Binary.encode(PointCloud.new([]), accel: true)
      assert {:ok, %{points: []}} = Binary.decode(empty, accel: true)

      assert [] =
               Binary.stream_decode(empty, source: :binary, accel: true) |> Enum.to_list()

      # count=2, only one xyz — mmap accel truncated
      one = <<1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32>>
      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)

      File.write!(
        path,
        <<"EXCP", 1::little-16, 0::little-16, 2::little-64, one::binary>>
      )

      items = Binary.stream_decode(path, source: :file, accel: true) |> Enum.to_list()
      assert Enum.any?(items, &match?({:error, %{reason: :invalid_data}}, &1))

      # binary stream truncated body
      bin = <<"EXCP", 1::little-16, 0::little-16, 2::little-64, one::binary>>
      items2 = Binary.stream_decode(bin, source: :binary, accel: true) |> Enum.to_list()
      assert Enum.any?(items2, &match?({:error, %{reason: :invalid_data}}, &1))
    end

    test "normalize color branches via elixir encode" do
      cloud =
        PointCloud.new([
          Point.new(0, 0, 0),
          Point.new(1, 1, 1, color: {1, 2, 3}),
          Point.new(2, 2, 2, color: {1, 2, 3, 4})
        ])

      assert {:ok, _} = Binary.encode(cloud, accel: false)

      path = tmp(".excp")
      on_exit(fn -> File.rm(path) end)

      # RGB schema with RGBA source exercises normalize_rgb/1 RGBA clause.
      assert :ok =
               Binary.stream_encode_to_file(
                 [Point.new(1, 1, 1, color: {9, 8, 7, 6})],
                 path,
                 schema: [:color],
                 accel: false
               )

      assert :ok =
               Binary.stream_encode_to_file(
                 [Point.new(0, 0, 0), Point.new(1, 1, 1, color: {9, 8, 7})],
                 path,
                 schema: [:color, :alpha],
                 accel: false
               )

      assert {:ok, _} = Binary.decode(File.read!(path), accel: false)

      # Missing file on elixir IO open path
      assert [{:error, %{reason: :io_error}}] =
               Binary.stream_decode("/no/such/ex_codecs_io.excp", source: :file, accel: false)
               |> Enum.to_list()
    end
  end

  describe "Gsplat accel: false elixir paths" do
    test "encode/decode/stream without Accel and error edges" do
      cloud =
        GaussianCloud.new([
          Gaussian.new({1.0, 2.0, 3.0}, opacity: 0.5),
          Gaussian.new({0.0, 1.0, 0.0},
            color: {0.2, 0.3, 0.4},
            sh: [[0.2, 0.3, 0.4], [0.1, 0.1, 0.1]]
          )
        ])

      # Empty SH list hits sh_rest_values/1 catch-all list clause (non-empty lists
      # match the [_dc | rest] head clause first).
      assert {:ok, _} =
               Gsplat.encode(
                 GaussianCloud.new([struct(Gaussian, position: {0.0, 0.0, 0.0}, sh: [])]),
                 accel: false
               )

      assert {:ok, bin} = Gsplat.encode(cloud, accel: false)
      assert {:ok, decoded} = Gsplat.decode(bin, accel: false)
      assert length(decoded.gaussians) == 2

      assert [%Gaussian{}, %Gaussian{}] =
               Gsplat.stream_decode(bin, source: :binary, accel: false) |> Enum.to_list()

      path = tmp(".gspl")
      on_exit(fn -> File.rm(path) end)

      assert :ok =
               Gsplat.stream_encode_to_file(cloud.gaussians, path,
                 schema: [sh_rest: 3],
                 accel: false
               )

      assert [%Gaussian{}, %Gaussian{}] =
               Gsplat.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      assert [%Gaussian{}] =
               Gsplat.stream_decode(path, source: :file, accel: false)
               |> Stream.take(1)
               |> Enum.to_list()

      assert [{:error, _}] =
               Gsplat.stream_decode(
                 <<"GSPL", 9::little-16, 0::little-16, 1::little-64, 0::little-16>>,
                 source: :binary,
                 accel: true
               )
               |> Enum.to_list()

      assert [{:error, _}] =
               Gsplat.stream_decode(<<"nope">>, source: :binary, accel: true) |> Enum.to_list()

      assert [{:error, _}] =
               Gsplat.stream_decode(<<"nope">>, source: :binary, accel: false) |> Enum.to_list()

      File.write!(path, "")

      assert [{:error, _}] =
               Gsplat.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      File.write!(path, "GSPL")

      assert [{:error, _}] =
               Gsplat.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      File.write!(
        path,
        <<"GSPL", 9::little-16, 0::little-16, 0::little-64, 0::little-16>>
      )

      assert [{:error, _}] =
               Gsplat.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      zeros = :binary.copy(<<0>>, 56)

      File.write!(
        path,
        <<"GSPL", 1::little-16, 0::little-16, 2::little-64, 0::little-16, zeros::binary>>
      )

      items = Gsplat.stream_decode(path, source: :file, accel: false) |> Enum.to_list()
      assert match?([%Gaussian{}, {:error, _}], items)

      items2 = Gsplat.stream_decode(path, source: :file, accel: true) |> Enum.to_list()
      assert Enum.any?(items2, &match?({:error, _}, &1))

      assert {:ok, empty} = Gsplat.encode(GaussianCloud.new([]), accel: true)
      assert [] = Gsplat.stream_decode(empty, source: :binary, accel: true) |> Enum.to_list()

      assert [{:error, %{reason: :io_error}}] =
               Gsplat.stream_decode("/no/such/ex_codecs_io.gspl", source: :file, accel: false)
               |> Enum.to_list()

      # XXXX magic via mmap header
      File.write!(path, <<"XXXX", 1::little-16, 0::little-16, 0::little-64, 0::little-16>>)

      assert [{:error, _}] =
               Gsplat.stream_decode(path, source: :file, accel: true) |> Enum.to_list()

      # Truncated binary stream (accel) — empty chunk path
      short = <<"GSPL", 1::little-16, 0::little-16, 1::little-64, 0::little-16, 0, 1, 2>>

      assert [{:error, %{reason: :invalid_data}}] =
               Gsplat.stream_decode(short, source: :binary, accel: true) |> Enum.to_list()

      # Short non-EOF body on IO path (count=1, fewer than stride bytes)
      File.write!(
        path,
        <<"GSPL", 1::little-16, 0::little-16, 1::little-64, 0::little-16, 0, 1, 2, 3, 4>>
      )

      assert [{:error, %{reason: :invalid_data}}] =
               Gsplat.stream_decode(path, source: :file, accel: false) |> Enum.to_list()
    end
  end

  describe "PLY accel: false binary paths" do
    test "binary decode and file stream without Accel cover unpack types" do
      # Craft a binary PLY with mixed property types so elixir unpack clauses run.
      header = """
      ply
      format binary_little_endian 1.0
      element vertex 1
      property char c
      property uchar uc
      property short s
      property ushort us
      property int i
      property uint ui
      property float x
      property float y
      property float z
      property double d
      end_header
      """

      body =
        <<
          -1::signed-integer-8,
          255::unsigned-integer-8,
          -2::little-signed-integer-16,
          3::little-unsigned-integer-16,
          -4::little-signed-integer-32,
          5::little-unsigned-integer-32,
          1.25::little-float-32,
          2.5::little-float-32,
          3.75::little-float-32,
          9.0::little-float-64
        >>

      path = tmp(".ply")
      on_exit(fn -> File.rm(path) end)
      File.write!(path, header <> body)

      assert {:ok, cloud} = PLY.decode(File.read!(path), accel: false)
      assert length(cloud.points) == 1

      assert [%Point{}] =
               PLY.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      # big-endian mixed types
      header_be = String.replace(header, "little_endian", "big_endian")

      body_be =
        <<
          -1::signed-integer-8,
          255::unsigned-integer-8,
          -2::big-signed-integer-16,
          3::big-unsigned-integer-16,
          -4::big-signed-integer-32,
          5::big-unsigned-integer-32,
          1.25::big-float-32,
          2.5::big-float-32,
          3.75::big-float-32,
          9.0::big-float-64
        >>

      File.write!(path, header_be <> body_be)
      assert {:ok, _} = PLY.decode(File.read!(path), accel: false)

      assert [%Point{}] =
               PLY.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      # normal binary_le encode/stream with accel false
      cloud2 = PointCloud.new([Point.new(1, 2, 3), Point.new(4, 5, 6)])
      {:ok, bin} = PLY.encode(cloud2, ply_format: :binary_le)
      File.write!(path, bin)

      assert [%Point{}, %Point{}] =
               PLY.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      assert [%Point{}] =
               PLY.stream_decode(path, source: :file, accel: false)
               |> Stream.take(1)
               |> Enum.to_list()

      # truncated binary body on IO path
      File.write!(path, binary_part(bin, 0, byte_size(bin) - 4))

      items = PLY.stream_decode(path, source: :file, accel: false) |> Enum.to_list()
      assert Enum.any?(items, &match?({:error, %{reason: :invalid_data}}, &1))

      # truncated via mmap accel path
      File.write!(path, binary_part(bin, 0, byte_size(bin) - 4))
      items2 = PLY.stream_decode(path, source: :file, accel: true) |> Enum.to_list()
      assert Enum.any?(items2, &match?({:error, %{reason: :invalid_data}}, &1))

      # CR-only newline after end_header (stream IO path uses strip count helper)
      File.write!(
        path,
        "ply\rformat binary_little_endian 1.0\relement vertex 1\rproperty float x\rproperty float y\rproperty float z\rend_header\r" <>
          <<1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32>>
      )

      assert [%Point{}] =
               PLY.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      # No newline after end_header — strip_leading_newlines_count/1 catch-all
      body = <<1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32>>

      File.write!(
        path,
        "ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header" <>
          body
      )

      assert [%Point{}] =
               PLY.stream_decode(path, source: :file, accel: false) |> Enum.to_list()

      # First 4096-byte header scan keeps only 1 body byte in leftover so
      # take_exact_bytes/3 must read the remainder of the vertex from the file.
      prefix =
        "ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\n"

      end_h = "end_header\n"
      # hdr + 1 body byte == 4096 ⇒ hdr size 4095
      fill_size = 4095 - byte_size(prefix) - byte_size(end_h)
      fill = "comment " <> String.duplicate("z", fill_size - 9) <> "\n"
      hdr = prefix <> fill <> end_h
      assert byte_size(hdr) == 4095

      File.write!(path, hdr <> body)

      assert [%Point{}] =
               PLY.stream_decode(path, source: :file, accel: false) |> Enum.to_list()
    end
  end
end
