# Real HTTP security headers (browsers ignore most of these as <meta http-equiv>).
#
# * Content-Security-Policy ....... config/initializers/content_security_policy.rb
# * Strict-Transport-Security ..... config.force_ssl / config.ssl_options in config/environments/production.rb
# * Permissions-Policy, X-Content-Type-Options, X-Frame-Options, Referrer-Policy ... below
#   (Rails' own permissions_policy DSL only emits the obsolete "Feature-Policy" header,
#   so the modern Permissions-Policy header is set here directly.)
PERMISSIONS_POLICY = [
  "accelerometer=()", "autoplay=()", "camera=()", "display-capture=()", "encrypted-media=()",
  "geolocation=()", "gyroscope=()", "hid=()", "idle-detection=()", "magnetometer=()", "microphone=()",
  "midi=()", "payment=()", "picture-in-picture=()", "serial=()", "usb=()",
  "web-share=(self)" # our own "Compartilhar" button
].join(", ").freeze

Rails.application.config.action_dispatch.default_headers = {
  "Permissions-Policy" => PERMISSIONS_POLICY,
  "X-Frame-Options" => "DENY",
  "X-Content-Type-Options" => "nosniff",
  "Referrer-Policy" => "no-referrer",
  "Cross-Origin-Opener-Policy" => "same-origin",
  "Cross-Origin-Resource-Policy" => "same-origin",
  # The legacy XSS auditor is removed from browsers and was itself exploitable: keep it off.
  "X-XSS-Protection" => "0"
}
