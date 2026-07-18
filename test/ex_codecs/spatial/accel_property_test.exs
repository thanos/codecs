defmodule ExCodecs.Spatial.AccelPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExCodecs.Spatial.Accel
  alias ExCodecs.Spatial.Codec.{Binary, Gsplat, PLY}
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}

  @moduletag :accel

  setup do
    if Accel.available?() do
      :ok
    else
      {:skip, "spatial Accel NIF not loaded"}
    end
  end

  defp float32 do
    # Keep values in a range that survives f32 round-trip without NaN/Inf.
    StreamData.float(min: -1.0e5, max: 1.0e5)
    |> StreamData.map(fn f ->
      <<x::little-float-32>> = <<f::little-float-32>>
      x
    end)
  end

  defp u8, do: StreamData.integer(0..255)

  defp point_generator do
    gen all(
          x <- float32(),
          y <- float32(),
          z <- float32(),
          mode <- StreamData.member_of([:xyz, :rgb, :rgba, :normal, :rgb_normal]),
          r <- u8(),
          g <- u8(),
          b <- u8(),
          a <- u8(),
          nx <- float32(),
          ny <- float32(),
          nz <- float32()
        ) do
      opts =
        case mode do
          :xyz -> []
          :rgb -> [color: {r, g, b}]
          :rgba -> [color: {r, g, b, a}]
          :normal -> [normal: {nx, ny, nz}]
          :rgb_normal -> [color: {r, g, b}, normal: {nx, ny, nz}]
        end

      Point.new(x, y, z, opts)
    end
  end

  defp gaussian_generator do
    gen all(
          x <- float32(),
          y <- float32(),
          z <- float32(),
          r <- float32(),
          g <- float32(),
          b <- float32(),
          opacity <- float32(),
          sx <- float32(),
          sy <- float32(),
          sz <- float32(),
          rw <- float32(),
          rx <- float32(),
          ry <- float32(),
          rz <- float32(),
          sh_n <- StreamData.integer(0..6),
          sh_vals <- StreamData.list_of(float32(), length: sh_n)
        ) do
      sh =
        if sh_n == 0 do
          nil
        else
          [[r, g, b] | Enum.chunk_every(sh_vals, 3)]
        end

      Gaussian.new({x, y, z},
        color: {r, g, b},
        opacity: opacity,
        scale: {sx, sy, sz},
        rotation: {rw, rx, ry, rz},
        sh: sh
      )
    end
  end

  defp assert_points_close(a, b) do
    assert length(a) == length(b)

    Enum.zip(a, b)
    |> Enum.each(fn {p1, p2} ->
      assert_in_delta p1.x, p2.x, 1.0e-5
      assert_in_delta p1.y, p2.y, 1.0e-5
      assert_in_delta p1.z, p2.z, 1.0e-5
      assert p1.color == p2.color
      assert_normals_close(p1.normal, p2.normal)
    end)
  end

  defp assert_normals_close(nil, nil), do: :ok

  defp assert_normals_close({a, b, c}, {d, e, f}) do
    assert_in_delta a, d, 1.0e-5
    assert_in_delta b, e, 1.0e-5
    assert_in_delta c, f, 1.0e-5
  end

  defp assert_gaussians_close(a, b) do
    assert length(a) == length(b)

    Enum.zip(a, b)
    |> Enum.each(fn {g1, g2} ->
      assert_tuple_close(g1.position, g2.position)
      assert_tuple_close(g1.color, g2.color)
      assert_in_delta g1.opacity, g2.opacity, 1.0e-5
      assert_tuple_close(g1.scale, g2.scale)
      assert_tuple_close(g1.rotation, g2.rotation)
      assert_sh_close(g1.sh, g2.sh)
    end)
  end

  defp assert_tuple_close(t1, t2) do
    assert tuple_size(t1) == tuple_size(t2)

    Enum.zip(Tuple.to_list(t1), Tuple.to_list(t2))
    |> Enum.each(fn {a, b} -> assert_in_delta a, b, 1.0e-5 end)
  end

  defp assert_sh_close(nil, nil), do: :ok

  defp assert_sh_close(a, b) when is_list(a) and is_list(b) do
    assert_tuple_close(
      List.to_tuple(List.flatten(a)),
      List.to_tuple(List.flatten(b))
    )
  end

  property "EXCP rust decode matches elixir decode" do
    check all(points <- StreamData.list_of(point_generator(), min_length: 0, max_length: 40)) do
      cloud = PointCloud.new(points)
      assert {:ok, bin} = Binary.encode(cloud, accel: false)
      assert {:ok, elixir} = Binary.decode(bin, accel: false)
      assert {:ok, rust} = Binary.decode(bin, accel: true)
      assert_points_close(elixir.points, rust.points)
    end
  end

  property "EXCP rust pack matches elixir encode body" do
    check all(points <- StreamData.list_of(point_generator(), min_length: 1, max_length: 40)) do
      assert {:ok, elixir_bin} = Binary.encode(PointCloud.new(points), accel: false)
      assert {:ok, rust_bin} = Binary.encode(PointCloud.new(points), accel: true)
      assert elixir_bin == rust_bin
    end
  end

  property "GSPL rust decode matches elixir decode" do
    check all(gs <- StreamData.list_of(gaussian_generator(), min_length: 0, max_length: 20)) do
      cloud = GaussianCloud.new(gs)
      assert {:ok, bin} = Gsplat.encode(cloud, accel: false)
      assert {:ok, elixir} = Gsplat.decode(bin, accel: false)
      assert {:ok, rust} = Gsplat.decode(bin, accel: true)
      assert_gaussians_close(elixir.gaussians, rust.gaussians)
    end
  end

  property "GSPL rust pack matches elixir encode body" do
    check all(gs <- StreamData.list_of(gaussian_generator(), min_length: 1, max_length: 20)) do
      assert {:ok, elixir_bin} = Gsplat.encode(GaussianCloud.new(gs), accel: false)
      assert {:ok, rust_bin} = Gsplat.encode(GaussianCloud.new(gs), accel: true)
      assert elixir_bin == rust_bin
    end
  end

  property "binary PLY rust decode matches elixir decode" do
    check all(points <- StreamData.list_of(point_generator(), min_length: 1, max_length: 30)) do
      cloud = PointCloud.new(points)
      assert {:ok, bin} = PLY.encode(cloud, ply_format: :binary_le)
      assert {:ok, elixir} = PLY.decode(bin, accel: false)
      assert {:ok, rust} = PLY.decode(bin, accel: true)
      assert_points_close(elixir.points, rust.points)
    end
  end

  property "EXCP mmap stream_decode matches elixir decode" do
    check all(points <- StreamData.list_of(point_generator(), min_length: 1, max_length: 25)) do
      assert {:ok, bin} = Binary.encode(PointCloud.new(points), accel: false)

      path =
        Path.join(
          System.tmp_dir!(),
          "ex_codecs_accel_prop_#{System.unique_integer([:positive])}.excp"
        )

      try do
        File.write!(path, bin)
        assert {:ok, elixir} = Binary.decode(bin, accel: false)

        streamed =
          Binary.stream_decode(path, source: :file, accel: true) |> Enum.to_list()

        assert_points_close(elixir.points, streamed)
      after
        File.rm(path)
      end
    end
  end
end
