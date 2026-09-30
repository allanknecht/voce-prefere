class VotesController < ApplicationController
  include PublicRequest

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

    option = Option.approved.find_by(id: option_id)

    unless option
      render json: { error: "Opção não encontrada" }, status: :not_found
      return
    end

    # `option:` (already loaded) spares the extra SELECT of the belongs_to presence validation
    Vote.create!(option: option, pair_hash: pair_hash)

    RateLimiter.record(hashed_ip, :vote)

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
