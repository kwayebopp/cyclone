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
      # recall that `faster` takes a `factor` as an argument
      #  and returns a pattern
      pattern: c.faster(2),
      query_span: TimeSpan.new(0, 1)
    )

    # Printing the pattern with patterned fast
    puts "\n== SAME BUT FASTER ==\n"
    puts 'Like: fast "2 4" "hello world"'
    pattern_pretty_printing(
      # recall that fast (no underscore) takes a `pattern_of_factors` as an argument
      # and returns a pattern
      pattern: c.fast([2, 4]),
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
    z = x.app_both(y)
    pattern_pretty_printing(
      pattern: z,
      query_span: TimeSpan.new(0, 1)
    )

    # Add number patterns together
    puts("\n== ADDITION ==\n")
    numbers = sequence([2, 3, 4, 5])
    more_numbers = sequence([10, 100])
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

    puts("\n== POLYMETER  ==\n")
    pattern_pretty_printing(
      pattern: I.polymeter([[0, 1, 2, 3], [20, 30]]),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYMETER (fewer steps) ==\n")
    pattern_pretty_printing(
      pattern: I.polymeter([[0, 1, 2, 3], [20, 30]], steps: 2),
      query_span: TimeSpan.new(0, 1)
    )

    puts("\n== POLYRHYTHM ==\n")
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
        T.class_of(C)
      )
    )
  end
  def guess_value_class(value)
    # return guess_value_class(value.first) if value.instance_of? Array
    return I if I.check_type(value)
    return S if S.check_type(value)
    return F if F.check_type(value)
    return R if R.check_type(value)
    return C if C.check_type(value)

    Pattern
  end

  ########### Fundamental patterns
  sig { returns(Pattern) }
  def silence
    Pattern.silence
  end

  sig { params(value: T.untyped).returns(Pattern) }
  def atom(value)
    guess_value_class(value).atom(value)
  end
  alias pure atom

  # A continuous value
  sig { params(value: T.untyped).returns(Pattern) }
  def steady(value)
    query = ->(span) { [Event.new(nil, span, value)] }
    Pattern.new(query)
  end

  sig { params(patterns: T::Array[T.untyped]).returns(Pattern) }
  def slowcat(patterns)
    return silence if patterns.empty?

    Pattern.slowcat(patterns)
  end
  alias cat slowcat

  sig { params(patterns: T::Array[T.untyped]).returns(Pattern) }
  def fastcat(patterns)
    return silence if patterns.empty?

    Pattern.fastcat(patterns)
  end

  sig { params(patterns: T::Array[T.untyped]).returns(Pattern) }
  def stack(patterns)
    return silence if patterns.empty?

    Pattern.stack(patterns)
  end

  sig { params(modifier: T.proc.params(pattern: Pattern).returns(Pattern), pattern: T.untyped).returns(Pattern) }
  def superimpose(modifier, pattern)
    Pattern.superimpose(modifier, pattern)
  end

  sig { params(modifiers: T::Array[T.proc.params(pattern: Pattern).returns(Pattern)], pattern: T.untyped).returns(Pattern) }
  def layer(modifiers, pattern)
    Pattern.layer(modifiers, pattern)
  end



  sig { params(things: T.untyped).returns(Pattern) }  
  def sequence(things)
    Pattern.sequence(things)
  end
  alias sq sequence

  sig { params(things: T::Array[T.untyped], steps: T.nilable(Integer)).returns(Pattern) }
  def polymeter(things, steps: nil)
    return silence if things.empty?

    klass =
      if things.first.instance_of?(Pattern)
        T.cast(things.first, Pattern).class
      else
        guess_value_class(things.first)
      end

    klass.polymeter(things, steps: steps)
  end
  alias pm polymeter

  sig { params(things: T::Array[T.untyped]).returns(Pattern) }
  def polyrhythm(things)
    return silence if things.empty?

    klass =
      if things.first.instance_of?(Pattern)
        T.cast(things.first, Pattern).class
      else
        guess_value_class(things.first)
      end

    klass.polyrhythm(things)
  end
  alias pr polyrhythm

  # the c stands for "curried"
  sig { returns(T.proc.returns(Pattern)) }
  def revc
    Cyclone.method(:inverted_rev).curry(1)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def fastc
    Cyclone.method(:inverted_fast).curry(2)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def slowc
    Cyclone.method(:inverted_slow).curry(2)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def earlyc
    Cyclone.method(:inverted_early).curry(2)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def latec
    Cyclone.method(:inverted_late).curry(2)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def everyc
    Cyclone.method(:inverted_every).curry(3)
  end

  sig { returns(T.proc.returns(Pattern)) }
  def appendc
    Cyclone.method(:inverted_append).curry(2)
  end
  alias slow_appendc appendc

  sig { returns(T.proc.returns(Pattern)) }
  def fast_appendc
    Cyclone.method(:inverted_fastappend).curry(2)
  end

  ########### Signals

  #  A continuous pattern as a function from time to values. Takes the
  #  midpoint of the given query as the time value.
  sig do
    params(
      time_fun: T.proc.params(time: Numeric).returns(T.untyped)
    ).returns(FloatPattern)
  end
  def signal(time_fun)
    query = lambda do |span|
      [Event.new(nil, span, time_fun.call(span.midpoint))]
    end

    FloatPattern.new(query)
  end

  sig { returns(FloatPattern) }
  def sine2
    signal(->(t) { Math.sin(Math::PI * 2 * t.to_f) })
  end

  sig { returns(FloatPattern) }
  def sine
    signal(->(t) { (Math.sin(Math::PI * 2 * t.to_f) + 1) / 2 })
  end

  sig { returns(Pattern) }
  def cosine2 
    sine2.early(0.25)
  end

  sig { returns(FloatPattern) }
  def cosine
   T.cast sine.early(0.25), FloatPattern
  end

  sig { returns(FloatPattern) }
  def saw2 
    signal(->(t) { ((t % 1) * 2).to_f })
  end

  sig { returns(FloatPattern) }
  def saw
    signal(->(t) { (t % 1).to_f })
  end

  sig { returns(FloatPattern) }
  def isaw2
    signal(->(t) { ((1 - (t % 1)) * 2).to_f })
  end

  sig { returns(FloatPattern) }
  def isaw
    signal(->(t) { (1 - (t % 1)).to_f })
  end

  sig { returns(FloatPattern) }
  def tri2
    T.cast fastcat([isaw2, saw2]), FloatPattern
  end

  sig { returns(FloatPattern) }
  def tri
    T.cast fastcat([isaw, saw]), FloatPattern
  end

  sig { returns(FloatPattern) }
  def square2 
    signal(->(t) { (((t * 2) % 2).floor * 2) - 1 })
  end

  sig { returns(FloatPattern) }
  def square  
    signal(->(t) { ((t * 2) % 2).floor })
  end

  sig { params(min: Numeric, max: Numeric, wave: FloatPattern).returns(FloatPattern) }
  def range(min, max, wave)
    T.cast wave.fmap(->(v) { v * min + (max - min) }), FloatPattern
  end

  private

  sig { params(factor: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def inverted_fast(factor, pattern)
    Pattern.sequence(pattern).fast(factor)
  end

  sig { params(factor: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def inverted_slow(factor, pattern)
    Pattern.sequence(pattern).slow(factor)
  end

  sig { params(offset: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def inverted_early(offset, pattern)
    Pattern.sequence(pattern).early(offset)
  end

  sig { params(offset: T.any(F, I, R, Numeric, T::Array[Numeric]), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def inverted_late(offset, pattern)
    Pattern.sequence(pattern).late(offset)
  end

  sig { params(count: Integer, fun: T.proc.params(pattern: Pattern).returns(Pattern), pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
  def inverted_every(count, fun, pattern)
    Pattern.sequence(pattern).every(count, fun)
  end

  sig { params(this: Pattern, that: Pattern).returns(Pattern) }
  def inverted_append(this, that)
    this.append(that)
  end

  sig { params(this: Pattern, that: Pattern).returns(Pattern) }
  def inverted_fast_append(this, that)
    this.fast_append(that)
  end

  sig { params(pattern: Pattern).returns(Pattern) }
  def inverted_rev(pattern)
    pattern.rev
  end
end