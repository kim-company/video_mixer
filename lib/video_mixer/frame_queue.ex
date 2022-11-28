defmodule VideoMixer.FrameQueue do
  defmodule ShadowingError do
    defexception [:message]
  end

  alias VideoMixer.Frame
  alias VideoMixer.FrameSpec

  defstruct [
    :index,
    :current_spec,
    :known_specs,
    :stream_finished?,
    :spec_changed?,
    :received_first_frame?,
    :ready,
    :pending,
    :needs_spec_before_next_frame
  ]

  def new(index, ready? \\ false) do
    %__MODULE__{
      index: index,
      spec_changed?: false,
      stream_finished?: false,
      received_first_frame?: ready?,
      # Erroneous condition in which a frame risks to be left behind in the
      # pending queue.
      needs_spec_before_next_frame: false,
      known_specs: [],
      current_spec: nil,
      ready: new_ready_queue(index),
      # Frames that do not find a matching Spec are stored in this buffer.
      pending: new_pending_queue(index)
    }
  end

  def new_pending_queue(index) do
    Q.new("pending-" <> to_string(index))
  end

  def new_ready_queue(index) do
    Q.new("ready-" <> to_string(index))
  end

  def push(state, spec = %FrameSpec{}) do
    state = %{state | known_specs: [spec | state.known_specs]}

    if Q.empty?(state.pending) do
      state
    else
      frames = Enum.into(state.pending.queue, [])

      pending_accepted? =
        frames
        |> Enum.map(fn x -> FrameSpec.compatible?(spec, x) end)
        |> Enum.all?()

      if pending_accepted? do
        state = %{
          state
          | spec_changed?: true,
            current_spec: spec,
            pending: new_pending_queue(state.index),
            needs_spec_before_next_frame: false
        }

        Enum.reduce(frames, state, fn x, state -> push_compatible(state, spec, x) end)
      else
        %{state | needs_spec_before_next_frame: true}
      end
    end
  end

  def push(state = %__MODULE__{needs_spec_before_next_frame: true}, frame = %Frame{}) do
    raise ShadowingError,
          "frame #{inspect(frame)} pushed while ##{state.pending.count} pending frames are still waiting for a compatible spec"
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
        %{state | pending: Q.push(state.pending, frame)}
      end
    end
  end

  def push(state = %__MODULE__{}, :end_of_stream) do
    %{state | stream_finished?: true}
  end

  def ready?(%__MODULE__{received_first_frame?: value}), do: value

  def any?(%__MODULE__{ready: %Q{count: count}}), do: count > 0

  @doc "Returns the size of the ready queue"
  def size(%__MODULE__{ready: %Q{count: count}}), do: count

  def closed?(%__MODULE__{stream_finished?: stream_finished?, ready: ready}) do
    Q.empty?(ready) and stream_finished?
  end

  def pop!(state = %__MODULE__{ready: ready}) do
    {value, ready} = Q.pop!(ready)
    {value, %{state | ready: ready}}
  end

  defp push_compatible(state, spec, frame) do
    ready =
      Q.push(state.ready, %{
        index: state.index,
        frame: frame,
        spec: spec,
        spec_changed?: state.spec_changed?
      })

    %{state | ready: ready, spec_changed?: false, received_first_frame?: true}
  end
end
