# typed: true
require "pycall"

class LinkClock
  attr_accessor :bpm

  def initialize(bpm = 120)
    link = PyCall.import_module "link"
    @subscribers = []
    @bpm = bpm
    @link = link.Link.new(bpm)
    @is_playing = false
    @mutex = Mutex.new
    @play_thread = Thread.new {
      Thread.stop
      play_thread_target
    }
  end

  def subscribe(subscriber)
    Thread.new {
      @mutex.synchronize { @subscribers << subscriber }
    }.join
    self
  end

  def unsubscribe(subscriber)
    Thread.new {
      @mutex.synchronize { @subscribers.delete(subscriber) }
    }.join
    self
  end

  def play
    Thread.new {
      @mutex.synchronize {
        @is_playing = true
      }
    }.join
    @play_thread.run
    self
  end

  def stop
    Thread.new {
      @mutex.synchronize { @is_playing = false }
    }.join
    self
  end

  private

  def play_thread_target
    @link.enabled = true
    @link.startStopSyncEnabled = true

    start = @link.clock.micros
    mill = 1_000_000
    start_beat = @link.captureSessionState.beatAtTime(start, 4)
    puts("start: " + start_beat.to_s)

    ticks = 0

    # rate, bpc and latency should be constructor args
    rate = 1.fdiv(20)
    frame = rate * mill
    bpc = 4

    while @is_playing
      ticks += 1

      logical_now = (start + (ticks * frame)).floor
      logical_next = (start + ((ticks + 1) * frame)).floor

      now = @link.clock.micros

      # wait until start of next frame
      wait = (logical_now - now).fdiv(mill)
      sleep(wait) if wait.positive?

      next unless @is_playing

      session_state = @link.captureSessionState
      cps = (session_state.tempo.fdiv(bpc)).fdiv(60)
      cycle_from = session_state.beatAtTime(logical_now, 0).fdiv(bpc)
      cycle_to = session_state.beatAtTime(logical_next, 0).fdiv(bpc)

      @subscribers.each do |subscriber|
        subscriber.notify_tick([cycle_from, cycle_to], session_state, cps, bpc, mill, now)
      end
    end
  end
end
