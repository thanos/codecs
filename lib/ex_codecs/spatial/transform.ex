defmodule ExCodecs.Spatial.Transform do
  @moduledoc """
  Rigid/similarity transform metadata, not applied to points by this library.

  **Reserved for future use.** No shipped codec reads or writes `Transform`
  fields today. The module is provided so that formats which embed pose
  metadata (e.g. EXCP v2) can use a shared type when that support lands.
  Application of transforms is left to higher-level code.

  ## Fields

    * `:translation` — `{float(), float(), float()}` Cartesian offset; defaults
      to `{0.0, 0.0, 0.0}`. Units match the associated spatial coordinates.
    * `:rotation` — `{float(), float(), float(), float()}` scalar-first
      `{w, x, y, z}` quaternion; defaults to identity
      `{1.0, 0.0, 0.0, 0.0}`. Unit length is not enforced.
    * `:scale` — `float()` uniform dimensionless scale; defaults to `1.0`.

  This module stores transform metadata but does not define composition order
  or apply transforms; consumers must follow the enclosing format's convention.

  ## Example

      iex> ExCodecs.Spatial.Transform.new(
      ...>   translation: {10, 0, -2},
      ...>   rotation: {1, 0, 0, 0},
      ...>   scale: 0.5
      ...> )
      %ExCodecs.Spatial.Transform{
        translation: {10.0, 0.0, -2.0},
        rotation: {1.0, 0.0, 0.0, 0.0},
        scale: 0.5
      }
  """

  @typedoc """
  Transform metadata with translation, scalar-first quaternion rotation, and
  uniform scale. See the module documentation for all fields, defaults, units
  and conventions, and a construction example.
  """
  @type t :: %__MODULE__{
          translation: {float(), float(), float()},
          rotation: {float(), float(), float(), float()},
          scale: float()
        }

  defstruct translation: {0.0, 0.0, 0.0},
            rotation: {1.0, 0.0, 0.0, 0.0},
            scale: 1.0

  @doc """
  Identity transform.

  ## Arguments

  None.

  ## Returns

  `%Transform{}` with zero translation, identity quaternion, scale `1.0`.

  ## Raises

  None.

  ## Examples

      iex> t = ExCodecs.Spatial.Transform.identity()
      iex> t.scale
      1.0
  """
  @spec identity() :: t()
  def identity, do: %__MODULE__{}

  @doc """
  Builds a transform.

  ## Arguments

    * `opts` — a keyword list with:
      * `:translation` — numeric `{x, y, z}`; defaults to the origin and is
        stored as floats.
      * `:rotation` — numeric `{w, x, y, z}` scalar-first quaternion; defaults
        to identity and is stored as floats.
      * `:scale` — `number()`; defaults to `1.0` and is stored as a float.

  ## Returns

  `%Transform{}`

  ## Raises

  * `FunctionClauseError` for malformed or non-numeric translation/rotation
    tuples, or if `opts` is not a keyword list.
  * `ArithmeticError` if `:scale` is not numeric.

  ## Examples

      iex> t = ExCodecs.Spatial.Transform.new(translation: {1, 0, 0}, scale: 2)
      iex> t.translation
      {1.0, 0.0, 0.0}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      translation: normalize_vec3(Keyword.get(opts, :translation, {0.0, 0.0, 0.0})),
      rotation: normalize_quat(Keyword.get(opts, :rotation, {1.0, 0.0, 0.0, 0.0})),
      scale: Keyword.get(opts, :scale, 1.0) * 1.0
    }
  end

  defp normalize_vec3({x, y, z}) when is_number(x) and is_number(y) and is_number(z) do
    {x * 1.0, y * 1.0, z * 1.0}
  end

  defp normalize_quat({w, x, y, z})
       when is_number(w) and is_number(x) and is_number(y) and is_number(z) do
    {w * 1.0, x * 1.0, y * 1.0, z * 1.0}
  end
end
