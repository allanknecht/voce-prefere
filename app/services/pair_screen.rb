# Everything a public poll page needs, built in ONE place for home, /pairs/:hash,
# /pairs/:hash/results and Par do Dia, so they cannot drift apart:
#
#   pair             two DIFFERENT options, both on the air (never nil/empty: otherwise there is no screen)
#   pair_hash        canonical "smaller-bigger"
#   percentages / total_votes   current numbers (shown only after voting, or on the results URL)
#   next_candidates  pair hashes for "Próximo" (see NextPairSelector), possibly empty
#   show_results     true only for the explicit results URL
#
# The factories return nil when there is no valid pair to show; the controllers then redirect
# (unknown/hidden pair) or render the friendly empty state (no pair exists at all).
# One vote query per page: this pair's counts plus the totals of the candidates.
class PairScreen
  attr_reader :pair, :pair_hash, :percentages, :total_votes, :next_candidates, :show_results, :votes_suffix

  def self.for_hash(pair_hash, show_results: false, votes_suffix: nil)
    build(PairGenerator.pair_by_hash(pair_hash), show_results: show_results, votes_suffix: votes_suffix)
  end

  def self.random
    build(PairGenerator.random_pair)
  end

  def self.of_day
    build(PairGenerator.pair_of_day, votes_suffix: "hoje")
  end

  def self.build(pair, show_results: false, votes_suffix: nil)
    return nil unless valid_pair?(pair)

    new(pair, show_results: show_results, votes_suffix: votes_suffix)
  end

  def self.valid_pair?(pair)
    pair.is_a?(Array) && pair.length == 2 && pair.all? { |option| option&.status == "approved" && option.text.present? } &&
      pair.map(&:id).uniq.length == 2
  end

  def initialize(pair, show_results:, votes_suffix:)
    @pair = pair
    @pair_hash = PairGenerator.hash_for(pair[0], pair[1])
    @show_results = show_results
    @votes_suffix = votes_suffix
    candidates = NextPairSelector.candidates(@pair_hash)
    counts = Vote.counts_for_pairs([ @pair_hash ] + candidates)
    own = counts[@pair_hash] || {}
    @percentages = Vote.percentages_from(own)
    @total_votes = own.values.sum
    totals = candidates.index_with { |hash| (counts[hash] || {}).values.sum }
    @next_candidates = NextPairSelector.least_voted(candidates, totals)
  end

  # Without JS the button goes to the server's first candidate; with none, to the home page.
  def next_href
    next_candidates.any? ? "/pairs/#{next_candidates.first}" : "/"
  end
end
