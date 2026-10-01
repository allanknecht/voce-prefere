class VotesController < ApplicationController
  include PublicRequest

  # A second vote on the same pair from the same (hashed) visitor within this window is treated
  # as a double click / retry: same success response, not counted. No cookie, no new personal data
  # (only a salted hash of ip+pair with a 10 s expiry, in the rate_limits table).
  DUPLICATE_WINDOW = 10.seconds

  def create
    # Rate limiting
    unless RateLimiter.check(hashed_ip, :vote)
      render json: { error: "Muitas votações. Aguarde um pouco." }, status: :too_many_requests
      return
    end

    option_id = params[:option_id].to_s.to_i
    pair_hash = params[:pair_hash].to_s

    unless option_id.positive? && pair_hash.match?(/\A\d{1,18}-\d{1,18}\z/) && pair_hash.split("-").map(&:to_i).include?(option_id)
      render json: { error: "Parâmetros inválidos" }, status: :unprocessable_entity
      return
    end

    # From the in-memory list of approved options (dropped whenever an option changes): no query
    option = PairGenerator.approved_option(option_id)

    unless option
      render json: { error: "Opção não encontrada" }, status: :not_found
      return
    end

    # One statement: claims the (visitor, pair) slot, or tells us it was claimed < 10 s ago.
    if RateLimiter.claim_once(hashed_ip, "vote_pair:#{pair_hash}", DUPLICATE_WINDOW)
      Vote.create!(option: option, pair_hash: pair_hash)
      RateLimiter.record(hashed_ip, :vote)
      Analytics.record_event(request, "vote", pair_hash: pair_hash, option_id: option.id)
    end

    # Updated percentages and total from ONE grouped query
    percentages, total_votes = Vote.pair_summary(pair_hash)

    render json: {
      success: true,
      percentages: percentages,
      total_votes: total_votes
    }
  rescue => e
    Rails.logger.error("Vote creation error: #{e.message}")
    render json: { error: "Erro ao registrar voto" }, status: :internal_server_error
  end

  private

  def hashed_ip
    request.remote_ip
  end
end
