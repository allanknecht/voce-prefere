# The only cookie this app ever sets is the admin session cookie:
#   * only sent to /admin (Path=/admin), so it never touches public pages;
#   * HttpOnly, SameSite=Strict, Secure (everywhere except local development over http);
#   * expires with the browser session / after 1 hour.
# Public pages run with the session disabled and never send Set-Cookie (see PublicRequest).
Rails.application.config.session_store :cookie_store,
  key: "_voce_prefere_admin",
  path: "/admin",
  httponly: true,
  same_site: :strict,
  secure: !Rails.env.development?,
  expire_after: 1.hour
