class PagesController < ApplicationController
  include PublicRequest
  include PublicCaching
  include PairPage

  # The random pair MUST stay random per request, so the home page is never cached.
  def home
    no_shared_cache
    @pair = PairGenerator.random_pair

    load_pair_page(PairGenerator.hash_for(@pair[0], @pair[1])) if @pair
  end

  # Static, identical for every visitor: cacheable by browsers and shared caches.
  def about
    cache_publicly(10.minutes)
  end
end
