class PagesController < ApplicationController
  include PublicRequest
  include PublicCaching

  # The random pair MUST stay random per request, so the home page is never cached.
  def home
    no_shared_cache
    @pair = PairGenerator.random_pair

    if @pair
      @pair_hash = PairGenerator.hash_for(@pair[0], @pair[1])
      @next_pair = PairGenerator.next_pair(@pair_hash)
      @percentages, @total_votes = Vote.pair_summary(@pair_hash)
    end
  end

  # Static, identical for every visitor: cacheable by browsers and shared caches.
  def about
    cache_publicly(10.minutes)
  end
end
