defmodule VideoMixer.FrameQueue.OrderTest do
  use ExUnit.Case, async: true

  alias VideoMixer.Frame
  alias VideoMixer.FrameQueue, as: Queue
  alias VideoMixer.FrameSpec, as: Spec

  test "handles frame-spec pairs delivered out-of-order" do
    queue = Queue.new()

    input = [
      %Frame{size: 100},
      %Spec{accepted_frame_size: 100},
      %Frame{size: 100},
      %Spec{accepted_frame_size: 200},
      # After spec change.
      %Frame{size: 100},
      %Frame{size: 200},
      %Spec{accepted_frame_size: 300},
      %Frame{size: 300},
      # Should not happen but still we prefer to handle it.
      %Frame{size: 200},
      %Frame{size: 300},
      # Buffer received before associated specs.
      %Frame{size: 400},
      %Spec{accepted_frame_size: 400}
    ]

    want = [
      %{frame: %Frame{size: 100}, spec: %Spec{accepted_frame_size: 100}, spec_changed?: true},
      %{frame: %Frame{size: 100}, spec: %Spec{accepted_frame_size: 100}, spec_changed?: false},
      %{frame: %Frame{size: 100}, spec: %Spec{accepted_frame_size: 100}, spec_changed?: false},
      %{frame: %Frame{size: 200}, spec: %Spec{accepted_frame_size: 200}, spec_changed?: true},
      %{frame: %Frame{size: 300}, spec: %Spec{accepted_frame_size: 300}, spec_changed?: true},
      %{frame: %Frame{size: 200}, spec: %Spec{accepted_frame_size: 200}, spec_changed?: true},
      %{frame: %Frame{size: 300}, spec: %Spec{accepted_frame_size: 300}, spec_changed?: true},
      %{frame: %Frame{size: 400}, spec: %Spec{accepted_frame_size: 400}, spec_changed?: true}
    ]

    queue =
      Enum.reduce(input, queue, fn frame_or_spec, queue -> Queue.push(queue, frame_or_spec) end)

    Enum.reduce(want, queue, fn want, queue ->
      {have, queue} = Queue.pop!(queue)

      assert have.frame == want.frame
      assert have.spec == want.spec
      assert have.spec_changed? == want.spec_changed?

      queue
    end)
  end
end
