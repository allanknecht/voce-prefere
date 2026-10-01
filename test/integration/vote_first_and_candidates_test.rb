require "test_helper"

# The poll page is a VOTE screen by default (even when the pair already has votes); results only
# after voting in the page (JS) or on the explicit results URL. "Próximo" candidates are chosen by
# the server (same category, never the current pair, only options on the air, fewest votes first).
class VoteFirstAndCandidatesTest < ActionDispatch::IntegrationTest
  setup do
    RateLimiter::RateLimit.delete_all
    @good = Array.new(5) { |i| Option.create!(text: "Boa #{i}", status: "approved", category: "good") }
    @bad = Array.new(4) { |i| Option.create!(text: "Ruim #{i}", status: "approved", category: "bad") }
    @pair = PairGenerator.hash_for(@good[0], @good[1])
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  def results_hidden?
    css_select("#results").first["class"].to_s.split.include?("hidden")
  end

  def vote_buttons_hidden?
    css_select("#voting-container > div.space-y-4").first["class"].to_s.split.include?("hidden")
  end

  def candidates
    css_select("#next-link").first["data-candidates"].to_s.split
  end

  # ---- vote screen first ----------------------------------------------------------------------

  test "a pair that already has votes (even 1 vote, 100%) opens as the VOTE screen, with a visible 'Ver resultado' link" do
    Vote.create!(option: @good[0], pair_hash: @pair)
    get pair_path(@pair)
    assert_response :success
    assert results_hidden?, "results must be hidden by default"
    refute vote_buttons_hidden?
    assert_select ".vote-button", 2
    assert_select "a#see-results-link[href=?]", pair_results_path(@pair), text: /Ver resultado/
    assert_nil css_select("#voting-container").first["data-results-shown"]
  end

  test "the explicit results URL shows the results (and a link back to vote), and is not cached" do
    3.times { Vote.create!(option: @good[0], pair_hash: @pair) }
    Vote.create!(option: @good[1], pair_hash: @pair)
    get pair_results_path(@pair)
    assert_response :success
    refute results_hidden?
    assert vote_buttons_hidden?
    assert_select "#voting-container[data-results-shown=true]"
    assert_match(/75.0%/, response.body)
    assert_select "#total-votes", text: "4 votos"
    assert_select "a[href=?]", pair_path(@pair), text: /Votar/
    assert_match(/no-cache/, response.headers["Cache-Control"])
    assert_nil response.headers["Set-Cookie"]
  end

  test "results of a pair that is not on the air redirect home (nothing leaks)" do
    hidden = Option.create!(text: "Fora", status: "rejected", category: "good")
    get pair_results_path(PairGenerator.hash_for(@good[0], hidden))
    assert_redirected_to root_path
    get pair_results_path("999-998")
    assert_redirected_to root_path
  end

  test "home and Par do Dia open as vote screens too, never as results" do
    Vote.create!(option: @good[0], pair_hash: PairGenerator.hash_for(@good[0], @good[1]))
    20.times do
      get root_path
      assert results_hidden?
      refute vote_buttons_hidden?
    end
    get pairs_day_path
    assert results_hidden?
    assert_select ".vote-button", 2
  end

  test "voting through the endpoint still returns the numbers the page swaps in" do
    get pair_path(@pair)
    post votes_path, params: { option_id: @good[0].id, pair_hash: @pair }.to_json, headers: public_post_headers
    assert_response :success
    assert_equal 1, response.parsed_body["total_votes"]
    assert_equal({ @good[0].id.to_s => 100.0 }, response.parsed_body["percentages"])
  end

  # ---- Próximo candidates ----------------------------------------------------------------------------

  test "candidates: same category, never the current pair, all options on the air, first = the href without JS" do
    hidden = Option.create!(text: "Fora do ar", status: "rejected", category: "good")
    30.times do
      get pair_path(@pair)
      list = candidates
      assert_operator list.size, :>=, 1
      assert_operator list.size, :<=, NextPairSelector::LIMIT
      refute_includes list, @pair
      assert_equal list.uniq, list
      list.each do |hash|
        options = PairGenerator.pair_by_hash(hash)
        assert options, "#{hash} must be on the air"
        assert_equal [ "good" ], options.map(&:category).uniq
        refute_includes options.map(&:id), hidden.id
      end
      assert_equal "/pairs/#{list.first}", css_select("#next-link").first["href"]
    end
  end

  test "a bad poll gets bad candidates, a good poll gets good ones" do
    bad_pair = PairGenerator.hash_for(@bad[0], @bad[1])
    get pair_path(bad_pair)
    candidates.each { |h| assert_equal [ "bad" ], PairGenerator.pair_by_hash(h).map(&:category).uniq }
  end

  test "pairs with fewer votes come first" do
    popular = PairGenerator.hash_for(@good[2], @good[3])
    5.times { Vote.create!(option: @good[2], pair_hash: popular) }
    seen = Set.new
    20.times do
      get pair_path(@pair)
      list = candidates
      assert_operator list.size, :>=, 5
      assert_operator list.index(popular).to_i, :>=, list.size - 1 if list.include?(popular) # the most voted is last
      seen << list.first
    end
    refute_includes seen, popular
  end

  test "candidates are served with no extra query besides the pair votes and the cached option list" do
    get pair_path(@pair)
    queries = count_queries { get pair_path(@pair) }
    assert_operator queries.size, :<=, 1, queries.join("\n")
  end

  test "a category with no other pair falls back to the other category so Próximo still leads to a new poll" do
    Option.where(category: "good").where.not(id: [ @good[0].id, @good[1].id ]).delete_all
    PairGenerator.expire_caches!
    get pair_path(@pair)
    assert candidates.any?
    candidates.each { |h| assert_equal [ "bad" ], PairGenerator.pair_by_hash(h).map(&:category).uniq }
  end

  test "pages with candidates stay no-cache and cookie-free" do
    [ root_path, pair_path(@pair), pair_results_path(@pair), pairs_day_path ].each do |path|
      get path
      assert_match(/no-cache/, response.headers["Cache-Control"], path)
      refute_match(/public/, response.headers["Cache-Control"], path)
      assert_nil response.headers["Set-Cookie"], path
    end
  end

  # ---- pluralisation -----------------------------------------------------------------------------------

  test "helpers: 1 voto / N votos, 1 denúncia / N denúncias (0 is plural)" do
    helper = ApplicationController.helpers
    assert_equal "1 voto", helper.votes_label(1)
    assert_equal "0 votos", helper.votes_label(0)
    assert_equal "2 votos", helper.votes_label(2)
    assert_equal "1 voto hoje", helper.votes_label(1, "hoje")
    assert_equal "3 votos hoje", helper.votes_label(3, "hoje")
    assert_equal "1 denúncia", helper.reports_label(1)
    assert_equal "0 denúncias", helper.reports_label(0)
    assert_equal "5 denúncias", helper.reports_label(5)
  end

  test "public pages: '1 voto' in the results (explicit URL) and on Par do Dia, never '1 votos'" do
    Vote.create!(option: @good[0], pair_hash: @pair)
    get pair_results_path(@pair)
    assert_select "#total-votes", text: "1 voto"
    assert_no_match(/\b1 votos\b/, response.body)
    Vote.delete_all
    day = PairGenerator.pair_of_day
    Vote.create!(option: day[0], pair_hash: PairGenerator.hash_for(*day))
    get pairs_day_path
    assert_select "#total-votes", text: "1 voto hoje"
  end

  test "controversial ranking says '1 voto' only for a single vote" do
    html = ApplicationController.render(inline: "<%= votes_label(1) %> | <%= votes_label(20) %>")
    assert_equal "1 voto | 20 votos", html
    source = Rails.root.join("app/views/pairs/controversial.html.erb").read
    assert_match(/votes_label\(pair_data\[:total_votes\]\)/, source)
  end

  test "no view hard-codes a plural next to a count" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].select do |f|
      File.read(f).match?(/%>\s*votos\b|%>\s*denúncias\b/)
    end
    assert_empty offenders
  end

  test "admin: '1 voto' / '1 denúncia' in the options list, the queue and the delete confirmation" do
    option = Option.create!(text: "Singular", status: "approved", category: "good", report_count: 1, needs_review: true)
    other = Option.create!(text: "Outra", status: "approved", category: "good")
    Vote.create!(option: option, pair_hash: PairGenerator.hash_for(option, other))
    https!
    get admin_login_path
    token = css_select("input[name=login_token]").first["value"]
    post admin_login_path, params: { secret: AdminSecret.value, login_token: token }, headers: { "Sec-Fetch-Site" => "same-origin" }
    assert_redirected_to admin_index_path
    get admin_options_path
    assert_match(/1 voto • 1 denúncia/, response.body)
    assert_no_match(/1 votos|1 denúncias/, response.body)
    get admin_review_path
    assert_match(/1 denúncia\b/, response.body)
    assert_match(/• 1 voto\b/, response.body)
    assert_no_match(/1 votos|1 denúncias/, response.body)
    get confirm_delete_admin_option_path(option)
    assert_match(/1 voto\b/, response.body)
    assert_match(/1 denúncia\b/, response.body)
  end
end
