# typed: false
module Cyclone
  module Chords
    NOTES = {
      "c" => 0,
      "c#" => 1,
      "csharp" => 1,
      "db" => 1,
      "dflat" => 1,
      "d" => 2,
      "dsharp" => 3,
      "d#" => 3,
      "eb" => 3,
      "eflat" => 3,
      "e" => 4,
      "f" => 5,
      "f#" => 6,
      "fsharp" => 6,
      "gb" => 6,
      "gflat" => 6,
      "g" => 7,
      "g#" => 8,
      "gsharp" => 8,
      "ab" => 8,
      "aflat" => 8,
      "a" => 9,
      "a#" => 10,
      "asharp" => 10,
      "bb" => 10,
      "bFlat" => 10,
      "b" => 11
    }.freeze

    def half_step_transpose(chord, half_steps = 0)
      return chord.map { |note| note + half_steps } if half_steps.instance_of? Integer

      raise ArgumentError, "Cannot transpose by non-integer value"
    end

    def key_transpose(chord, key = "c")
      return chord.map { |note| note + NOTES[key] } if NOTES.include? key

      raise ArgumentError, "Cannot transpose chord to undefined key #{key}"
    end

    def transpose(chord, key = "c")
      unless chord.all?{ |el| el.respond_to?(:to_i) }
        raise ArgumentError, "Invalid chord description. Must be list of Integers" 
      end

      return key_transpose(chord.map(&:to_i), key.downcase) if key.instance_of? String
      return half_step_transpose(chord.map(&:to_i), key) if key.instance_of? Integer

      raise ArgumentError, "Invalid key argument"
    end

    # major chords
    def major(key = "c")
      chord = [0,4,7]
      transpose(chord, key)
    end
    alias maj major
    alias M major

    def aug(key = "c")
      chord = [0,4,8]
      transpose(chord, key)
    end
    alias plus aug
    alias sharp5 aug

    def six(key = "c")
      chord = [0,4,7,9]
      transpose(chord, key)
    end

    def six_nine(key = "c")
      chord = [0,4,7,9,14]
      transpose(chord, key)
    end
    alias six9 six_nine
    alias sixby9 six_nine

    def major7(key = "c")
      chord = [0,4,7,11]
      transpose(chord, key)
    end
    alias maj7 major7
    alias M7 major7

    def major9(key = "c")
      chord = [0,4,7,11,14]
      transpose(chord, key)
    end
    alias maj9 major9
    alias M9 major9

    def add9(key = "c")
      chord = [0,4,7,14]
      transpose(chord, key)
    end
    alias dom9 add9

    def major11(key = "c")
      chord = [0,4,7,11,14,17]
      transpose(chord, key)
    end
    alias maj11 major11
    alias M11 major11

    def add11(key = "c")
      chord = [0,4,7,17]
      transpose(chord, key)
    end
    alias dom11 add11

    def major13(key = "c")
      chord = [0,4,7,11,14,21]
      transpose(chord, key)
    end
    alias maj13 major13
    alias M13 major13

    def add13(key = "c")
      chord = [0,4,7,21]
      transpose(chord, key)
    end
    alias dom13 add13

    # dominant chords
    def dom7(key = "c")
      chord = [0,4,7,10]
      transpose(chord, key)
    end

    def sevenFlat5(key = "c")
      chord = [0,4,6,10]
      transpose(chord, key)
    end

    def sevenSharp5(key = "c")
      chord = [0,4,8,10]
      transpose(chord, key)
    end

    def sevenFlat9(key = "c")
      chord = [0,4,7,10,13]
      transpose(chord, key)
    end

    def nine(key = "c")
      chord = [0,4,7,10,14]
      transpose(chord, key)
    end

    def eleven(key = "c")
      chord = [0,4,7,10,14,17]
      transpose(chord, key)
    end

    def thirteen(key = "c")
      chord = [0,4,7,10,14,17,21]
      transpose(chord, key)
    end

    # minor chords
    def minor(key = "c")
      chord = [0,3,7]
      transpose(chord, key)
    end
    alias min minor
    alias m minor

    def diminished(key = "c")
      chord = [0,3,6]
      transpose(chord, key)
    end
    alias dim diminished

    def minorSharp5(key = "c")
      chord = [0,3,8]
      transpose(chord, key)
    end
    alias minSharp5 minorSharp5
    alias mSharp5 minorSharp5
    alias mS5 minorSharp5

    def minor6(key = "c")
      chord = [0,3,7,9]
      transpose(chord, key)
    end
    alias min6 minor6
    alias m6 minor6

    def minorSixNine(key = "c")
      chord = [0,3,9,7,14]
      transpose(chord, key)
    end
    alias minSixNine minorSixNine
    alias minor69 minorSixNine
    alias min69 minorSixNine
    alias m69 minorSixNine
    alias m6by9 minorSixNine

    def minor7flat5(key = "c")
      chord = [0,3,6,10]
      transpose(chord, key)
    end
    alias min7flat5 minor7flat5
    alias min7f5 minor7flat5
    alias m7flat5 minor7flat5
    alias m7f5 minor7flat5


    def minor7(key = "c")
      chord = [0,3,7,10]
      transpose(chord, key)
    end
    alias min7 minor7
    alias m7 minor7

    def minor7sharp5(key = "c")
      chord = [0,3,8,10]
    end
    alias minor7s5 minor7sharp5
    alias min7sharp5 minor7sharp5
    alias min7s5 minor7sharp5
    alias m7sharp5 minor7sharp5
    alias m7s5 minor7sharp5

    def minor7flat9(key = "c")
      chord = [0,3,7,10,14]
      transpose(chord, key)
    end
    alias minor7f9 minor7flat9
    alias min7flat9 minor7flat9
    alias min7f9 minor7flat9
    alias m7flat9 minor7flat9
    alias m7f9 minor7flat9

    def minor7sharp9(key = "c")
      chord = [0,3,7,10,14]
      transpose(chord, key)
    end
    alias minor7s9 minor7sharp9
    alias min7sharp9 minor7sharp9
    alias m7sharp9 minor7sharp9
    alias m7s9 minor7sharp9

    def diminished7(key = "c")
      chord = [0,3,6,9]
      transpose(chord, key)
    end
    alias dim7 diminished7

    def minor9(key = "c")
      chord = [0,3,7,10,14]
      transpose(chord, key)
    end
    alias min9 minor9
    alias m9 minor9

    def minor11(key = "c")
      chord = [0,3,7,10,14,17]
      transpose(chord, key)
    end
    alias min11 minor11
    alias m11 minor11

    def minor13(key = "c")
      chord = [0,3,7,10,14,17,21]
      transpose(chord, key)
    end
    alias min13 minor13
    alias m13 minor13

    # other chords
    def one(key = "c")
      chord = [0]
      transpose(chord, key)
    end

    def five(key = "c")
      chord = [0, 7]
      transpose(chord, key)
    end

    def sus2(key = "c")
      chord = [0,2,7]
      transpose(chord, key)
    end

    def sus4(key = "c")
      chord = [0,5,7]
      transpose(chord, key)
    end

    def sevenSus2(key = "c")
      chord = [0,2,7,10]
      transpose(chord, key)
    end

    def sevenSus4(key = "c")
      chord = [0,5,7,10]
      transpose(chord, key)
    end

    def nineSus4(key = "c")
      chord = [0,5,7,10,14]
      transpose(chord, key)
    end

    # questionable chords?
    def sevenFlat10(key = "c")
      chord = [0,4,7,10,15]
      transpose(chord, key)
    end

    def nineSharp5(key = "c")
      chord = [0,1,13]
      transpose(chord, key)
    end

    def minor9sharp5(key = "c")
      chord = [0,1,14]
      transpose(chord, key)
    end
    alias minor9s5 minor9sharp5
    alias min9sharp5 minor9sharp5
    alias min9s5 minor9sharp5
    alias m9sharp5 minor9sharp5
    alias m9s5 minor9sharp5

    def sevenSharp5flat9(key = "c")
      chord = [0,4,8,10,13]
      transpose(chord, key)
    end

    def minor7sharp5flat9
      chord = [0,3,8,10,13]
      transpose(chord, key)
    end
    alias minor7s5f9 minor7sharp5flat9
    alias min7sharp5flat9 minor7sharp5flat9
    alias min7s5f9 minor7sharp5flat9
    alias m7sharp5flat9 minor7sharp5flat9
    alias m7s5f9 minor7sharp5flat9

    def elevenSharp(key = "c")
      chord = [0,4,7,10,14,18]
      transpose(chord, key)
    end

    def minorElevenSharp(key = "c")
      chord = [0,3,7,10,14,18]
      transpose(chord, key)
    end
    alias minor11sharp minorElevenSharp
    alias minElevenSharp minorElevenSharp
    alias min11sharp minorElevenSharp
    alias m11sharp minorElevenSharp
    alias m11s minorElevenSharp
  end
end
