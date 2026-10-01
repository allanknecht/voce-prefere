require "test_helper"

# Every public poll screen is built by PairScreen + the shared partials, so none of them can
# render an empty card: a complete vote screen (2 option buttons + Enviar sua opção + Par do Dia +
# Polêmicos), a redirect, or the friendly empty state.
class PairScreensTest < ActionDispatch::IntegrationTest
  setup do
    RateLimiter::RateLimit.delete_all
    @good = Array.new(4) { |i| Option.create!(text: "Boa #{i}", status: "approved", category: "good") }
    @bad = Array.new(3) { |i| Option.create!(text: "Ruim #{i}", status: "approved", category: "bad") }
    @pair = PairGenerator.hash_for(@good[0], @good[1])
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  def assert_complete_vote_screen(path = nil)
    assert_response :success, path
    assert_select "#voting-container .vote-button", 2, "#{path}: two option buttons"
    assert_select "#voting-container[data-pair-hash]"
    assert_select "#submit-button", 1
    assert_select "a[href=?]", pairs_day_path, text: /Par do Dia/
    assert_select "a[href=?]", pairs_controversial_path, text: /Polêmicos/
    assert_select "#next-link", 1
    assert_select "#empty-state", 0
    pair_hash = css_select("#voting-container").first["data-pair-hash"]
    assert PairGenerator.pair_by_hash(pair_hash), "#{path}: both options are on the air"
  end

  # ---- every pair screen is complete -------------------------------------------------------------

  test "home, /pairs/:hash, results URL and Par do Dia all render the same complete screen" do
    [ root_path, pair_path(@pair), pair_results_path(@pair), pairs_day_path ].each do |path|
      get path
      assert_complete_vote_screen(path)
      assert_select "#results", 1
      assert_select "#share-button", 1
    end
  end

  test "the screens share the same partials and PairScreen (no per-page copy of the card)" do
    %w[pages/home pairs/show pairs/day].each do |view|
      source = Rails.root.join("app/views/#{view}.html.erb").read
      assert_match(%r{render "shared/voting", screen: @screen}, source, view)
      assert_match(%r{render "shared/poll_footer"}, source, view)
      assert_no_match(/vote-button|<button/, source, view)
    end
    assert_no_match(/vote-button/, Rails.root.join("app/views/pairs/controversial.html.erb").read)
    assert_match(/shared\/pair_bars/, Rails.root.join("app/views/pairs/controversial.html.erb").read)
  end

  test "PairScreen refuses anything that is not two different approved options" do
    hidden = Option.create!(text: "Escondida", status: "rejected", category: "good")
    assert_nil PairScreen.build(nil)
    assert_nil PairScreen.build([])
    assert_nil PairScreen.build([ @good[0], nil ])
    assert_nil PairScreen.build([ @good[0], @good[0] ])
    assert_nil PairScreen.build([ @good[0], hidden ])
    assert PairScreen.build([ @good[0], @good[1] ])
  end

  # ---- missing / hidden options redirect, never an empty card ---------------------------------

  test "a pair whose option was deleted, hidden or never existed redirects (302) to the home page" do
    hidden = Option.create!(text: "Escondida", status: "rejected", category: "good")
    gone = Option.create!(text: "Vai sumir", status: "approved", category: "good")
    stale = PairGenerator.hash_for(@good[0], gone)
    gone.destroy!
    [ PairGenerator.hash_for(@good[0], hidden), stale, "999-998", "1-1", "abc", "5" ].each do |hash|
      [ pair_path(hash), pair_results_path(hash) ].each do |path|
        get path
        assert_response :found, path
        assert_redirected_to root_path
        assert_match(/no-cache/, response.headers["Cache-Control"])
      end
    end
    follow_redirect!
    assert_complete_vote_screen("redirect target")
  end

  test "an option taken off the air while a Próximo link is already on a page: the link lands on a complete screen" do
    get pair_path(@pair)
    target = css_select("#next-link").first["href"]
    victim_ids = target.delete_prefix("/pairs/").split("-").map(&:to_i)
    Option.find(victim_ids.first).update!(status: "rejected")
    get target
    assert_response :found
    follow_redirect!
    assert_complete_vote_screen
  end

  test "Par do Dia redirects home when no pair exists" do
    Option.delete_all
    PairGenerator.expire_caches!
    get pairs_day_path
    assert_redirected_to root_path
  end

  # ---- friendly empty state ---------------------------------------------------------------------------

  test "with no pair available the home page is a friendly full page: message, link and the usual buttons, never an empty card" do
    Option.delete_all
    PairGenerator.expire_caches!
    get root_path
    assert_response :success
    assert_select "#empty-state", 1
    assert_select "#empty-state", text: /Ops!.*Não há opções suficientes ainda/m
    assert_select "#empty-state a[href=?]", root_path
    assert_select "#voting-container", 0
    assert_select "#next-link", 0
    assert_select "#share-button", 0
    assert_select "#submit-button", 1
    assert_select "a[href=?]", pairs_day_path
    assert_select "a[href=?]", pairs_controversial_path
    assert_select "h1", text: /Você prefere\?/ # upper-cased by CSS
  end

  test "a single option in a category gives an empty state only when no category has a pair" do
    Option.where(category: "bad").delete_all
    Option.where(category: "good").where.not(id: @good[0].id).delete_all
    PairGenerator.expire_caches!
    get root_path
    assert_select "#empty-state", 1
    assert_select ".vote-button", 0
  end

  # ---- Próximo is a full document load and always leads to a complete vote screen ---------------------

  test "Próximo, Votar and Ver resultado are plain links with no Turbo content swap (and the app ships no Turbo)" do
    get pair_results_path(@pair)
    %w[#next-link].each { |sel| assert_equal "false", css_select(sel).first["data-turbo"] }
    assert_equal "false", css_select("a[href='#{pair_path(@pair)}']").first["data-turbo"]
    get pair_path(@pair)
    assert_equal "false", css_select("#see-results-link").first["data-turbo"]
    assert_nil css_select("#next-link").first["data-turbo-frame"]
    refute_match(/turbo/i, Rails.root.join("Gemfile.lock").read)
    refute_match(/turbo/i, Rails.root.join("app/assets/javascripts/application.js").read)
    refute_match(/innerHTML|outerHTML|insertAdjacentHTML/, Rails.root.join("app/assets/javascripts/application.js").read)
    assert_select "script:not([src])", 0 # no inline scripts, the only script is the external, deferred one
    assert_select "head script[src][defer]", 1
  end

  test "following Próximo 40 times always lands on a complete vote screen of a different poll" do
    get root_path
    previous = css_select("#voting-container").first["data-pair-hash"]
    40.times do
      get css_select("#next-link").first["href"]
      assert_complete_vote_screen
      current = css_select("#voting-container").first["data-pair-hash"]
      refute_equal previous, current
      assert_equal 1, PairGenerator.pair_by_hash(current).map(&:category).uniq.size
      previous = current
    end
  end

  test "the results view of a poll with no votes is complete too (0%, '0 votos')" do
    get pair_results_path(@pair)
    assert_select "#results:not(.hidden)", 1
    assert_select "#total-votes", text: "0 votos"
    assert_select "[data-option-id$='-percentage']", 2
    assert_select "[data-option-id$='-bar'][data-width='0']", 2
  end

  test "when only one pair exists Próximo points to the home page (which shows a complete screen)" do
    Option.where.not(id: [ @good[0].id, @good[1].id ]).delete_all
    PairGenerator.expire_caches!
    get pair_path(@pair)
    assert_equal "/", css_select("#next-link").first["href"]
    get "/"
    assert_complete_vote_screen
  end

  test "all pair screens stay no-cache and cookie-free" do
    [ root_path, pair_path(@pair), pair_results_path(@pair), pairs_day_path, pairs_controversial_path, "/pairs/999-998" ].each do |path|
      get path
      assert_nil response.headers["Set-Cookie"], path
      cache_control = response.headers["Cache-Control"].to_s
      next if path == pairs_controversial_path # public aggregate, cached for a minute by design

      assert_match(/no-cache/, cache_control, path)
      refute_match(/public/, cache_control, path)
    end
  end
end
