require "cyclone"
require_relative "./pattern"
require_relative "./event"
require_relative "./time_span"
require_relative "../rational"
require_relative "../stream/super_dirt_stream"
require_relative "../stream/link_clock"
require_relative "../proc"

include Cyclone

@default_clock = LinkClock.new(120)
@streams = {}

def p(key, pattern)
  unless @streams.keys.include?(key)
    stream = SuperDirtStream.new
    @default_clock.subscribe(stream)
    @streams[key] = stream
  end
  @streams[key].pattern = pattern
  pattern
end

def hush
  @streams.each_value do |stream|
    stream.pattern = silence
    @default_clock.unsubscribe(stream)
  end
  @streams.clear
end

def clock
  @default_clock
end

def streams
  @streams
end

def list_streams
  @streams.keys
end
alias ls list_streams

def mute_streams(*keys)
  keys.each do |k|
    @streams[k].pattern = silence
  end
end

alias m mute_streams

def solo_streams(*keys)
  @streams.each do |key, stream|
    stream.pattern = silence unless keys.include?(key)
  end
end
alias solo solo_streams

def stack_streams(name, keys)
  p(name, stack(streams.map { |k, stream| stream.pattern if keys.include?(k) }))

  @streams.each do |key, stream|
    stream.pattern = silence and @streams.delete(key) unless stream == @streams[name]
  end
end

def kill_streams(*keys)
  keys.each do |k|
    @streams[k].pattern = silence
    @streams.delete(k)
  end
end
alias ks kill_streams

def clear
  system 'clear'
end
alias c clear
