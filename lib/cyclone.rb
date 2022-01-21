# typed: true
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"
require_relative "cyclone/version"

module Cyclone
  extend T::Sig

  include Kernel

  class Error < StandardError; end

  # Better formatting for printing Tidal Patterns
  sig { params(pattern: Pattern, query_span: TimeSpan).void }
  def pattern_pretty_printing(pattern:, query_span:)
    pattern.query.call(query_span).each do |event|
      puts event.to_s
    end
    nil
  end

  sig { returns(T.untyped) }
  def smoke_test
    a = atom("hello")
    b = atom("world")
    c = fastcat([a, b])
    d = stack([a, b])

    #  Printing the pattern
    puts "\n== TEST PATTERN ==\n"
    puts 'Like: "hello world" (over two cycles)'
    pattern_pretty_printing(
      pattern: c,
      query_span: TimeSpan.new(0, 2)
    )

    # Printing the pattern with fast
    puts "\n== SAME BUT FASTER ==\n"
    puts 'Like: fast 4 "hello world"'
    pattern_pretty_printing(
      # recall that `_fast` takes a `factor` as an argument
      #  and returns a pattern
      pattern: c._fast(2),
      query_span: TimeSpan.new(0, 1)
    )

    # Printing the pattern with patterned fast
    puts "\n== SAME BUT FASTER ==\n"
    puts 'Like: fast "2 4" "hello world"'
    pattern_pretty_printing(
      # recall that fast (no underscore) takes a `pattern_of_factors` as an argument
      # and returns a pattern
      pattern: c.fast(fastcat([atom(2), atom(4)])),
      query_span: TimeSpan.new(0, 1)
    )

    # Printing the pattern with stack
    puts("\n== STACK ==\n")
    pattern_pretty_printing(
      pattern: d,
      query_span: TimeSpan.new(0, 1)
    )

    # Printing the pattern with late
    puts("\n== LATE ==\n")
    pattern_pretty_printing(
      pattern: c.late(0.5),
      query_span: TimeSpan.new(0, 1)
    )

    # Apply pattern of values to a pattern of functions
    puts("\n== APPLICATIVE ==\n")
    x = fastcat([atom(->(v) { v + 1 }), atom(->(v) { v + 2 })])
    y = fastcat([atom(3), atom(4), atom(5)])
    z = x.app(y)
    pattern_pretty_printing(
      pattern: z,
      query_span: TimeSpan.new(0, 1)
    )

    # Add number patterns together
    puts("\n== ADDITION ==\n")
    numbers = fastcat([2, 3, 4, 5].map { |v| atom(v) })
    more_numbers = fastcat([atom(10), atom(100)])
    pattern_pretty_printing(
      pattern: numbers + more_numbers,
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== EMBEDDED SEQUENCES ==\n")
    # sequence([0,1,[2, [3, 4]]]) is the same as "[0 1 [2 [3 4]]]" in Tidal's mininotation
    pattern_pretty_printing(
      pattern: sequence([0, 1, [2, [3, [4]]]]),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYRHYTHM  ==\n")
    pattern_pretty_printing(
      pattern: polyrhythm([[0, 1, 2, 3], [20, 30]]),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYRHYTHM (fewer steps) ==\n")
    pattern_pretty_printing(
      pattern: polyrhythm([[0, 1, 2, 3], [20, 30]], steps: 2),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYMETER ==\n")
    pattern_pretty_printing(
      pattern: polymeter([[0, 1, 2, 3], [20, 30]]),
      query_span: TimeSpan.new(0, 1)
    )

    print("\n== POLYMETER (w/ embedded polyrhythm) ==\n")
    pattern_pretty_printing(
      pattern: pm([pr([[100, 200, 300, 400], [0, 1]]), [20, 30]]),
      query_span: TimeSpan.new(0, 1)
    )
  end

  # Identity function
  sig { returns(T.proc.params(value: T.untyped).returns(T.untyped)) }
  def id
    ->(value) { value }
  end

  ########### Fundamental patterns

  sig { returns(Pattern) }
  def silence
    Pattern.new(->(_span) { [] })
  end

  # A continuous value
  sig { params(value: T.untyped).returns(Pattern) }
  def steady(value)
    signal ->(_t) { value }
  end

  # Repeat discrete value once per cycle
  sig { params(value: T.untyped).returns(Pattern) }
  def pure(value)
    query = lambda do |span|
      span.span_cycles.map do |s|
        Event.new(s.start.whole_cycle, s, value)
      end
    end

    Pattern.new(query)
  end
  alias_method :atom, :pure

  sig { params(thing: T.untyped).returns(Pattern) }
  def sequence(thing)
    _sequence(thing).first
  end

  sig { params(thing: T.untyped).returns([Pattern, Integer]) }
  def _sequence(thing)
    case thing.class
    when Array
      [fastcat(thing.map { |x| sequence(x) }), thing.size]
    when Pattern
      [thing, 1]
    else
      [atom(thing), 1]
    end
  end

  sig { params(things: T.untyped, steps: T.nilable(Integer)).returns(Pattern) }
  def polyrhythm(things, steps: nil)
    sequences = things.map { |thing| _sequence(thing) }
    return silence if sequences.empty?

    steps = sequences[0][1] if steps.nil?
    patterns = []
    sequences.each do |(pattern, sequence_length)|
      next if sequence_length.zero?

      patterns << pattern if steps == sequence_length
      patterns << pattern._fast(steps.to_r / sequence_length.to_r)
    end

    stack patterns
  end
  alias_method :pr, :polyrhythm

  sig { params(things: T::Array[T.untyped]).returns(Pattern) }
  def polymeter(things)
    sequences = things.map { |thing| sequence(thing) }
    return silence if sequences.empty?

    stack sequences
  end
  alias_method :pm, :polymeter

  ########### Signals

  #  A continuous pattern as a function from time to values. Takes the
  #  midpoint of the given query as the time value.
  sig { params(time_fun: T.proc.params(time: Rational).returns(T.untyped)).returns(Pattern) }
  def signal(time_fun)
    query = lambda do |span|
      midpoint = span.start + (span.stop - span.start) / 2
      [Event.new(nil, span, time_fun.call(midpoint.to_r))]
    end

    Pattern.new(query)
  end

  # Concatenation: combines a list of patterns, switching between them
  # successively, one per cycle.
  # (currently behaves slightly differently from Tidal)
  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def slowcat(patterns)
    query = lambda do |span|
      pattern = patterns[span.start.floor % patterns.size]
      T.must(pattern).query.call(span)
    end
    pattern = Pattern.new(query)
    pattern.split_queries
  end

  # Concatenation: as with slowcat, but squashes a cycle from each
  # pattern into one cycle
  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def fastcat(patterns)
    slowcat(patterns)._fast(patterns.size)
  end
  alias_method :cat, :fastcat

  # Pile up patterns
  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def stack(patterns)
    query = lambda do |span|
      patterns.flat_map { |pattern| pattern.query.call(span) }
    end

    Pattern.new(query)
  end

  module_function(
    :atom,
    :pure,
    :id,
    :silence,
    :slowcat,
    :fastcat,
    :stack,
    :_sequence,
    :sequence,
    :polyrhythm,
    :pr,
    :polymeter,
    :pm,
    :signal
  )
end
