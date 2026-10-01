class PairsController < ApplicationController
  include PublicRequest
  include PublicCaching

  # The VOTE screen, even when the pair already has votes (results only after voting here, or
  # on the explicit results URL below).
  def show
    load_screen(params[:id], show_results: false)
  end

  # Explicit results link ("Ver resultado", shared result links).
  def results
    render :show if load_screen(params[:id], show_results: true)
  end

  # Public aggregate, the same for every visitor (and cached in memory by PairGenerator).
  def controversial
    @controversial_pairs = PairGenerator.controversial_pairs(limit: 20, min_votes: 10)
    cache_publicly(1.minute)
  end

  def day
    no_shared_cache
    @screen = PairScreen.of_day
    redirect_to root_path, status: :found unless @screen
  end

  private

  # A pair that does not exist, or whose option was deleted / hidden / is not approved, never
  # renders a card: it redirects (302) to the home page, which always shows a complete screen
  # (a random valid poll, or the friendly empty state).
  def load_screen(pair_hash, show_results:)
    no_shared_cache
    @screen = PairScreen.for_hash(pair_hash, show_results: show_results)
    redirect_to root_path, status: :found unless @screen
    @screen.present?
  end
end
