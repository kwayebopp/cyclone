# turn off the pattern by making the value an empty hash
def zzz
  lambda do |pattern|
    pattern.with_value(->(_) { {} })
  end
end