defmodule VideoMixer.FrameQueue.StateTest do
  use ExUnit.Case, async: true

  alias VideoMixer.Frame
  alias VideoMixer.FrameQueue, as: Queue
  alias VideoMixer.FrameSpec

  test "reports readiness and size as frames arrive" do
    queue = Queue.new()

    refute Queue.ready?(queue)
    refute Queue.any?(queue)
    assert Queue.size(queue) == 0
    refute Queue.closed?(queue)

    spec = %FrameSpec{accepted_frame_size: 4}
    frame = %Frame{size: 4}

    queue =
      queue
      |> Queue.push(spec)
      |> Queue.push(frame)

    assert Queue.ready?(queue)
    assert Queue.any?(queue)
    assert Queue.size(queue) == 1
    refute Queue.closed?(queue)

    {_value, queue} = Queue.pop!(queue)
    assert Queue.size(queue) == 0
  end

  test "closes when end_of_stream arrives with no ready frames" do
    queue = Queue.new()
    queue = Queue.push(queue, :end_of_stream)

    assert Queue.closed?(queue)
  end
end
