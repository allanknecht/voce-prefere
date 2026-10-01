class PagesController < ApplicationController
  include PublicRequest
  include PublicCaching

  # The random pair MUST stay random per request, so the home page is never cached.
  # With no pair at all the page renders the friendly empty state (never an empty card).
  def home
    no_shared_cache
    @screen = PairScreen.random
  end

  # Static, identical for every visitor: cacheable by browsers and shared caches.
  def about
    cache_publicly(10.minutes)
  end
end
