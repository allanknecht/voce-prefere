class PairsController < ApplicationController
  include PublicRequest

  def show
    pair_hash = params[:id]
    @pair = PairGenerator.pair_by_hash(pair_hash)

    unless @pair
      redirect_to root_path
      return
    end

    @pair_hash = pair_hash
    @percentages = Vote.pair_stats(pair_hash)
    @total_votes = Vote.where(pair_hash: pair_hash).count
  end

  def controversial
    @controversial_pairs = PairGenerator.controversial_pairs(limit: 20, min_votes: 10)
  end

  def day
    @pair = PairGenerator.pair_of_day

    unless @pair
      redirect_to root_path
      return
    end

    @pair_hash = generate_pair_hash(@pair[0], @pair[1])
    @percentages = Vote.pair_stats(@pair_hash)
    @total_votes = Vote.where(pair_hash: @pair_hash).count
  end

  private

  def generate_pair_hash(option1, option2)
    [ option1.id, option2.id ].sort.join("-")
  end
end
