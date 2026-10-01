class PairsController < ApplicationController
  include PublicRequest
  include PublicCaching
  include PairPage

  # The VOTE screen, even when the pair already has votes (results only after voting here, or
  # on the explicit results URL below).
  def show
    return unless load_pair(params[:id])

    @show_results = false
  end

  # Explicit results link ("Ver resultado", shared result links).
  def results
    return unless load_pair(params[:id])

    @show_results = true
    render :show
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
    load_pair_page(PairGenerator.hash_for(@pair[0], @pair[1]))
  end

  private

  # false (after redirecting to the home page) when the pair does not exist / is not on the air
  def load_pair(pair_hash)
    @pair = PairGenerator.pair_by_hash(pair_hash)

    unless @pair
      redirect_to root_path
      return false
    end

    no_shared_cache
    load_pair_page(pair_hash)
    true
  end
end
