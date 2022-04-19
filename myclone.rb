# turn off the pattern by making the value an empty hash
def zzz
  lambda do |pattern|
    pattern.with_value(->(_) { {} })
  end
end

# extend the Pattern class to support a custom instance method
class Cyclone::Pattern
  def zzz_every(count)
    every(count, zzz)
  end
end