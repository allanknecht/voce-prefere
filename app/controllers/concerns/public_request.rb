# Shared behaviour for the public (anonymous) endpoints.
#
# * Cookie-free: the session is switched off, so no Set-Cookie header is ever sent.
# * CSRF without cookies: because there is no session we cannot use Rails' session
#   based authenticity token. Every state-changing request (vote / submit / report)
#   is instead verified statelessly:
#     1. Sec-Fetch-Site must be "same-origin" (browsers send `Origin: null` under our
#        no-referrer policy, so Origin alone is not usable); only old browsers without
#        that header fall back to an Origin/Referer host comparison (see StatelessCsrf);
#     3. a short-lived, signed, purpose-bound token, embedded in the page as
#        <meta name="form-token"> and echoed by our JS in the X-Form-Token header,
#        must be valid.
#   Cross-site pages cannot forge (1) and (2) from a browser and cannot read our
#   HTML to obtain (3). See PRIVACY.md.
module PublicRequest
  extend ActiveSupport::Concern
  include StatelessCsrf

  FORM_TOKEN_HEADER = "X-Form-Token"
  FORM_TOKEN_TTL = 24.hours
  FORM_TOKEN_PURPOSE = :public_form

  included do
    skip_forgery_protection
    before_action :disable_session
    before_action :verify_public_request, unless: -> { request.get? || request.head? }
    helper_method :public_form_token
  end

  class_methods do
    def form_token_verifier
      Rails.application.message_verifier(:public_form_csrf)
    end
  end

  private

  # Pages that carry a random pair / a per-visitor form token must never be served from a cache
  # (browser, Cloudflare): "private, no-cache" = always revalidate (back/forward still works).
  def no_shared_cache
    response.cache_control.replace(private: true, extras: [ "no-cache", "max-age=0" ])
  end

  def public_form_token
    self.class.form_token_verifier.generate(SecureRandom.hex(8), purpose: FORM_TOKEN_PURPOSE, expires_in: FORM_TOKEN_TTL)
  end

  def disable_session
    request.session_options[:skip] = true
  end

  def verify_public_request
    return if same_origin_request? && valid_form_token?

    render json: { error: "Requisição inválida. Recarregue a página e tente novamente." }, status: :forbidden
  end

  def valid_form_token?
    token = request.headers[FORM_TOKEN_HEADER].to_s
    token.present? && self.class.form_token_verifier.verified(token, purpose: FORM_TOKEN_PURPOSE).present?
  end
end
