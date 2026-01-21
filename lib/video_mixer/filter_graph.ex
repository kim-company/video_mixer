defmodule VideoMixer.FilterGraph do
  alias VideoMixer.Error
  alias VideoMixer.FrameSpec

  @type layout ::
          :single_fit
          | :hstack
          | :vstack
          | :xstack
          | :primary_sidebar

  @type role ::
          :primary
          | :sidebar
          | :left
          | :right
          | :top
          | :bottom
          | :top_left
          | :top_right
          | :bottom_left
          | :bottom_right

  @spec build(layout(), keyword(FrameSpec.t()) | map(), FrameSpec.t() | map(), keyword()) ::
          {:ok,
           %{
             graph: String.t(),
             filter_indexes: [non_neg_integer()],
             input_order: [role()],
             mapping: [FrameSpec.t()]
           }}
          | {:error, Error.t()}
  def build(layout, specs_by_role, output_spec, opts \\ []) do
    with {:ok, specs_by_role} <- normalize_specs(specs_by_role),
         {:ok, output_dims} <- output_dims(output_spec),
         {:ok, pixel_format} <- pixel_format(output_spec, opts),
         {:ok, role_order} <- role_order(layout),
         :ok <- validate_roles(specs_by_role, role_order),
         :ok <- validate_specs(specs_by_role, pixel_format) do
      mapping = Enum.map(role_order, &Map.fetch!(specs_by_role, &1))

      do_build(layout, output_dims, role_order, mapping)
    end
  end

  defp do_build(:single_fit, output_dims, role_order, mapping) do
    fit_modes = extract_fit_modes(mapping, role_order)
    graph = single_fit_graph(output_dims, fit_modes)

    {:ok,
     %{
       graph: graph,
       filter_indexes: [0],
       input_order: role_order,
       mapping: mapping
     }}
  end

  defp do_build(:hstack, output_dims, role_order, mapping) do
    fit_modes = extract_fit_modes(mapping, role_order)
    graph = hstack_graph(output_dims, fit_modes)

    {:ok,
     %{
       graph: graph,
       filter_indexes: [0, 1],
       input_order: role_order,
       mapping: mapping
     }}
  end

  defp do_build(:vstack, output_dims, role_order, mapping) do
    fit_modes = extract_fit_modes(mapping, role_order)
    graph = vstack_graph(output_dims, fit_modes)

    {:ok,
     %{
       graph: graph,
       filter_indexes: [0, 1],
       input_order: role_order,
       mapping: mapping
     }}
  end

  defp do_build(:xstack, output_dims, role_order, mapping) do
    fit_modes = extract_fit_modes(mapping, role_order)
    graph = xstack_graph(output_dims, fit_modes)

    {:ok,
     %{
       graph: graph,
       filter_indexes: [0, 1, 2, 3],
       input_order: role_order,
       mapping: mapping
     }}
  end

  defp do_build(:primary_sidebar, output_dims, role_order, mapping) do
    with {:ok, dims} <- primary_sidebar_dimensions(output_dims) do
      fit_modes = extract_fit_modes(mapping, role_order)
      graph = primary_sidebar_graph(dims, fit_modes)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1],
         input_order: role_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(other, _output_dims, _role_order, _mapping) do
    {:error, Error.new(:filter_graph, :unsupported_layout, %{layout: other})}
  end

  defp normalize_specs(specs_by_role) when is_map(specs_by_role) do
    {:ok, specs_by_role}
  end

  defp normalize_specs(specs_by_role) when is_list(specs_by_role) do
    if Keyword.keyword?(specs_by_role) do
      keys = Keyword.keys(specs_by_role)

      if length(keys) != length(Enum.uniq(keys)) do
        {:error, Error.new(:filter_graph, :duplicate_roles, %{roles: keys})}
      else
        {:ok, Map.new(specs_by_role)}
      end
    else
      {:error, Error.new(:filter_graph, :invalid_specs)}
    end
  end

  defp normalize_specs(_specs_by_role) do
    {:error, Error.new(:filter_graph, :invalid_specs)}
  end

  defp output_dims(%FrameSpec{width: width, height: height}) do
    output_dims(%{width: width, height: height})
  end

  defp output_dims(%{width: width, height: height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    {:ok, %{width: width, height: height}}
  end

  defp output_dims(_output_spec) do
    {:error, Error.new(:filter_graph, :invalid_output_dimensions)}
  end

  defp pixel_format(%FrameSpec{pixel_format: pixel_format}, opts),
    do: pixel_format(%{pixel_format: pixel_format}, opts)

  defp pixel_format(%{pixel_format: pixel_format}, opts) when is_atom(pixel_format) do
    requested = Keyword.get(opts, :pixel_format, :I420)

    if requested == pixel_format do
      {:ok, requested}
    else
      {:error,
       Error.new(:filter_graph, :pixel_format_mismatch, %{
         expected: requested,
         got: pixel_format
       })}
    end
  end

  defp pixel_format(_output_spec, opts) do
    {:ok, Keyword.get(opts, :pixel_format, :I420)}
  end

  defp validate_specs(specs_by_role, pixel_format) do
    invalid =
      Enum.find(specs_by_role, fn {_role, spec} -> not valid_spec?(spec, pixel_format) end)

    if invalid do
      {role, spec} = invalid

      {:error,
       Error.new(:filter_graph, :invalid_input_spec, %{role: role, spec: spec})}
    else
      :ok
    end
  end

  defp valid_spec?(%FrameSpec{} = spec, pixel_format) do
    is_integer(spec.width) and spec.width > 0 and is_integer(spec.height) and spec.height > 0 and
      is_atom(spec.pixel_format) and spec.pixel_format == pixel_format and
      is_integer(spec.accepted_frame_size) and spec.accepted_frame_size > 0
  end

  defp valid_spec?(_spec, _pixel_format), do: false

  defp role_order(:single_fit), do: {:ok, [:primary]}
  defp role_order(:hstack), do: {:ok, [:left, :right]}
  defp role_order(:vstack), do: {:ok, [:top, :bottom]}
  defp role_order(:xstack), do: {:ok, [:top_left, :top_right, :bottom_left, :bottom_right]}
  defp role_order(:primary_sidebar), do: {:ok, [:primary, :sidebar]}
  defp role_order(layout), do: {:error, Error.new(:filter_graph, :unsupported_layout, %{layout: layout})}

  defp validate_roles(specs_by_role, role_order) do
    roles = Map.keys(specs_by_role)
    missing = role_order -- roles
    extra = roles -- role_order

    cond do
      missing != [] ->
        {:error, Error.new(:filter_graph, :missing_roles, %{missing: missing})}

      extra != [] ->
        {:error, Error.new(:filter_graph, :unexpected_roles, %{unexpected: extra})}

      true ->
        :ok
    end
  end

  defp extract_fit_modes(mapping, role_order) do
    role_order
    |> Enum.zip(mapping)
    |> Map.new(fn {role, spec} -> {role, Map.get(spec, :fit_mode, :crop)} end)
  end

  defp scale_filter_chain(width, height, fit_mode) do
    case fit_mode do
      :crop ->
        "scale=#{width}:#{height}:force_original_aspect_ratio=increase,setsar=1,crop=#{width}:#{height}"

      :fit ->
        "scale=#{width}:#{height}:force_original_aspect_ratio=decrease,pad=#{width}:#{height}:-1:-1,setsar=1"
    end
  end

  defp single_fit_graph(%{width: ow, height: oh}, fit_modes) do
    fit_mode = fit_modes[:primary] || :crop
    "[0:v]#{scale_filter_chain(ow, oh, fit_mode)}[out]"
  end

  defp hstack_graph(%{width: ow, height: oh}, fit_modes) do
    [
      "[0:v]#{scale_filter_chain("#{ow}/2", oh, fit_modes[:left] || :crop)}[l]",
      "[1:v]#{scale_filter_chain("#{ow}/2", oh, fit_modes[:right] || :crop)}[r]",
      "[l][r]hstack=inputs=2,scale=#{ow}:#{oh}[out]"
    ]
    |> Enum.join(";")
  end

  defp vstack_graph(%{width: ow, height: oh}, fit_modes) do
    [
      "[0:v]#{scale_filter_chain(ow, "#{oh}/2", fit_modes[:top] || :crop)}[t]",
      "[1:v]#{scale_filter_chain(ow, "#{oh}/2", fit_modes[:bottom] || :crop)}[b]",
      "[t][b]vstack=inputs=2,scale=#{ow}:#{oh}[out]"
    ]
    |> Enum.join(";")
  end

  defp xstack_graph(%{width: ow, height: oh}, fit_modes) do
    [
      "[0:v]#{scale_filter_chain("#{ow}/2", "#{oh}/2", fit_modes[:top_left] || :crop)}[a]",
      "[1:v]#{scale_filter_chain("#{ow}/2", "#{oh}/2", fit_modes[:top_right] || :crop)}[b]",
      "[2:v]#{scale_filter_chain("#{ow}/2", "#{oh}/2", fit_modes[:bottom_left] || :crop)}[c]",
      "[3:v]#{scale_filter_chain("#{ow}/2", "#{oh}/2", fit_modes[:bottom_right] || :crop)}[d]",
      "[a][b][c][d]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,scale=#{ow}:#{oh}[out]"
    ]
    |> Enum.join(";")
  end

  defp primary_sidebar_graph(%{width: ow, height: oh}, fit_modes) do
    [
      "[0:v]#{scale_filter_chain("#{ow}/3*2", oh, fit_modes[:primary] || :crop)}[l]",
      "[1:v]#{scale_filter_chain("#{ow}/3", oh, fit_modes[:sidebar] || :crop)}[r]",
      "[l][r]hstack=inputs=2,scale=#{ow}:#{oh}[out]"
    ]
    |> Enum.join(";")
  end

  defp primary_sidebar_dimensions(%{width: ow, height: oh}) do
    {:ok, %{width: ow, height: oh}}
  end
end
