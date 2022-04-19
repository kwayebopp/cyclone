# typed: false
require "cyclone"
require_relative "../../myclone"
require_relative "./pattern"
require_relative "./event"
require_relative "./time_span"
require_relative "../rational"
require_relative "../stream/super_dirt_stream"
require_relative "../stream/link_clock"
require_relative "../proc"
require_relative "./chords"
require_relative "./control"


include Cyclone
include Cyclone::Chords

@default_clock = LinkClock.new
@streams = {}
@muted_streams = {}

def cyclone_help
  puts("Welcome to the Cyclone interactive shell!")
  puts()
  puts("use `d1(pattern)` to set a pattern for the default stream `:d1`.")
  puts("there are 12 default streams: :d1, :d2, :d3,..., :d12.")
  puts()
  puts("use `p(id, pattern)` create a stream with a custom ID and set its pattern.")
  puts()
  puts("use `ps` to print a list of all of your stream IDs.")
  puts()
  puts("use `m stream_id` to mute a stream. you can mute multiple streams by separating their IDs with commas.")
  puts()
  puts("use `um stream_id` to unmute a stream. you can unmute multiple streams by separating their IDs with commas.")
  puts()
  puts("use `k stream_id` to kill a stream. you can kill multiple streams by separating them with commas.")
  puts()
  puts("use `hush` to silence all streams.")
  puts()
  puts("use `echo` to enable value inspection in the shell.")
  puts("this is useful for inspecting the structure of patterns and the output of evaluated statements.")
  puts()
  puts("use `noecho` to disable value inspection in the shell.")
  puts("if you would like to print the value of a statement while in `noecho` mode, use `pp my_statement`.")
  puts()
  puts("use `q` to exit the shell.")
  puts()
  puts("use `h` to view this help message.")
end
alias h cyclone_help

def setbpm(bpm)
  clock.bpm = bpm
end

# for defining named outputs
def p(id, pattern)
  if id.respond_to?(:to_sym)
    symbol_id = id.to_sym
    unless @streams.keys.include?(symbol_id)
      stream = SuperDirtStream.new
      @default_clock.subscribe(stream)
      @streams[symbol_id] = stream
    end
    @streams[symbol_id].pattern = pattern
    return pattern
  end
  raise ArgumentError, "stream ID must be a string (e.g., 'foo') or a symbol (e.g., :foo)"
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

def mute_streams(*ids)
  ids.map(&:to_sym).each do |id|
    if streams.include?(id)
      muted_streams[id] = streams[id].dup
      streams[id].pattern = silence
    end
  end
end

alias m mute_streams

def unmute_streams(*ids)
  ids.map(&:to_sym).each do |id|
    if muted_streams.include?(id)
      streams[id].pattern = muted_streams[id].pattern
      muted_streams.delete(id)
    end
  end
end
alias um unmute_streams

def solo_streams(*keys)
  arg_ids = keys.map(&:to_sym)
  streams.each do |id, _stream|
    unmute_streams(id) if muted_streams.include?(id)
    mute_streams(id) unless arg_ids.include?(id)
  end
end
alias solo solo_streams

def stack_streams(new_id, *stream_ids)
  patterns = streams.fetch_values(*(stream_ids.map(&:to_sym))).map(&:pattern)
  kill_streams(*stream_ids)
  p(new_id, stack(patterns))
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
  pp "ECHO MODE DISABLED"
end
