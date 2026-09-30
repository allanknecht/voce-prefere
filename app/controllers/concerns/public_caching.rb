# HTTP caching for public GET pages that are identical for every visitor.
#
# Only for pages that carry no per-visitor content: no Set-Cookie (public pages have no
# session), no form token (the pages using this skip the <meta name="form-token"> tag, see
# the layout) and no random pair. Never use it for the home page or anything with a form.
#
# Sends `Cache-Control: public, max-age=N` plus a strong ETag (page content + the digested
# asset URLs, so a deploy invalidates it), so revalidation is a cheap 304.
module PublicCaching
  extend ActiveSupport::Concern

  private

  def cache_publicly(max_age)
    @skip_form_token = true
    expires_in max_age, public: true
    fresh_when etag: [ view_context.asset_path("tailwind.css"), view_context.asset_path("application.js"), @controversial_pairs&.map { |pair| [ pair[:pair_hash], pair[:percentages] ] } ]
  end
end
