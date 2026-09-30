class OptionsController < ApplicationController
  include PublicRequest

  def create
    # Rate limiting
    unless RateLimiter.check(hashed_ip, :submit)
      render json: { error: "Muitas tentativas. Aguarde um pouco." }, status: :too_many_requests
      return
    end

    text = params[:text].to_s.strip

    if text.blank? || text.length > 120
      render json: { error: "Texto inválido (máx 120 caracteres)" }, status: :unprocessable_entity
      return
    end

    # Content moderation
    moderation = ContentModerator.check(text)

    option = Option.new(
      text: text,
      status: moderation[:approved] ? "approved" : "pending",
      category: params[:category].to_s.strip.first(50).presence
    )

    if option.save
      RateLimiter.record(hashed_ip, :submit)
      render json: {
        success: true,
        message: moderation[:approved] ? "Opção enviada!" : "Opção enviada para moderação",
        approved: moderation[:approved]
      }
    else
      render json: { error: option.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def report
    # Rate limiting
    unless RateLimiter.check(hashed_ip, :report)
      render json: { error: "Muitas tentativas. Aguarde um pouco." }, status: :too_many_requests
      return
    end

    option = Option.find_by(id: params[:id])

    unless option
      render json: { error: "Opção não encontrada" }, status: :not_found
      return
    end

    option.report!
    RateLimiter.record(hashed_ip, :report)

    render json: { success: true, message: "Denúncia registrada" }
  end

  private

  def hashed_ip
    request.remote_ip
  end
end
