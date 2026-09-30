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

    # No automatic moderation: the option is live immediately, in a good/bad category guessed by
    # OptionClassifier, and waits in the persistent review queue (/admin/review) for the admin
    # to Aprovar or Reprovar it.
    option = Option.new(text: text, status: "approved", needs_review: true)

    if option.save
      RateLimiter.record(hashed_ip, :submit)
      render json: {
        success: true,
        message: "Opção enviada! Já está no ar e será revisada.",
        approved: true
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
