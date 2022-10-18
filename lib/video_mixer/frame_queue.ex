defmodule VideoMixer.FrameQueue do
  defmodule QexWithCount do
    defstruct queue: Qex.new(), count: 0

    def new(), do: %__MODULE__{}

    def push(state = %__MODULE__{queue: queue, count: count}, item) do
      %__MODULE__{state | queue: Qex.push(queue, item), count: count + 1}
    end

    def pop!(state = %__MODULE__{queue: queue, count: count}) do
      {item, queue} = Qex.pop!(queue)
      {item, %__MODULE__{state | queue: queue, count: count - 1}}
    end

    def empty?(%__MODULE__{count: 0}), do: true
    def empty?(_state), do: false
  end

  defmodule ShadowingError do
    defexception [:message]
  end

  alias VideoMixer.Frame
  alias VideoMixer.FrameSpec

  defstruct [:index, :current_spec, :known_specs, :stream_finished?, :spec_changed?, :ready, :pending, :needs_spec_before_next_frame]

  def new(index) do
    %__MODULE__{
      index: index,
      spec_changed?: false,
      stream_finished?: false,
      # Erroneous condition in which a frame risks to be left behind in the
      # pending queue.
      needs_spec_before_next_frame: false,
      
      known_specs: [],
      current_spec: nil,
      ready: QexWithCount.new(),
      # Frames that do not find a matching Spec are stored in this buffer.
      pending: QexWithCount.new()
    }
  end

  def push(state, spec = %FrameSpec{}) do
    state = %{state | known_specs: [spec | state.known_specs]}

    if QexWithCount.empty?(state.pending) do
      state
    else
      frames = Enum.into(state.pending.queue, [])

      pending_accepted? =
        frames
        |> Enum.map(fn x -> FrameSpec.compatible?(spec, x) end)
        |> Enum.all?()

      if pending_accepted? do
        state = %{state | spec_changed?: true, current_spec: spec, pending: QexWithCount.new(), needs_spec_before_next_frame: false}
        Enum.reduce(frames, state, fn x, state -> push_compatible(state, spec, x) end)
      else
        %{state | needs_spec_before_next_frame: true}
      end
    end
  end

  def push(state = %__MODULE__{needs_spec_before_next_frame: true}, frame = %Frame{}) do
    raise ShadowingError, "frame #{inspect frame} pushed while ##{state.pending.count} pending frames are still waiting for a compatible spec"
  end

  def push(state = %__MODULE__{current_spec: spec}, frame = %Frame{}) do
    if FrameSpec.compatible?(spec, frame) do
      # Common Case
      push_compatible(state, spec, frame)
    else
      spec = Enum.find(state.known_specs, &FrameSpec.compatible?(&1, frame))
      if spec != nil do
        state = %{state | spec_changed?: true, current_spec: spec}
        push_compatible(state, spec, frame)
      else
        %{state | pending: QexWithCount.push(state.pending, frame)}
      end
    end
  end

  def push(state = %__MODULE__{}, :end_of_stream) do
    %{state | stream_finished?: true}
  end

  def ready?(%__MODULE__{ready: %QexWithCount{count: count}}), do: count > 0

  def closed?(%__MODULE__{stream_finished?: stream_finished?, ready: ready}) do
    QexWithCount.empty?(ready) and stream_finished?
  end

  def pop!(state = %__MODULE__{ready: ready}) do
    {value, ready} = QexWithCount.pop!(ready)
    {value, %{state | ready: ready}}
  end

  defp push_compatible(state, spec, frame) do
      ready =
        QexWithCount.push(state.ready, %{
          index: state.index,
          frame: frame,
          spec: spec,
          spec_changed?: state.spec_changed?
        })

      %{state | ready: ready, spec_changed?: false}
  end

end
