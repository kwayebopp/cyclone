# typed: strict
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"
require_relative "cyclone/version"
require_relative "cyclone/pattern"
require_relative "cyclone/event"
require_relative "cyclone/time_span"

module Cyclone
  include Kernel

  extend T::Sig
  extend self

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
    # simple patterns
    a = S.atom("hello")
    b = S.atom("world")
    c = S.fastcat([a, b])
    d = S.stack([a, b])

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
      pattern: c.fast(S.fastcat([F.pure(2), F.pure(4)])),
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
    x = F.fastcat([Pattern.pure(->(v) { v + 1 }), Pattern.pure(->(v) { v + 2 })])
    y = F.fastcat([F.pure(3), F.pure(4), F.pure(5)])
    z = x.app(y)
    pattern_pretty_printing(
      pattern: z,
      query_span: TimeSpan.new(0, 1)
    )

    # Add number patterns together
    puts("\n== ADDITION ==\n")
    numbers = F.fastcat([2, 3, 4, 5].map { |v| F.pure(v) })
    more_numbers = F.fastcat([F.pure(10), F.pure(100)])
    pattern_pretty_printing(
      pattern: numbers + more_numbers,
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== EMBEDDED SEQUENCES ==\n")
    # sequence([0,1,[2, [3, 4]]]) is the same as "[0 1 [2 [3 4]]]" in Tidal's mininotation
    pattern_pretty_printing(
      pattern: I.sequence([0, 1, [2, [3, [4]]]]),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYRHYTHM  ==\n")
    pattern_pretty_printing(
      pattern: I.polyrhythm([[0, 1, 2, 3], [20, 30]]),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYRHYTHM (fewer steps) ==\n")
    pattern_pretty_printing(
      pattern: I.polyrhythm([[0, 1, 2, 3], [20, 30]], steps: 2),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYMETER ==\n")
    pattern_pretty_printing(
      pattern: I.polymeter([[0, 1, 2, 3], [20, 30]]),
      query_span: TimeSpan.new(0, 1)
    )

    print("\n== POLYMETER (w/ embedded polyrhythm) ==\n")
    pattern_pretty_printing(
      pattern: I.pm([I.pr([[100, 200, 300, 400], [0, 1]]), [20, 30]]),
      query_span: TimeSpan.new(0, 1)
    )
  end

  sig do
    params(value: T.untyped).returns(
      T.any(
        T.class_of(Pattern),
        T.class_of(F),
        T.class_of(I),
        T.class_of(R),
        T.class_of(S),
        T.class_of(Control)
      )
    )
  end
  def guess_value_class(value)
    return I if I.check_type(value)
    return S if S.check_type(value)
    return F if F.check_type(value)
    return R if R.check_type(value)
    return Control if Control.check_type(value)

    Pattern
  end

  ########### Fundamental patterns
  sig { returns(Pattern) }
  def silence
    Pattern.silence
  end

  sig { params(value: T.untyped).returns(Pattern) }
  def pure(value)
    guess_value_class(value).pure(value)
  end
  alias atom pure

  # A continuous value
  sig { params(value: T.untyped).returns(Pattern) }
  def steady(value)
    signal ->(_t) { value }
  end

  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def slowcat(patterns)
    return silence if patterns.empty?

    T.cast(patterns.first, Pattern).class.slowcat(patterns)
  end

  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def fastcat(patterns)
    return silence if patterns.empty?

    T.cast(patterns.first, Pattern).class.fastcat(patterns)
  end
  alias cat fastcat

  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def stack(patterns)
    return silence if patterns.empty?

    T.cast(patterns.first, Pattern).class.stack(patterns)
  end

  sig { params(things: T::Array[T.untyped]).returns(T.any(Pattern, [Pattern, Integer])) }
  def _sequence(things)
    return silence if things.empty?

    klass =
      if things.first.instance_of(Pattern)
        T.cast(things.first, Pattern).class
      else
        guess_value_class(things.first)
      end

    klass._sequence(things)
  end

  sig { params(things: T::Array[T.untyped]).returns(Pattern) }
  def sequence(things)
    return silence if things.empty?

    klass =
      if things.first.instance_of?(Pattern)
        T.cast(things.first, Pattern).class
      else
        guess_value_class(things.first)
      end

    klass.sequence(things)
  end

  sig { params(things: T::Array[T.untyped], steps: T.nilable(Integer)).returns(Pattern) }
  def polyrhythm(things, steps: nil)
    return silence if things.empty?

    klass =
      if things.first.instance_of?(Pattern)
        T.cast(things.first, Pattern).class
      else
        guess_value_class(things.first)
      end

    klass.polyrhythm(things, steps: steps)
  end
  alias pr polyrhythm

  sig { params(things: T::Array[T.untyped]).returns(Pattern) }
  def polymeter(things)
    return silence if things.empty?

    klass =
      if things.first.instance_of?(Pattern)
        T.cast(things.first, Pattern).class
      else
        guess_value_class(things.first)
      end

    klass.polymeter(things)
  end
  alias pm polymeter

  ########### Controls

  sig { params(pattern: T.any(Pattern, S, String, T::Array[String])).returns(Pattern) }
  def sound(pattern)
    Pattern.sound(pattern)
  end
  alias s sound

  sig { params(pattern: T.any(Pattern, S, String, T::Array[String])).returns(Pattern) }
  def vowel(pattern)
    Pattern.vowel(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def n(pattern)
    Pattern.n(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def note(pattern)
    Pattern.note(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def rate(pattern)
    Pattern.rate(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def gain(pattern)
    Pattern.gain(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def pan(pattern)
    Pattern.pan(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def speed(pattern)
    Pattern.speed(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def room(pattern)
    Pattern.room(pattern)
  end

  sig { params(pattern: T.any(F, I, R, Numeric, T::Array[Numeric])).returns(Pattern) }
  def size(pattern)
    Pattern.size(pattern)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def fast
    Cyclone.method(:_fast).curry(2)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def slow
    Cyclone.method(:_slow).curry(2)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def early
    Cyclone.method(:_early).curry(2)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def late
    Cyclone.method(:_late).curry(2)
  end

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

  private

  sig { params(mthd: Method).returns(T.proc.returns(T.untyped)) }
  def currify(mthd)
    mthd.curry(mthd.arity)
  end

  sig { params(factor: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def _fast(factor, pattern)
    Pattern.sequence(pattern).fast(factor)
  end

  sig { params(factor: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def _slow(factor, pattern)
    Pattern.sequence(pattern).slow(factor)
  end

  sig { params(offset: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def _early(offset, pattern)
    Pattern.sequence(pattern).early(offset)
  end

  sig { params(offset: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def _late(offset, pattern)
    Pattern.sequence(pattern).late(offset)
  end
end