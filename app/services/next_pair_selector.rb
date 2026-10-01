# Decides the "Próximo" candidates of a poll page. ONE place for every public pair screen
# (home, /pairs/:hash, /pairs/:hash/results, Par do Dia).
#
# Every candidate is a pair hash ("smaller_id-bigger_id") that
#   * is NOT the current pair,
#   * is made of two options that are on the air (approved) right now,
#   * has the SAME category (good/bad) as the current pair. Only when the category has no other
#     pair at all, pairs of the other category are used, so the link still leads to a new poll.
# The result may be empty (there is no other pair at all): the page then links to the home page.
# Nothing here is random at click time: the page embeds the list when it is rendered.
class NextPairSelector
  POOL = 24  # pairs considered ...
  LIMIT = 8  # ... of which this many (the least voted) are embedded in the page

  # [candidate hashes], from the in-memory approved list: no query.
  def self.candidates(current_hash, generator: PairGenerator.new)
    new(current_hash, generator).candidates
  end

  # The `limit` candidates with the fewest votes (`totals`: { pair_hash => votes }), ties shuffled.
  def self.least_voted(hashes, totals, limit: LIMIT)
    hashes.shuffle.sort_by.with_index { |hash, index| [ totals[hash].to_i, index ] }.first(limit)
  end

  def initialize(current_hash, generator)
    @current_hash = current_hash.to_s
    @generator = generator
  end

  def candidates
    current = @generator.pair_by_hash(@current_hash)
    groups = @generator.pairable_options
    same = current ? groups.select { |options| options.first.category == current.first.category } : []
    found = hashes_from(same)
    found = hashes_from(groups) if found.empty?
    found.select { |hash| @generator.pair_by_hash(hash) } # last guard: both options still on the air
  end

  private

  # Small categories: every pair. Big ones: random draws (the number of pairs grows with n^2).
  def hashes_from(groups)
    found = Set.new
    groups.each do |options|
      if options.length <= 10
        options.combination(2).each { |pair| found << PairGenerator.hash_for(*pair) }
      else
        (POOL * 3).times do
          break if found.length >= POOL * 2

          found << PairGenerator.hash_for(*options.sample(2))
        end
      end
    end
    found.delete(@current_hash)
    found.to_a.shuffle.first(POOL)
  end
end
