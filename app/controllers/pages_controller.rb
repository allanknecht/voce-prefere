class PagesController < ApplicationController
  include PublicRequest

  def home
    @pair = PairGenerator.random_pair

    if @pair
      @pair_hash = generate_pair_hash(@pair[0], @pair[1])
      @percentages = Vote.pair_stats(@pair_hash)
      @total_votes = Vote.where(pair_hash: @pair_hash).count
    end
  end

  def about
  end

  private

  def generate_pair_hash(option1, option2)
    [ option1.id, option2.id ].sort.join("-")
  end
end
