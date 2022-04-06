# typed: strict
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"

# `Pattern` class, representing discrete and continuous `Event`s as a
# function of time.
module Cyclone
  extend T::Sig
  extend self

  # Identity function
  sig { returns(T.proc.params(value: T.untyped).returns(T.untyped)) }
  def id
    ->(value) { value }
  end
  class Pattern
    extend T::Sig
    Query = T.type_alias { T.proc.params(span: TimeSpan).returns(T::Array[Event]) }

    sig { returns(Query) }
    attr_accessor :query

    sig { params(query: Query).void }
    def initialize(query)
      @query = query
    end

    # Splits queries at cycle boundaries. Makes some calculations easier
    # to express, as everything then happens within a cycle.
    sig { returns(Pattern) }
    def split_queries
      query = lambda do |span|
        span.span_cycles.flat_map(&self.query)
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to the `TimeSpan` of the query.
    sig { params(span_lambda: TimeSpan::SpanLambda).returns(Pattern) }
    def with_query_span(span_lambda)
      query = lambda do |span|
        self.query.call(span_lambda.call(span))
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of the the query `TimeSpan`.
    sig { params(time_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_query_time(time_lambda)
      query = lambda do |span|
        self.query.call(span.with_time(time_lambda))
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to each `Event`
    # timespan.
    sig { params(fun: TimeSpan::SpanLambda).returns(Pattern) }
    def with_event_span(fun)
      query = lambda do |span|
        self.query.call(span).map { |event| event.with_span(fun) }
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of each event `TimeSpan`.
    sig { params(time_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_event_time(time_lambda)
      with_event_span(->(span) { span.with_time(time_lambda) })
    end

    # Returns a new `Pattern`, with the function applied to the value of
    # each `Event`. It has the alias 'fmap'
    sig { params(fun: Event::ValueLambda).returns(Pattern) }
    def with_value(fun)
      query = lambda do |span|
        self.query.call(span).map { |event| event.with_value(fun) }
      end

      self.class.new(query)
    end
    alias fmap with_value

    # Returns a new pattern that will only return events where the start
    # of the 'whole' timespan matches the start of the 'part'
    # timespan, i.e. the events that include their 'onset'
    sig { returns(Pattern) }
    def onsets_only
      query = lambda do |span|
        self.query.call(span).select(&:has_onset?)
      end

      self.class.new(query)
    end

    sig { params(count: Integer, fun: T.proc.params(pattern: Pattern).returns(Pattern)).returns(Pattern) }
    def every(count, fun)
      Pattern.slowcat([fun.call(self)] + ([self] * (count - 1)))
    end

    # Speeds up a `Pattern` by the given `factor``
    sig { override(allow_incompatible: true).params(factor: Numeric).returns(Pattern) }
    def _fast(factor)
      fast_query = with_query_time(->(t) { t * factor })
      fast_query.with_event_time(->(t) { t / factor })
    end

    sig { override(allow_incompatible: true).params(factor: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def fast(factor)
      Pattern.sequence(factor).fmap(->(fac) { _fast(fac) }).outer_join
    end

    # Slow slows down a `Pattern` by the given `factor`
    sig { override(allow_incompatible: true).params(factor: Numeric).returns(Pattern) }
    def _slow(factor)
      _fast(1 / factor.to_f)
    end

    sig { override(allow_incompatible: true).params(factor: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def slow(factor)
      Pattern.sequence(factor).fmap(->(fac) { _slow(fac) }).outer_join
    end

    # Equivalent of Tidal's `<~` operator
    sig { override(allow_incompatible: true).params(offset: Numeric).returns(Pattern) }
    def _early(offset)
      with_query_time(->(t) { t + offset }).with_event_time(->(t) { t - offset })
    end

    sig { override(allow_incompatible: true).params(offset: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def early(offset)
      Pattern.sequence(offset).fmap(->(ofst) { _early(ofst) }).outer_join
    end

    # Equivalent of Tidal's `~>` operator
    sig { override(allow_incompatible: true).params(offset: Numeric).returns(Pattern) }
    def _late(offset)
      early(-offset)
    end

    sig { override(allow_incompatible: true).params(offset:  T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def late(offset)
      Pattern.sequence(offset).fmap(->(ofst) { _late(ofst) }).outer_join
    end

    sig { returns(T::Array[Event]) }
    def first_cycle
      query.call(TimeSpan.new(0, 1))
    end

    sig { returns(Pattern) }
    def self.silence
      new(->(_) { [] })
    end

    sig { params(_value: T.untyped).returns(T::Boolean) }
    def self.check_type(_value)
      true
    end

    # Returns a pattern that repeats the given value once per cycle
    sig { params(value: T.untyped).returns(Pattern) }
    def self.pure(value)
      raise ArgumentError unless check_type(value)

      query = lambda do |span|
        span.span_cycles.map do |s|
          Event.new(s.start.whole_cycle, s, value)
        end
      end

      new(query)
    end
    class << self
      alias atom pure
    end

    # Concatenation: combines a list of patterns, switching between them
    # successively, one per cycle.
    # (currently behaves slightly differently from Tidal)
    sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
    def self.slowcat(patterns)
      query = lambda do |span|
        pattern = patterns[span.start.floor % patterns.size]
        T.must(pattern).query.call(span)
      end

      new(query).split_queries
    end

    # Concatenation: as with slowcat, but squashes a cycle from each
    # pattern into one cycle
    sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
    def self.fastcat(patterns)
      slowcat(patterns)._fast(patterns.size)
    end
    class << self
      alias cat fastcat
    end

    # Pile up patterns
    sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
    def self.stack(patterns)
      query = lambda do |span|
        patterns.flat_map { |pattern| pattern.query.call(span) }
      end

      new(query)
    end

    sig { params(thing: T.any(T::Array[T.untyped], Pattern, T.untyped)).returns(Pattern) }
    def self.sequence(thing)
      _sequence(thing).first
    end

    sig { params(thing: T.any(T::Array[T.untyped], Pattern, T.untyped)).returns([Pattern, Integer]) }
    def self._sequence(thing)
      case thing
      when Array
        [fastcat(thing.map { |x| sequence(x) }), thing.size]
      when Pattern
        [thing, 1]
      else
        [atom(thing), 1]
      end
    end

    sig { params(things: T::Array[T.untyped], steps: T.nilable(Integer)).returns(Pattern) }
    def self.polymeter(things, steps: nil)
      sequences = things.map { |thing| _sequence(thing) }
      return silence if sequences.empty?

      steps = T.cast(sequences[0], [Pattern, Integer])[1] if steps.nil?
      patterns = []
      sequences.each do |(pattern, sequence_length)|
        next if sequence_length.zero?

        patterns << pattern if steps == sequence_length
        patterns << pattern._fast(steps.to_r / sequence_length.to_r)
      end

      stack patterns
    end
    class << self
      alias pm polymeter
    end


    sig { params(things: T::Array[T.untyped]).returns(Pattern) }
    def self.polyrhythm(things)
      sequences = things.map { |thing| sequence(thing) }
      return silence if sequences.empty?

      stack sequences
    end
    class << self
      alias pr polyrhythm
    end

    # Pattern Controls
    sig do
      params(
        control_name: T.any(Symbol, String),
        pattern: T.any(Pattern, T.untyped)
      ).returns(Cyclone::Control)
    end
    def self.make_control(control_name, pattern)
      control_lambda = ->(value) { {control_name.to_s => value} }
      pat = pattern.instance_of?(Pattern) ? T.cast(pattern, Pattern) : sequence(pattern)
      Control.new(pat.fmap(control_lambda).query)
    end

    sig { params(pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
    def self.sound(pattern)
      make_control(:sound, pattern)
    end
    class << self
      alias s sound
    end

    sig { params(pattern: T.any(Pattern, String, T::Array[String])).returns(Pattern) }
    def self.vowel(pattern)
      make_control(:vowel, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.n(pattern)
      make_control(:n, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.note(pattern)
      make_control(:note, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.rate(pattern)
      make_control(:rate, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.gain(pattern)
      make_control(:gain, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.pan(pattern)
      make_control(:pan, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.speed(pattern)
      make_control(:speed, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.room(pattern)
      make_control(:room, pattern)
    end

    sig { params(pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def self.size(pattern)
      make_control(:size, pattern)
    end

    sig { params(thing: T.untyped).returns(Pattern) }
    def self.reify(thing)
      return thing if thing.instance_of?(self)

      pure(thing)
    end

    # Tidal's `<*>` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def app(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return this.intersect(that) unless this.nil? || that.nil?
      end

      _app_whole(whole_fun, pattern_of_vals)
    end

    # Tidal's `<*` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def appl(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return this unless this.nil? || that.nil?
      end

      _app_whole(whole_fun, pattern_of_vals)
    end

    # Tidal's `*>` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def appr(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return that unless this.nil? || that.nil?
      end

      _app_whole(whole_fun, pattern_of_vals)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def bind(fun)
      whole_fun = lambda do |this, that|
        return this.intersect(that) unless this.nil? || that.nil?
      end
      _bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    # the intersection of matched inner and outer events.
    sig { returns(Pattern) }
    def join
      bind(Cyclone.id)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def inner_bind(fun)
      whole_fun = lambda do |this, that|
        return this unless this.nil? || that.nil?
      end
      _bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    # taken from inner events.
    sig { returns(Pattern) }
    def inner_join
      inner_bind(Cyclone.id)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def outer_bind(fun)
      whole_fun = lambda do |this, that|
        return that unless this.nil? || that.nil?
      end
      _bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    #  taken from outer events.
    sig { returns(Pattern) }
    def outer_join
      outer_bind(Cyclone.id)
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def +(other)
      # if instance_of?(Control) && other.instance_of?(Control)
      #   return  fmap(->(x) { ->(y) {
      #     if x.key?("sound") && y.key?("n")
      #       {"sound" => "#{x["sound"]}:#{y["n"]}"}
      #     elsif x.key?("n") && y.key?("n")
      #       {"n" => x["n"] + y["n"]}
      #     end
      #    } }).appl(self.class.reify(other)) 
      # end
      fmap(->(x) { ->(y) { x + y } }).app(self.class.reify(other))
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def -(other)
      fmap(->(x) { ->(y) { x - y } }).app(self.class.reify(other))
    end

    # The union of two patterns of dictionaries, with values from left
    # replacing any with the same name from the right
    sig { params(other: Pattern).returns(Pattern) }
    def <<(other)
      fmap(->(x) { ->(y) { {**y, **x} } }).app(other)
    end

    # Overrides the >> operator to support combining patterns of
    # hashes (AKA 'control patterns'). Produces the union of
    # two patterns of hashes, with values from right replacing
    # any with the same name from the left
    sig { params(other: Pattern).returns(Pattern) }
    def >>(other)
      fmap(->(x) { ->(y) { {**x, **y} } }).app(other)
    end

    sig { returns(String) }
    def inspect
      query.call(TimeSpan.new(0, 1)).inspect
    end

    private

    # Assumes self is a pattern of functions, and given a function to
    # resolve wholes, applies a given pattern of values to that pattern
    # of functions.
    sig do
      params(
        whole_fun: T.proc.params(
          arg0: TimeSpan,
          arg1: TimeSpan
        ).returns(T.nilable(TimeSpan)),
        pattern_of_vals: Pattern
      ).returns(Pattern)
    end
    def _app_whole(whole_fun, pattern_of_vals)
      pattern_of_funs = self
      query = lambda do |span|
        event_funs = pattern_of_funs.query.call(span)
        event_vals = pattern_of_vals.query.call(span)
        apply = lambda do |event_fun, event_val|
          intersection = event_fun.part.maybe_intersect(event_val.part)
          unless intersection.nil?
            Event.new(
              whole_fun.call(event_fun.whole, event_val.whole),
              intersection,
              event_fun.value.call(event_val.value)
            )
          end
        end
        event_funs.flat_map do |event_fun|
          # .compact to eliminate `nil`s that may be returned from `apply`
          event_vals.map { |event_val| apply.call(event_fun, event_val) }.compact
        end
      end
      self.class.new(query)
    end

    sig do
      params(
        choose_whole: T.proc.params(
          this_event: Event,
          that_event: Event
        ).returns(T.nilable(TimeSpan)),
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def _bind_whole(choose_whole, fun)
      pattern_of_values = self
      query = lambda do |span|
        with_whole = lambda do |this_event, that_event|
          Event.new(
            choose_whole.call(this_event.whole, that_event.whole),
            that_event.part,
            that_event.value
          )
        end
        match = lambda do |event|
          fun.call(event.value).query.call(event.part).map do |evt|
            with_whole.call(event, evt)
          end
        end
        pattern_of_values.query.call(span).flat_map(&match)
      end

      self.class.new(query)
    end
  end

  ########### Pattern Classes

  class StringPattern < Pattern
    extend T::Sig

    class << self
      undef_method(:n)
      undef_method(:note)
      undef_method(:rate)
      undef_method(:gain)
      undef_method(:pan)
      undef_method(:speed)
      undef_method(:room)
      undef_method(:size)
    end

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(String)
    end
  end

  S = StringPattern
  class FloatPattern < Pattern
    extend T::Sig

    class << self
      undef_method(:s)
      undef_method(:sound)
      undef_method(:vowel)
    end

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Float) || value.instance_of?(Integer)
    end
  end

  F = FloatPattern

  class IntegerPattern < Pattern
    extend T::Sig

    class << self
      undef_method(:s)
      undef_method(:sound)
      undef_method(:vowel)
    end

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Integer)
    end
  end

  I = IntegerPattern

  class RationalPattern < Pattern
    extend T::Sig

    class << self
      undef_method(:s)
      undef_method(:sound)
      undef_method(:vowel)
    end

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Rational)
    end
  end

  R = RationalPattern


  class Control < Pattern
    extend T::Sig

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Hash)
    end
  end
end
