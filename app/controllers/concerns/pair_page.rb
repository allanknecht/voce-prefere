# Shared by the pages that show one poll (home, /pairs/:hash, /pairs/:hash/results, /pairs/day).
#
# The poll is shown as a VOTE screen. Results appear only after the visitor voted on that page
# (client side, the vote response) or on the explicit results URL (/pairs/:hash/results).
# Everything the page needs comes from ONE vote query: the current pair's summary and the vote
# totals of the candidate "Próximo" pairs (used to prefer the least voted ones).
module PairPage
  extend ActiveSupport::Concern

  private

  def load_pair_page(pair_hash)
    @pair_hash = pair_hash
    candidates = PairGenerator.next_candidates(pair_hash)
    counts = Vote.counts_for_pairs([ pair_hash ] + candidates)
    @percentages = Vote.percentages_from(counts[pair_hash] || {})
    @total_votes = (counts[pair_hash] || {}).values.sum
    totals = candidates.index_with { |hash| (counts[hash] || {}).values.sum }
    @next_candidates = PairGenerator.pick_candidates(candidates, totals)
  end
end
