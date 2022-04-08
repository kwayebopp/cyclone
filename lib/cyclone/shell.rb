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
@muted_streams = {}

def cyclone_help
  puts("Welcome to the Cyclone interactive shell!")
  puts()
  puts("use `d1(pattern)` to set a pattern for the default stream `:d1`.")
  puts("there are 12 default streams: :d1, :d2, :d3,..., :d12.")
  puts()
  puts("use `p(name, pattern)` create a stream with a custom name and set its pattern.")
  puts()
  puts("use `ps` to print a list of all of your streams.")
  puts()
  puts("use `m stream_name` to mute a stream. you can mute multiple streams by separating them with commas.")
  puts()
  puts("use `um stream_name` to unmute a stream. you can unmute multiple streams by separating them with commas.")
  puts()
  puts("use `k stream_name` to kill a stream. you can kill multiple streams by separating them with commas.")
  puts()
  puts("use `hush` to silence all streams.")
  puts()
  puts("use `echo` to enable value inspection in the shell.")
  puts("this is useful for inspecting the structure of patterns and the output of evaluated statements.")
  puts()
  puts("use `noecho` to disable value inspection in the shell.")
  puts("if you would like to print the value of a statement while in `noecho`, use `pp my_statement`.")
  puts()
  puts("use `q` to exit the shell.")
  puts()
  puts("use `h` to view this help message.")
end
alias h cyclone_help

# for defining named outputs
def p(key, pattern)
  if key.respond_to?(:to_sym)
    symbol = key.to_sym
    unless @streams.keys.include?(symbol)
      stream = SuperDirtStream.new
      @default_clock.subscribe(stream)
      @streams[symbol] = stream
    end
    @streams[symbol].pattern = pattern
    return pattern
  end
  raise ArgumentError, "stream name must be a string (e.g., 'foo') or a symbol (e.g., :foo)"
end

# definining dirt streams d1-d12 as functions
(1..12).each do |i|
  define_method("d#{i}") do |arg|
    p("d#{i}", arg)
  end
end

def hush
  kill_streams(*@streams.keys)
  @streams.clear
end

def clock
  @default_clock
end

def streams
  @streams
end

def muted_streams
  @muted_streams
end

def list_streams
  @streams.keys
end
alias ls list_streams

def put_streams
  puts ls.to_s
end
alias ps put_streams

def mute_streams(*keys)
  keys.map(&:to_sym).each do |k|
    if streams.include?(k)
      muted_streams[k] = streams[k]
      streams[k].pattern = silence
    end
  end
end

alias m mute_streams

def unmute_streams(*keys)
  keys.map(&:to_sym).each do |k|
    if muted_streams.include?(k)
      streams[k] = muted_streams[k]
      muted_streams.delete(k)
    end
  end
end
alias um unmute_streams

def solo_streams(*keys)
  streams.each do |key, _stream|
    unmute_streams(key) if muted_streams.include?(key)
    mute_streams(key) unless keys.map(&:to_sym).include?(key)
  end
end
alias solo solo_streams

def stack_streams(new_name, keys)
  streams_to_stack = streams.map do |name, stream|
    stream.pattern if keys.map(&:to_sym).include?(name)
  end

  kill_streams(*keys)
  p(new_name, stack(streams_to_stack))
end

def kill_streams(*keys)
  keys.map(&:to_sym).each do |k|
    streams[k].pattern = silence
    clock.unsubscribe(muted_streams.delete(k))
    clock.unsubscribe(streams.delete(k))
  end
end
alias ks kill_streams

def clear
  system 'clear'
end
alias c clear

def echo
  conf.echo = true
  pp "ECHO MODE ENABLED"
end

def noecho
  conf.echo = false
  pp "NOECHO MODE ENABLED"
end
