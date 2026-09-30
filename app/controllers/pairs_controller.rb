class PairsController < ApplicationController
  include PublicRequest
  include PublicCaching

  def show
    pair_hash = params[:id]
    @pair = PairGenerator.pair_by_hash(pair_hash)

    unless @pair
      redirect_to root_path
      return
    end

    no_shared_cache
    @pair_hash = pair_hash
    @next_pair = PairGenerator.next_pair(pair_hash)
    @percentages, @total_votes = Vote.pair_summary(pair_hash)
  end

  # Public aggregate, the same for every visitor (and cached in memory by PairGenerator).
  def controversial
    @controversial_pairs = PairGenerator.controversial_pairs(limit: 20, min_votes: 10)
    cache_publicly(1.minute)
  end

  def day
    @pair = PairGenerator.pair_of_day

    unless @pair
      redirect_to root_path
      return
    end

    no_shared_cache
    @pair_hash = PairGenerator.hash_for(@pair[0], @pair[1])
    @percentages, @total_votes = Vote.pair_summary(@pair_hash)
  end
end
