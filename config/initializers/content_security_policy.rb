# Content Security Policy, sent as a real HTTP header.
#
# The site has NO inline scripts and NO inline styles: all JavaScript lives in
# app/assets/javascripts/application.js and all CSS in the compiled Tailwind
# stylesheet, so 'unsafe-inline' is not needed (and no nonces are required).
# Nothing third-party is allowed: no analytics, no CDN, no captcha
# (Cloudflare Turnstile is NOT integrated, so challenges.cloudflare.com is not listed).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :none
    policy.script_src      :self
    policy.style_src       :self
    policy.img_src         :self, :data
    policy.font_src        :self
    policy.connect_src     :self
    policy.manifest_src    :self
    policy.object_src      :none
    policy.frame_src       :none
    policy.child_src       :none
    policy.worker_src      :none
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :none
    policy.upgrade_insecure_requests true if Rails.env.production?
  end

  config.content_security_policy_report_only = false
end
